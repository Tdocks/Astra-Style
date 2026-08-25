// ============================================================================
// style-dna/context.ts
// ============================================================================
// Turns the three stored profile rows into the context packet a
// `StylistReasoningProvider` call carries
// (`docs/06-kyra-orchestration.md` §1.6, `docs/08-provider-abstraction.md` §1).
//
// It exists as its own module for two reasons. First, retrieval and reasoning
// are separately testable: `context_test.ts` can prove that a row with five
// null measurements produces `hasAnyMeasurement: false` without involving a
// provider at all. Second, when the live adapter lands, THIS is the shape
// that gets serialized into a prompt — so the decision about what the model
// is allowed to see lives in one file, which is where a privacy review
// (§29, and spec §14's "avoid logging full prompt contents") can look at it.
//
// WHAT IS DELIBERATELY NOT IN THE PACKET.
//
//  • Nothing that identifies the user. No user id, no display name, no email,
//    no reference-selfie storage paths. A stylist reasoning call needs to
//    know that a man wears a suit four days a week; it never needs to know
//    who he is. Keeping identity out means a future prompt log, a vendor's
//    retention window, or a support export cannot leak one.
//  • No raw measurements. `body_profiles` holds chest, waist, inseam and neck
//    in centimetres; the packet carries only the DERIVED frame axes the
//    database already computes (`derive_frame_axes()`,
//    20260729120000_frame_profile.sql) plus a boolean for whether anything
//    was measured at all. The axes are what any advice would actually use,
//    and spec §11's guardrail against implying exact fit is easier to hold
//    when the exact numbers were never in the prompt to begin with.
// ============================================================================

export interface PreferenceAxisReading {
  readonly score: number | null;
  readonly confidence: string;
  readonly observations: number;
  readonly agreement: number | null;
}

export interface FrameAxis {
  readonly value: string;
  /** 0-1, from `body_profiles.frame_*_confidence`. */
  readonly confidence: number;
}

export interface StyleDnaContext {
  readonly identity: {
    readonly primary: string | null;
    readonly secondaries: readonly string[];
  };
  readonly goals: readonly string[];
  readonly preferredFit: string | null;
  readonly vector: {
    readonly comparisonsAnswered: number;
    readonly comparisonsOffered: number;
    /**
     * ONLY the axes the comparison set could actually probe. An axis with no
     * entry here was never asked about; an axis present with
     * `observations === 0` was asked and drew no preference. Both facts are
     * load-bearing downstream and the difference is preserved end to end —
     * see 20260730180000_style_preference_vector.sql.
     */
    readonly dimensions: Readonly<Record<string, PreferenceAxisReading>>;
  };
  readonly body: {
    readonly hasAnyMeasurement: boolean;
    readonly fitNotes: readonly string[];
    readonly taper: FrameAxis | null;
    readonly proportion: FrameAxis | null;
    readonly scale: FrameAxis | null;
    /** Depth (light through deepest) and undertone both change palette advice. */
    readonly skinTone: string | null;
    readonly skinUndertone: string | null;
  };
  readonly lifestyle: {
    readonly occupationCategory: string | null;
    readonly dressCode: string | null;
    readonly typicalWeek: string | null;
    readonly commonOccasions: readonly string[];
    readonly monthlyBudget: number | null;
    readonly currency: string | null;
    readonly preferredBrands: readonly string[];
    readonly avoidedBrands: readonly string[];
    readonly laundryCadence: string | null;
    readonly travelFrequency: string | null;
    readonly sustainabilityPreference: string | null;
  };
}

type Row = Record<string, unknown> | null | undefined;

function str(row: Row, key: string): string | null {
  const value = row?.[key];
  return typeof value === "string" && value.length > 0 ? value : null;
}

