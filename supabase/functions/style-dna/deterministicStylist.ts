// ============================================================================
// style-dna/deterministicStylist.ts
// ============================================================================
// A `StylistReasoningProvider` (spec §8, `docs/08-provider-abstraction.md` §1)
// that produces Style DNA from the context packet with no model call at all.
//
// WHY THE MOCK IS FIRST AND THE LIVE ADAPTER SECOND.
//
// P2-CORE-02 says so ("implement a mock (fixture-based) and one live
// adapter"), ADR 0004 requires the seam regardless ("Every provider has ...
// a mock implementation behind the same protocol for use when a vendor key is
// unavailable"), and there is a third reason worth naming: the acceptance
// criterion this ticket is actually judged on is "a profile with only
// required fields filled produces a coherent, non-empty result". That is a
// statement about degradation behaviour, and degradation behaviour is far
// easier to get right — and to TEST — in code that is deterministic. Every
// sparse-input case below is covered by an assertion, not by an eval run.
//
// WHAT MAKES THIS A USEFUL MOCK RATHER THAN A PLACEHOLDER.
//
// `docs/01-build-roadmap.md`'s Phase 2 risk list names the failure mode
// exactly: "a technically-working endpoint can still produce generic or
// repetitive output". So this composer is built on one rule:
//
//   EVERY SENTENCE IT EMITS IS TRACEABLE TO AN INPUT THE USER ACTUALLY GAVE,
//   AND AN INPUT THAT IS MISSING PRODUCES A SHORTER RESULT, NOT AN INVENTED
//   ONE.
//
// A man who picked Quiet Luxury and nothing else gets a Quiet Luxury palette,
// a Quiet Luxury silhouette direction, three Quiet Luxury signature pieces,
// and an `open_questions` list naming what would sharpen it. A man who also
// gave a dress code, a week shape and four measured preference axes gets all
// of that plus advice that names those inputs back to him. Neither is padded
// to look like the other.
//
// The corollary matters as much: `known_inputs` and `open_questions` are not
// decoration. They are what stops a thin result from reading as a complete
// one, which is the specific dishonesty
// 20260730180000_style_preference_vector.sql and
// ios/.../StylePreferenceVector.swift were both written to prevent, applied
// here at the point where those numbers become prose.
//
// COPY RULES: see identityPlaybook.ts's header. The garment is the subject of
// every sentence, "flattering" never appears, and no string here names a
// ticket, a model, a vendor, or the word "AI".
// ============================================================================

import type {
  StylistCompletionRequest,
  StylistCompletionResult,
  StylistReasoningProvider,
} from "../_shared/providers/stylistReasoning.ts";
import { ProviderError, type ProviderRequestContext } from "../_shared/providers/types.ts";
import {
  confidenceWeight,
  isStatable,
  type PreferenceAxisReading,
  type StyleDnaContext,
} from "./context.ts";
import {
  ACCESSORY_PREFERENCES,
  type AccessoryPreferenceValue,
  FORMALITY_LEVELS,
  type FormalityValue,
  type NamedRecommendation,
  type RankedRecommendation,
  type StyleDnaDocument,
} from "./schema.ts";
import { DRESS_CODE_SIGNATURES, IDENTITY_PLAYBOOK, WOMENSWEAR_PRIORITIES, WOMENSWEAR_SIGNATURES, WOMENSWEAR_SILHOUETTE_FRAMING } from "./identityPlaybook.ts";

/**
 * The version string this provider reports as `modelIdentifier`.
 *
 * Versioned like a model on purpose. When output changes — a palette is
 * retuned, a priority is reworded — the stored `model_identifier` on results
 * generated before the change still says which content produced them, which
 * is the same property a vendor version string buys.
 */
export const DETERMINISTIC_STYLIST_VERSION = "astra-deterministic-stylist/1";

// The eight axes of spec §6.9, in the order `StyleDimension.allCases`
// declares them, with the plain nouns `StyleDimension.displayName` uses for
// mid-sentence copy. Duplicated from Swift rather than shared because there
// is no shared artifact between a Deno function and an iOS target; the raw
// values are pinned by a test in both places.
const AXIS_LABELS: Readonly<Record<string, string>> = {
  colour_tolerance: "colour",
  formality: "formality",
  silhouette: "cut",
  texture: "texture",
  logo_tolerance: "branding",
  trend_tolerance: "how current you like things",
  accessory_preference: "accessories",
  contrast_preference: "contrast",
};

const CANONICAL_AXES = Object.keys(AXIS_LABELS);

/** Where each dress code sits on the five-point formality scale. */
const DRESS_CODE_FORMALITY: Readonly<Record<string, number>> = {
  ultra_casual: 0,
  casual: 1,
  athletic: 1,
  smart_casual: 2,
  business_casual: 2,
  business_formal: 3,
  formal: 4,
  black_tie: 4,
};

/**
 * The identity a dress code implies, used ONLY when §6.5's identity step was
 * skipped — which the flow does not currently allow, but a profile written by
 * an earlier build or a partial migration can still present.
 *
 * Every entry here is a guess, and the composer labels it as one in
 * `identity_basis` rather than presenting it in the same voice as a choice
 * the user made. That labelling is the difference between a helpful fallback
 * and a fabrication.
 */
const DRESS_CODE_IDENTITY: Readonly<Record<string, string>> = {
  black_tie: "executive",
  formal: "executive",
  business_formal: "executive",
  business_casual: "smart_casual",
  smart_casual: "smart_casual",
  casual: "classic_americana",
  ultra_casual: "rugged_utility",
  athletic: "luxury_streetwear",
};

const DRESS_CODE_LABELS: Readonly<Record<string, string>> = {
  ultra_casual: "ultra casual",
  casual: "casual",
  smart_casual: "smart casual",
  business_casual: "business casual",
  business_formal: "business formal",
  black_tie: "black tie",
  formal: "formal",
  athletic: "athletic",
};

/** One wardrobe priority per §6.4 goal, in the goal's own words back to him. */
const GOAL_PRIORITIES: Readonly<Record<string, NamedRecommendation>> = {
  dress_better_daily: {
    title: "Settle on one outfit you can repeat",
    reason:
      "You said you want to dress better day to day. A default that works removes the decision on the mornings there is no time to make one.",
  },
  build_complete_wardrobe: {
    title: "Fill the gaps before adding variety",
    reason:
      "You said you want a complete wardrobe. That means counting what a full week needs before anything is added for interest.",
  },
  improve_professional_image: {
    title: "Get the work half of the week right first",
    reason:
      "You said your professional image matters. Those are the outfits the most people see, most often.",
  },
  prepare_for_social_events: {
    title: "One evening outfit that always works",
    reason:
      "You said dates and social events. A single settled answer beats five options that get second-guessed at the door.",
  },
  find_signature_style: {
    title: "Narrow the palette before widening the wardrobe",
    reason:
      "You said you want a signature style. A signature is a small set of things repeated, not a wide set worn once each.",
  },
  shop_more_intelligently: {
    title: "Replace rather than accumulate",
    reason:
      "You said you want to shop more intelligently. The question becomes what a purchase unlocks, not whether it is nice.",
  },
  dress_for_changing_body: {
    title: "Favour cloth that can be altered",
    reason:
      "You said you are dressing for a changing body. Woven cloth with seam allowance can be taken in and let out; most knitwear cannot.",
  },
  pack_and_travel_better: {
    title: "Keep one palette that all packs together",
    reason:
      "You said packing and travel. Pieces that share a palette roughly halve what has to go in the bag.",
  },
};

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

/**
 * Trims text to `max` characters at a word boundary.
 *
 * Used wherever a user's own free text is echoed back inside a generated
 * sentence. `typical_week` and the occasion list are free-form, so without
 * this a long answer would push a `reason` past the length the response
 * validator enforces — and a provider whose output its own validator rejects
 * is a 502 for a request that had nothing wrong with it.
 */
function clip(text: string, max: number): string {
  const collapsed = text.replace(/\s+/g, " ").trim();
  if (collapsed.length <= max) {
    return collapsed;
  }
  const cut = collapsed.slice(0, max);
  const lastSpace = cut.lastIndexOf(" ");
  return (lastSpace > max * 0.6 ? cut.slice(0, lastSpace) : cut).trimEnd() + "…";
}