function num(row: Row, key: string): number | null {
  const value = row?.[key];
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  // PostgREST returns `numeric` as a STRING to avoid the precision loss a
  // JavaScript double would introduce (monthly_budget is numeric(10,2)).
  // Reading only `typeof value === "number"` would silently drop every
  // budget and every measurement — the exact class of bug BodyProfile.swift's
  // header describes, where "all nil" is indistinguishable from "not
  // answered".
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function stringList(row: Row, key: string): string[] {
  const value = row?.[key];
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter((entry): entry is string => typeof entry === "string" && entry.length > 0);
}

function frameAxis(row: Row, valueKey: string, confidenceKey: string): FrameAxis | null {
  const value = str(row, valueKey);
  if (value === null) {
    return null;
  }
  const confidence = num(row, confidenceKey);
  // A derived axis with no confidence is treated as no axis rather than as a
  // certain one. `derive_frame_axes()` always writes the pair together, so
  // this only fires on a row written before that trigger existed — where
  // assuming confidence would be assuming a measurement.
  return confidence === null ? null : { value, confidence };
}

function readVector(raw: unknown): StyleDnaContext["vector"] {
  const empty = { comparisonsAnswered: 0, comparisonsOffered: 0, dimensions: {} };
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    return empty;
  }
  const record = raw as Record<string, unknown>;
  const rawDimensions = record["dimensions"];
  const dimensions: Record<string, PreferenceAxisReading> = {};
  if (
    rawDimensions !== null && typeof rawDimensions === "object" && !Array.isArray(rawDimensions)
  ) {
    for (const [axis, value] of Object.entries(rawDimensions as Record<string, unknown>)) {
      if (value === null || typeof value !== "object" || Array.isArray(value)) {
        continue;
      }
      const reading = value as Record<string, unknown>;
      const score = typeof reading["score"] === "number" ? reading["score"] as number : null;
      const observations = typeof reading["observations"] === "number"
        ? reading["observations"] as number
        : 0;
      const agreement = typeof reading["agreement"] === "number"
        ? reading["agreement"] as number
        : null;
      const confidence = typeof reading["confidence"] === "string"
        ? reading["confidence"] as string
        : "insufficient";
      // Kept even when `observations === 0` and `score === null`. That
      // reading is the record of an axis that WAS asked about and drew no
      // preference, which is different from an axis that is missing here —
      // and the composer uses the difference to decide what to put in
      // `open_questions` (asking again about an axis he already declined is
      // worse than not asking).
      dimensions[axis] = { score, confidence, observations, agreement };
    }
  }
  const count = (key: string): number => {
    const value = record[key];
    return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : 0;
  };
  return {
    comparisonsAnswered: count("comparisons_answered"),
    comparisonsOffered: count("comparisons_offered"),
    dimensions,
  };
}

/**
 * Builds the packet from the three rows, any or all of which may be absent —
 * a user who skipped every optional step has a `style_profiles` row and two
 * empty ones, and a user whose Style DNA is regenerated before onboarding
 * finished may have none at all.
 */
export function buildStyleDnaContext(
  styleRow: Row,
  bodyRow: Row,
  lifestyleRow: Row,
): StyleDnaContext {
  const appearance = bodyRow?.["appearance"];
  const appearanceRecord =
    appearance !== null && typeof appearance === "object" && !Array.isArray(appearance)
      ? appearance as Record<string, unknown>
      : {};

  return {
    identity: {
      primary: str(styleRow, "primary_identity"),
      secondaries: stringList(styleRow, "secondary_identities"),
    },
    goals: stringList(styleRow, "style_goals"),
    preferredFit: str(styleRow, "preferred_fit"),
    vector: readVector(styleRow?.["preference_vector"] ?? null),
    body: {
      hasAnyMeasurement: [
        "height_value_cm",
        "weight_value_kg",
        "chest_cm",
        "waist_cm",
        "inseam_cm",
        "neck_cm",
      ]
        .some((key) => num(bodyRow, key) !== null),
      fitNotes: stringList(bodyRow, "fit_notes"),
      taper: frameAxis(bodyRow, "frame_taper", "frame_taper_confidence"),
      proportion: frameAxis(bodyRow, "frame_proportion", "frame_proportion_confidence"),
      scale: frameAxis(bodyRow, "frame_scale", "frame_scale_confidence"),
      skinTone: typeof appearanceRecord["skin_tone"] === "string"
        ? appearanceRecord["skin_tone"] as string
        : null,
      skinUndertone: typeof appearanceRecord["skin_undertone"] === "string"
        ? appearanceRecord["skin_undertone"] as string
        : null,
    },
    lifestyle: {
      occupationCategory: str(lifestyleRow, "occupation_category"),
      dressCode: str(lifestyleRow, "dress_code"),
      typicalWeek: str(lifestyleRow, "typical_week"),
      commonOccasions: stringList(lifestyleRow, "common_occasions"),
      monthlyBudget: num(lifestyleRow, "monthly_budget"),
      currency: str(lifestyleRow, "currency"),
      preferredBrands: stringList(lifestyleRow, "preferred_brands"),
      avoidedBrands: stringList(lifestyleRow, "avoided_brands"),
      laundryCadence: str(lifestyleRow, "laundry_cadence"),
      travelFrequency: str(lifestyleRow, "travel_frequency"),
      sustainabilityPreference: str(lifestyleRow, "sustainability_preference"),
    },
  };
}

/** How much weight one axis of the preference vector has earned. */
export function confidenceWeight(confidence: string): number {
  switch (confidence) {
    // Mirrors `PreferenceConfidence` on the client, including its rule that
    // `.moderate` is the bar at which a preference may be stated back to the
    // user as something he said rather than something Kyra guessed
    // (`PreferenceConfidence.isStatable`). Below that the axis still nudges a
    // number, because a nudge is not a claim — it just never becomes a
    // sentence.
    case "high":
      return 0.8;
    case "moderate":
      return 0.5;
    case "low":
      return 0.25;
    default:
      return 0;
  }
}

/** True when this axis may be stated back to the user in prose, not just used as a nudge. */
export function isStatable(reading: PreferenceAxisReading | undefined): boolean {
  if (reading === undefined || reading.score === null) {
    return false;
  }
  return reading.confidence === "moderate" || reading.confidence === "high";
}