/** Joins with commas and a final "and", as the copy elsewhere in the app does. */
function listSentence(items: readonly string[]): string {
  if (items.length === 0) return "";
  if (items.length === 1) return items[0] ?? "";
  const head = items.slice(0, -1).join(", ");
  return `${head} and ${items[items.length - 1]}`;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function axis(context: StyleDnaContext, name: string): PreferenceAxisReading | undefined {
  return context.vector.dimensions[name];
}

/**
 * How far along an axis to move a baseline, given how much the axis has
 * actually earned.
 *
 * `score` alone would treat one comparison exactly like six agreeing ones —
 * the failure `StylePreferenceInference.swift`'s header spends its length
 * warning about. Multiplying by the confidence weight is what keeps a single
 * forced choice a nudge instead of a verdict, and it is why an axis with
 * `confidence: "insufficient"` (weight 0) moves nothing at all while still
 * being recorded as asked.
 */
function axisPull(context: StyleDnaContext, name: string): number {
  const reading = axis(context, name);
  if (reading === undefined || reading.score === null) {
    return 0;
  }
  return reading.score * confidenceWeight(reading.confidence);
}

// ---------------------------------------------------------------------------
// The composer
// ---------------------------------------------------------------------------

interface ResolvedIdentity {
  primary: string | null;
  basis: string;
  /** True when the identity came from a dress code rather than from §6.5. */
  inferred: boolean;
}

function resolveIdentity(context: StyleDnaContext): ResolvedIdentity {
  const stated = context.identity.primary;
  if (stated !== null && IDENTITY_PLAYBOOK[stated] !== undefined) {
    return {
      primary: stated,
      basis: "the identity you ranked first",
      inferred: false,
    };
  }

  const dressCode = context.lifestyle.dressCode;
  if (dressCode !== null) {
    const inferredIdentity = DRESS_CODE_IDENTITY[dressCode];
    if (inferredIdentity !== undefined) {
      return {
        primary: inferredIdentity,
        basis: `your ${
          DRESS_CODE_LABELS[dressCode] ?? dressCode
        } dress code — the identity step has not been answered, so this is a starting point rather than your choice`,
        inferred: true,
      };
    }
  }

  // No identity and no dress code. Returning null and saying so is the only
  // honest option: picking one anyway would put a fabricated answer in the
  // most prominent field on the §6.10 screen, where it reads as something
  // the user told us.
  return {
    primary: null,
    basis: "nothing yet — the identity step and the dress code question are both unanswered",
    inferred: false,
  };
}

function resolveSecondaries(
  context: StyleDnaContext,
  primary: string | null,
): { values: string[]; inferred: boolean } {
  const stated = context.identity.secondaries
    .filter((identity) => identity !== primary && IDENTITY_PLAYBOOK[identity] !== undefined);
  if (stated.length > 0) {
    return { values: stated.slice(0, 3), inferred: false };
  }
  if (primary === null) {
    return { values: [], inferred: false };
  }
  const playbook = IDENTITY_PLAYBOOK[primary];
  return {
    values: (playbook?.neighbours ?? []).filter((identity) => identity !== primary).slice(0, 2),
    inferred: true,
  };
}

function composePalette(
  context: StyleDnaContext,
  primary: string | null,
): StyleDnaDocument["palette"] {
  if (primary === null) {
    return {
      preferred_colors: [],
      avoided_colors: [],
      rationale:
        "There is no palette yet. A palette follows from a direction, and the direction question has not been answered.",
    };
  }
  const playbook = IDENTITY_PLAYBOOK[primary];
  if (playbook === undefined) {
    return { preferred_colors: [], avoided_colors: [], rationale: "No palette available." };
  }

  const preferred = [...playbook.coreColours];
  const avoided = [...playbook.avoidColours];
  const clauses: string[] = [playbook.paletteNote];

  const colourReading = axis(context, "colour_tolerance");
  const colourPull = axisPull(context, "colour_tolerance");
  if (colourPull >= 0.2) {
    preferred.push(...playbook.accentColours);
    clauses.push(
      isStatable(colourReading)
        ? "the comparisons showed you welcome colour, so two accents are in"
        : "the comparisons leaned slightly toward colour, so two accents are in as a starting point",
    );
  } else if (colourPull <= -0.2) {
    avoided.push(...playbook.accentColours);
    clauses.push(
      isStatable(colourReading)
        ? "the comparisons showed you keep colour restrained, so the accents stay out"
        : "the comparisons leaned away from colour, so the accents stay out for now",
    );
  }

  const contrastPull = axisPull(context, "contrast_preference");
  if (contrastPull <= -0.2) {
    clauses.push("kept within a couple of shades of each other, since you leaned tonal");
  } else if (contrastPull >= 0.2) {
    clauses.push("with one clear light-dark break per outfit, since you leaned high-contrast");
  }

  const undertone = context.body.skinUndertone;
  if (undertone !== null) {
    const lowered = undertone.toLowerCase();
    if (lowered.includes("warm") || lowered.includes("olive")) {
      clauses.push("weighted toward the warmer neutrals here, which suit a warm undertone");
    } else if (lowered.includes("cool")) {
      clauses.push("weighted toward the cooler neutrals here, which suit a cool undertone");
    }
  }
  const skinTone = context.body.skinTone?.toLowerCase() ?? "";
  if (skinTone.includes("deep")) {
    clauses.push(
      "using neutrals that still read against a deeper complexion, not only bone and light grey",
    );
  }

  return {
    preferred_colors: preferred,
    avoided_colors: avoided,
    rationale: clip(
      `${playbook.displayName} runs on ${listSentence(clauses)}.`,
      380,
    ),
  };
}

function composeSilhouette(
  context: StyleDnaContext,
  primary: string | null,
): StyleDnaDocument["silhouette"] {
  if (primary === null) {
    return {
      headline: "Not enough to call yet.",
      detail:
        "Cut advice needs either a direction or a measurement to be worth anything, and neither has been given. Answer the identity step or add a chest and waist and this fills in.",
    };
  }
  const playbook = IDENTITY_PLAYBOOK[primary];
  if (playbook === undefined) {
    return { headline: "Not enough to call yet.", detail: "No direction available." };
  }

  const detail: string[] = [];
  if (context.wardrobeGraph === "womenswear") {
    detail.push(WOMENSWEAR_SILHOUETTE_FRAMING);
  }
  detail.push(playbook.silhouetteDetail);

  // Stated fit preference (§6.6) comes before anything derived, because it is
  // the user telling us directly rather than us inferring.
  if (context.preferredFit !== null) {
    detail.push(`You said you prefer a ${context.preferredFit} fit, so that is the starting cut.`);
  }

  // The frame axes are DERIVED IN POSTGRES from the measurements
  // (derive_frame_axes(), 20260729120000_frame_profile.sql) and carry their
  // own confidence. Only a confident axis produces advice, and the advice
  // still describes what the garment does — never the wearer (spec §2,
  // docs/14-frame-fit.md §4).
  const taper = context.body.taper;
  if (taper !== null && taper.confidence >= 0.5) {
    if (taper.value === "strong") {
      detail.push(
        "A jacket with room through the chest and a taken-in waist keeps its line closed rather than pulling at the button.",
      );
    } else if (taper.value === "straight") {
      detail.push(
        "A jacket cut straight through the body hangs cleaner here than one shaped hard at the waist.",
      );
    }
  }

  const proportion = context.body.proportion;
  if (proportion !== null && proportion.confidence >= 0.5) {
    if (proportion.value === "long_leg") {
      detail.push("A slightly higher rise keeps the trouser and the top an even length apart.");
    } else if (proportion.value === "long_torso") {
      detail.push("A shorter jacket body and a mid rise stop the top half running long.");
    }
  }

  const scale = context.body.scale;
  if (scale !== null && scale.confidence >= 0.5) {
    if (scale.value === "tall") {
      detail.push(
        "Longer jacket lengths and full-length trousers are worth seeking out; most off-the-peg hems finish short.",
      );
    } else if (scale.value === "compact") {
      detail.push("Hemming a trouser to break once rather than twice keeps the leg line unbroken.");
    }
  }

  // The quiz's own silhouette axis. Where it CONTRADICTS the stated fit
  // preference, say so instead of quietly picking one — a stylist who
  // noticed both is more useful than one who averaged them.
  const silhouettePull = axisPull(context, "silhouette");
  if (Math.abs(silhouettePull) >= 0.2) {
    const leaned = silhouettePull > 0 ? "looser" : "closer to the body";
    const contradicts = context.preferredFit !== null &&
      ((silhouettePull > 0 && ["slim", "tailored"].includes(context.preferredFit)) ||
        (silhouettePull < 0 && ["relaxed", "oversized"].includes(context.preferredFit)));
    detail.push(
      contradicts
        ? `The comparisons leaned ${leaned} than the fit you named. Kyra will start from what you said and watch which one your choices back up.`
        : `The comparisons leaned ${leaned}, which matches that.`,
    );
  }

  if (!context.body.hasAnyMeasurement && context.preferredFit === null) {
    detail.push(
      "This is the direction's own proportion; a measurement or two would make it specific to you.",
    );
  }

  return {
    headline: playbook.silhouetteHeadline,
    detail: clip(detail.join(" "), 1000),
  };
}

function composeSignatures(
  context: StyleDnaContext,
  primary: string | null,
): NamedRecommendation[] {
  if (primary === null) {
    return [];
  }
  const playbook = IDENTITY_PLAYBOOK[primary];
  if (playbook === undefined) {
    return [];
  }

  const items: NamedRecommendation[] = [];
  if (context.wardrobeGraph === "womenswear") {
    for (const item of WOMENSWEAR_SIGNATURES) {
      items.push({ ...item });
    }
  }
  for (const item of playbook.signatures) {
    if (!items.some((existing) => existing.title === item.title)) {
      items.push({ ...item });
    }
  }

  // A dress code adds a piece the identity alone would not call for — the two
  // inputs answer different questions (what he wants to look like vs what the
  // room requires) and a wardrobe has to satisfy both.
  const dressCode = context.lifestyle.dressCode;
  if (dressCode !== null) {
    const extra = DRESS_CODE_SIGNATURES[dressCode];
    if (extra !== undefined && !items.some((item) => item.title === extra.title)) {
      items.push({ ...extra });
    }
  }

  return items.slice(0, 4);
}

function composePriorities(
  context: StyleDnaContext,
  primary: string | null,
): RankedRecommendation[] {
  const candidates: NamedRecommendation[] = [];

  // 1. The most concrete input there is: what the week actually looks like.
  const { dressCode, typicalWeek } = context.lifestyle;
  if (dressCode !== null && typicalWeek !== null) {
    candidates.push({
      title: "Cover the days you actually dress for",
      reason: clip(
        `You said your week is "${typicalWeek}" with a ${
          DRESS_CODE_LABELS[dressCode] ?? dressCode
        } dress code. That decides how many of each piece you need before it decides which pieces.`,
        380,
      ),
    });
  }

  // 2. The goals, in the order §6.4 lists them (the payload sorts them), so
  // the same goal set always produces the same ranking.
  for (const goal of context.goals) {
    const priority = GOAL_PRIORITIES[goal];
    if (priority !== undefined) {
      candidates.push(priority);
    }
  }

  // 3. Lifestyle constraints that change quantities rather than choices.
  const cadence = context.lifestyle.laundryCadence;
  if (cadence === "monthly" || cadence === "biweekly") {
    candidates.push({
      title: "Enough of the basics to reach laundry day",
      reason:
        "You said laundry happens every couple of weeks or less often. Quantity of the plain layers matters more here than another jacket.",
    });
  }
  if (context.lifestyle.travelFrequency !== null) {
    candidates.push({
      title: "Keep a version of this that fits one bag",
      reason: clip(
        `You said you travel ${context.lifestyle.travelFrequency.toLowerCase()}. A packable subset of the same palette saves rebuilding the wardrobe every trip.`,
        380,
      ),
    });
  }
  const occasion = context.lifestyle.commonOccasions[0];
  if (occasion !== undefined) {
    candidates.push({
      title: `A settled answer for ${clip(occasion.toLowerCase(), 60)}`,
      reason:
        "You named it as something that comes up regularly, and a recurring occasion deserves an outfit rather than a scramble.",
    });
  }

  // 4. Women's graph: dress/separates coverage before identity fallbacks.
  if (context.wardrobeGraph === "womenswear") {
    for (const priority of WOMENSWEAR_PRIORITIES) {
      candidates.push(priority);
    }
  }

  // 5. Only if the above produced too little: the identity's own priorities.
  // Last, because they are the least personal thing available — true of the
  // direction rather than of the wearer.
  if (primary !== null && candidates.length < 3) {
    const playbook = IDENTITY_PLAYBOOK[primary];
    for (const priority of playbook?.priorities ?? []) {
      candidates.push(priority);
    }
  }

  const seen = new Set<string>();
  const deduped = candidates.filter((item) => {
    if (seen.has(item.title)) {
      return false;
    }
    seen.add(item.title);
    return true;
  });

  return deduped.slice(0, 4).map((item, index) => ({ ...item, rank: index + 1 }));
}

/**
 * The four §6.10 summary scalars.
 *
 * This function is the whole reason
 * 20260730180000_style_preference_vector.sql insists these columns are the
 * generator's output rather than the quiz's: the quiz contributes ONE term
 * to each, weighted by how much that axis has actually earned, alongside the
 * identity's baseline, the dress code and the stated goals. Letting the quiz
 * write these columns directly would let three photographs overwrite all of
 * that.
 */
function composeScalars(
  context: StyleDnaContext,
  primary: string | null,
): {
  formality_preference: FormalityValue;
  logo_tolerance: number;
  trend_tolerance: number;
  accessory_preference: AccessoryPreferenceValue;
} {
  const playbook = primary === null ? undefined : IDENTITY_PLAYBOOK[primary];

  // Formality, on the five-point scale. The identity baseline and the dress
  // code carry equal weight when both are known — one is what he wants, the
  // other is what he needs, and neither outranks the other.
  let formality = playbook?.formality ?? 2;
  const dressCode = context.lifestyle.dressCode;
  if (dressCode !== null) {
    const dressCodeOrdinal = DRESS_CODE_FORMALITY[dressCode];
    if (dressCodeOrdinal !== undefined) {
      formality = (formality + dressCodeOrdinal) / 2;
    }
  }
  // A goal is a statement of intent about where he wants to move, so it is
  // worth half a step, not a whole one.
  if (context.goals.includes("improve_professional_image")) {
    formality += 0.5;
  }
  formality += axisPull(context, "formality") * 1.5;
  const formalityIndex = clamp(Math.round(formality), 0, FORMALITY_LEVELS.length - 1);

  // The two 0-100 tolerances. 45 points is the widest a fully-confident,
  // fully-consistent axis can move the identity's baseline — enough to cross
  // a ToleranceLevel band (the client's low/medium/high bridge in
  // StyleProfile.swift) but not enough for one axis to override the direction
  // the user chose.
  const logo = clamp(
    Math.round((playbook?.logoTolerance ?? 25) + axisPull(context, "logo_tolerance") * 45),
    0,
    100,
  );
  const trend = clamp(
    Math.round((playbook?.trendTolerance ?? 40) + axisPull(context, "trend_tolerance") * 45),
    0,
    100,
  );

  const accessoryBase = ACCESSORY_PREFERENCES.indexOf(playbook?.accessoryPreference ?? "moderate");
  const accessoryIndex = clamp(
    Math.round(accessoryBase + axisPull(context, "accessory_preference") * 1.2),
    0,
    ACCESSORY_PREFERENCES.length - 1,
  );

  return {
    formality_preference: FORMALITY_LEVELS[formalityIndex] ?? "balanced",
    logo_tolerance: logo,
    trend_tolerance: trend,
    accessory_preference: ACCESSORY_PREFERENCES[accessoryIndex] ?? "moderate",
  };
}

function measuredAxes(context: StyleDnaContext): string[] {
  const present = Object.entries(context.vector.dimensions)
    .filter(([, reading]) => reading.score !== null)
    .map(([name]) => name);
  const canonical = CANONICAL_AXES.filter((name) => present.includes(name));
  const extras = present.filter((name) => !CANONICAL_AXES.includes(name)).sort();
  return [...canonical, ...extras];
}

function composeKnownInputs(context: StyleDnaContext, identity: ResolvedIdentity): string[] {
  const inputs: string[] = [];
  if (!identity.inferred && identity.primary !== null) {
    inputs.push("the style identities you picked");
  }
  if (context.goals.length > 0) {
    inputs.push(
      `the ${context.goals.length === 1 ? "goal" : `${context.goals.length} goals`} you chose`,
    );
  }
  if (context.lifestyle.dressCode !== null) {
    inputs.push("your work dress code");
  }
  if (context.lifestyle.typicalWeek !== null) {
    inputs.push("the shape of your week");
  }
  if (context.lifestyle.commonOccasions.length > 0) {
    inputs.push("the occasions you named");
  }
  if (context.preferredFit !== null) {
    inputs.push("the fit you said you prefer");
  }
  if (context.body.hasAnyMeasurement) {
    inputs.push("your measurements");
  }
  if (context.body.skinTone !== null) {
    inputs.push("your skin tone");
  }
  if (context.body.skinUndertone !== null) {
    inputs.push("your skin undertone");
  }
  const answered = context.vector.comparisonsAnswered;
  if (answered > 0) {
    const offered = context.vector.comparisonsOffered;
    inputs.push(
      offered > 0 ? `${answered} of ${offered} style comparisons` : `${answered} style comparisons`,
    );
  }
  if (context.lifestyle.monthlyBudget !== null) {
    inputs.push("your clothing budget");
  }
  return inputs.slice(0, 12);
}

function composeOpenQuestions(context: StyleDnaContext, identity: ResolvedIdentity): string[] {
  const questions: string[] = [];

  if (identity.primary === null || identity.inferred) {
    questions.push(
      "Which three style identities look like you. It is the single answer that changes the most here.",
    );
  }
  if (context.lifestyle.dressCode === null) {
    questions.push(
      "What you wear to work. It decides how much of this wardrobe has to be work clothes and how much is yours.",
    );
  }
  if (context.goals.length === 0) {
    questions.push(
      "What you want out of this. The goals step is what turns a palette into a plan.",
    );
  }
  if (!context.body.hasAnyMeasurement) {
    questions.push(
      "A chest and a waist measurement. They turn general cut advice into advice about the trousers you would actually buy.",
    );
  }
  if (context.body.skinTone === null) {
    questions.push(
      "Your skin tone — how light or deep you are. Without it, neutrals quietly assume a light complexion.",
    );
  }
  if (context.body.skinUndertone === null) {
    questions.push(
      "Your skin undertone. It changes which neutrals get recommended, independent of how light or deep you are.",
    );
  }

  // Axes the comparison set could not probe at all. Phrased as something the
  // app has not done yet rather than something he failed to answer, because
  // that is the truth: five of the eight dimensions have no imagery
  // (docs/03-progress.md). An axis he was asked about and passed on is
  // deliberately NOT listed — asking again about a question he already
  // declined is worse than not asking.
  const unasked = CANONICAL_AXES.filter((name) => context.vector.dimensions[name] === undefined);
  if (unasked.length > 0) {
    const labels = unasked.map((name) => AXIS_LABELS[name] ?? name);
    questions.push(
      clip(
        `Kyra has not asked you about ${
          listSentence(labels)
        } yet. Until she has, those parts lean on the direction you chose rather than on anything you said.`,
        380,
      ),
    );
  }

  return questions.slice(0, 12);
}

function composeSummary(
  context: StyleDnaContext,
  identity: ResolvedIdentity,
  palette: StyleDnaDocument["palette"],
  priorities: readonly RankedRecommendation[],
): string {
  if (identity.primary === null) {
    return "There is not enough here yet to call a direction, and guessing one would be worse than saying so. Answer the identity step — three picks and a favourite — and this fills in immediately.";
  }
  const playbook = IDENTITY_PLAYBOOK[identity.primary];
  const name = playbook?.displayName ?? identity.primary;

  const sentences: string[] = [];
  sentences.push(
    identity.inferred
      ? `Starting from ${name}, inferred from ${identity.basis.split(" — ")[0]}.`
      : `You are ${name}.`,
  );
  if (palette.preferred_colors.length > 0) {
    sentences.push(
      `The palette to build on is ${clip(listSentence(palette.preferred_colors), 160)}.`,
    );
  }
  const first = priorities[0];
  if (first !== undefined) {
    sentences.push(`First thing to fix: ${first.title.toLowerCase()}.`);
  }
  const measured = measuredAxes(context);
  if (measured.length > 0) {
    const labels = measured.map((name) => AXIS_LABELS[name] ?? name);
    sentences.push(`The comparisons gave a read on ${listSentence(labels)}.`);
  }
  return clip(sentences.join(" "), 1000);
}

/**
 * Builds the Style DNA document from the context packet. Pure, total, and
 * deterministic: the same context always produces byte-identical output,
 * which is what lets `deterministicStylist_test.ts` assert on the prose
 * rather than only on its shape.
 */
export function composeStyleDna(context: StyleDnaContext): StyleDnaDocument {
  const identity = resolveIdentity(context);
  const secondaries = resolveSecondaries(context, identity.primary);
  const palette = composePalette(context, identity.primary);
  const silhouette = composeSilhouette(context, identity.primary);
  const signatures = composeSignatures(context, identity.primary);
  const priorities = composePriorities(context, identity.primary);
  const scalars = composeScalars(context, identity.primary);

  const basis = secondaries.inferred && secondaries.values.length > 0
    ? `${identity.basis}; the secondary influences are the directions that sit closest to it, not ones you named`
    : identity.basis;

  return {
    primary_identity: identity.primary,
    identity_basis: clip(basis, 380),
    secondary_influences: secondaries.values,
    palette,
    silhouette,
    signature_opportunities: signatures,
    wardrobe_priorities: priorities,
    summary: composeSummary(context, identity, palette, priorities),
    ...scalars,
    known_inputs: composeKnownInputs(context, identity),
    open_questions: composeOpenQuestions(context, identity),
    measured_dimensions: measuredAxes(context),
  };
}

// ---------------------------------------------------------------------------
// The provider
// ---------------------------------------------------------------------------

/**
 * The deterministic implementation of `StylistReasoningProvider`.
 *
 * It ignores `systemPrompt`, `tools`, `messages`, `maxOutputTokens`,
 * `temperature` and `tier` — it has no model to apply them to — and reads
 * only `contextPacket`. That is the correct shape for a mock behind this
 * protocol: the CALLER still constructs a complete, real request, so the day
 * a live adapter is dropped in, nothing about the call site changes. A mock
 * with a narrower signature would have hidden the fact that the caller was
 * never building a usable prompt.
 */
export class DeterministicStylistProvider implements StylistReasoningProvider {
  complete(
    request: StylistCompletionRequest,
    _ctx: ProviderRequestContext,
  ): Promise<StylistCompletionResult> {
    const document = composeStyleDna(request.contextPacket as unknown as StyleDnaContext);
    const message = JSON.stringify(document);
    return Promise.resolve({
      message,
      toolCalls: [],
      finishReason: "stop",
      usage: { inputTokens: 0, outputTokens: 0 },
      modelIdentifier: DETERMINISTIC_STYLIST_VERSION,
    });
  }

  // deno-lint-ignore require-yield
  async *completeStream(
    _request: StylistCompletionRequest,
    _ctx: ProviderRequestContext,
  ): AsyncIterable<{ delta: string; toolCallDelta?: unknown }> {
    // Throwing beats emitting the whole document as one "delta". A caller
    // that asked for a stream wants incremental output; handing it a single
    // chunk would let a latency-sensitive call site (Kyra's turns, spec §20)
    // silently behave as non-streaming while its tests passed. Style DNA
    // itself never calls this — see the protocol's own note on why.
    await Promise.resolve();
    throw new ProviderError(
      "INVALID_INPUT",
      false,
      "The deterministic stylist does not stream; it produces one complete document.",
    );
  }
}
