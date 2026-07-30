// ============================================================================
// profile/schema.ts
// ============================================================================
// Request-schema validation for `POST /profile/complete-onboarding`
// (spec §14, ticket P2-ONBOARD-12). Shapes mirror
// `OnboardingCompletionPayload` in
// ios/AstraStyle/Domain/Repositories/ProfileRepository.swift and the three
// domain models it carries (`StyleProfile`, `BodyProfile`,
// `LifestyleProfile`), including the snake_case wire keys from their
// `CodingKeys` blocks. The outer wrapper is
// `AstraRequestEnvelope<OnboardingCompletionPayload>`:
//
//   { "request_id": string, "client_version": string, "body": { ... } }
//
// SECURITY: `style_profile.user_id` and `body_profile.user_id` ARE present on
// the wire (the Swift models carry them), and nothing in this file reads
// them. They are dropped at the parse boundary rather than checked against
// the JWT afterwards, because `complete_onboarding()` — the RPC that does the
// writing — has no user-id parameter at all and derives everything from
// auth.uid(). There is therefore no value an attacker could substitute and no
// later code path that could forget to compare. See the migration
// 20260730190000_complete_onboarding_rpc.sql.
//
// WHAT THIS FILE IS CAREFUL ABOUT, beyond the usual type checking:
//
//  1. THE PREFERENCE VECTOR'S ABSENT-VS-ZERO DISTINCTION SURVIVES.
//     `20260730180000_style_preference_vector.sql` is explicit that an axis
//     with no key was never asked about, while an axis present with
//     `observations: 0` was asked and drew no preference. The parser below
//     therefore copies the `dimensions` object key by key and never fills in
//     a missing axis, never defaults a null `score` to 0, and never drops a
//     reading because its observation count is zero. Collapsing either would
//     manufacture a measurement that was never taken — the specific
//     dishonesty the whole vector design exists to prevent.
//
//  2. THE FOUR SUMMARY COLUMNS ARE NOT ACCEPTED FROM THE CLIENT.
//     `formality_preference`, `logo_tolerance`, `trend_tolerance` and
//     `accessory_preference` are the Style DNA generator's output (§6.10),
//     not onboarding's. `StyleProfile` encodes those keys (as `null` today,
//     since `OnboardingDraft.styleProfile(...)` leaves them nil), so a naive
//     pass-through would start writing them the moment anything client-side
//     set them. They are not read here and not written by the RPC.
// ============================================================================

import { badRequest } from "../_shared/errors.ts";
import { isRecord, optionalString } from "../_shared/validation.ts";

// ---------------------------------------------------------------------------
// Enum value sets
// ---------------------------------------------------------------------------
// Duplicated from the Postgres enum types rather than imported, because there
// is nothing to import from — an Edge Function cannot read pg_enum at parse
// time without a round trip. Validating here rather than letting the cast
// inside `complete_onboarding()` fail is what turns a bad enum value into the
// 400 that P2-ONBOARD-12 requires ("rejects a malformed payload with a 4xx,
// not a 500") instead of a Postgres 22P02 surfacing as a 500.
//
// These lists must stay in step with 20260728100100_core_enums.sql and the
// Swift enums in Domain/Models/Enums.swift; `schema_test.ts` asserts each set
// verbatim so a silent edit here fails a test rather than production.

const STYLE_IDENTITIES = [
  "modern_heritage",
  "quiet_luxury",
  "smart_casual",
  "minimalist",
  "luxury_streetwear",
  "rugged_utility",
  "classic_americana",
  "european_summer",
  "executive",
  "creative",
] as const;

const FIT_PREFERENCES = ["slim", "tailored", "regular", "relaxed", "oversized"] as const;

const DRESS_CODES = [
  "ultra_casual",
  "casual",
  "smart_casual",
  "business_casual",
  "business_formal",
  "black_tie",
  "formal",
  "athletic",
] as const;

const PREFERENCE_CONFIDENCES = ["insufficient", "low", "moderate", "high"] as const;

export const ENUM_VALUES = {
  styleIdentity: STYLE_IDENTITIES,
  fitPreference: FIT_PREFERENCES,
  dressCode: DRESS_CODES,
  preferenceConfidence: PREFERENCE_CONFIDENCES,
} as const;

// Bounds. Chosen to be far above any legitimate payload and far below
// anything that could be used to make the RPC do unbounded work: §6.5 asks
// for three identities, §6.4 offers eight goals, §6.9 offers 12-20
// comparisons, §6.8's brand lists are hand-typed.
const MAX_LIST_ITEMS = 64;
const MAX_SHORT_STRING = 200;
const MAX_FREE_TEXT = 2000;
const MAX_DIMENSIONS = 32;
const MAX_APPEARANCE_KEYS = 32;

function requireOneOf<T extends string>(
  value: unknown,
  field: string,
  allowed: readonly T[],
): T | null {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value !== "string" || !(allowed as readonly string[]).includes(value)) {
    throw badRequest(`${field} must be one of: ${allowed.join(", ")}.`);
  }
  return value as T;
}

function optionalStringList(value: unknown, field: string): string[] {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw badRequest(`${field} must be an array of strings.`);
  }
  if (value.length > MAX_LIST_ITEMS) {
    throw badRequest(`${field} must contain at most ${MAX_LIST_ITEMS} items.`);
  }
  return value.map((entry, index) => {
    if (typeof entry !== "string") {
      throw badRequest(`${field}[${index}] must be a string.`);
    }
    if (entry.length > MAX_SHORT_STRING) {
      throw badRequest(`${field}[${index}] must be at most ${MAX_SHORT_STRING} characters.`);
    }
    return entry;
  });
}

/**
 * A measurement, or null.
 *
 * Rejects non-finite and non-positive values rather than clamping them: the
 * columns carry `check (x > 0)`, so a 0 or a NaN would fail at INSERT and
 * become a 500. `null` is a legitimate, meaningful answer here — spec §6.6
 * requires "I don't know" on every field and `MeasurementEntry.centimetres`
 * already returns nil for it — so an absent key is never an error.
 */
function optionalMeasurement(value: unknown, field: string, max: number): number | null {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw badRequest(`${field} must be a number.`);
  }
  if (value <= 0 || value > max) {
    throw badRequest(`${field} must be greater than 0 and at most ${max}.`);
  }
  // Rounded to the column's own scale — numeric(5,2) — so a client sending
  // the full double from an inch->cm conversion (71 in = 180.34000000000003)
  // does not depend on Postgres's rounding to fit the precision.
  return Math.round(value * 100) / 100;
}

// ---------------------------------------------------------------------------
// The preference vector
// ---------------------------------------------------------------------------

export interface DimensionReading {
  score: number | null;
  confidence: string;
  observations: number;
  agreement: number | null;
}

export interface PreferenceVector {
  version: number;
  comparisons_answered: number;
  comparisons_offered: number;
  dimensions: Record<string, DimensionReading>;
}

function parseDimensionReading(raw: unknown, field: string): DimensionReading {
  if (!isRecord(raw)) {
    throw badRequest(`${field} must be a JSON object.`);
  }

  // `score` is nullable BY DESIGN and null is not the same as absent-axis:
  // this axis was probed and every comparison touching it was answered "no
  // preference". `StyleDimensionReading.score` is `Double?` for exactly this
  // case. Defaulting it to 0 here would turn "he had no opinion" into
  // "measured, and neutral".
  let score: number | null = null;
  const rawScore = raw["score"];
  if (rawScore !== undefined && rawScore !== null) {
    if (typeof rawScore !== "number" || !Number.isFinite(rawScore)) {
      throw badRequest(`${field}.score must be a number or null.`);
    }
    if (rawScore < -1 || rawScore > 1) {
      throw badRequest(`${field}.score must be between -1 and 1.`);
    }
    score = rawScore;
  }

  const confidence = requireOneOf(
    raw["confidence"],
    `${field}.confidence`,
    PREFERENCE_CONFIDENCES,
  );
  if (confidence === null) {
    throw badRequest(`${field}.confidence is required.`);
  }

  const rawObservations = raw["observations"];
  if (typeof rawObservations !== "number" || !Number.isFinite(rawObservations)) {
    throw badRequest(`${field}.observations must be a number.`);
  }
  if (rawObservations < 0) {
    throw badRequest(`${field}.observations must not be negative.`);
  }

  let agreement: number | null = null;
  const rawAgreement = raw["agreement"];
  if (rawAgreement !== undefined && rawAgreement !== null) {
    if (typeof rawAgreement !== "number" || !Number.isFinite(rawAgreement)) {
      throw badRequest(`${field}.agreement must be a number or null.`);
    }
    if (rawAgreement < 0 || rawAgreement > 1) {
      throw badRequest(`${field}.agreement must be between 0 and 1.`);
    }
    agreement = rawAgreement;
  }

  return { score, confidence, observations: rawObservations, agreement };
}

/**
 * Parses `style_profile.preference_vector` into the document stored verbatim
 * in `style_profiles.preference_vector`.
 *
 * An absent or `{}` vector is a real, valid value — the §6.9 step is
 * skippable — and produces a vector with zero counts and no dimensions,
 * matching `StylePreferenceVector.skipped`.
 *
 * UNRECOGNISED AXIS KEYS ARE PRESERVED, not rejected. `StyleDimension` has
 * eight cases today, and `StylePreferenceVector.init(from:)` on the client
 * deliberately skips an axis it does not know rather than failing to decode
 * the user's own profile. The server has the same obligation in the other
 * direction: an older deployed function must not reject a payload from a
 * newer client that probes a ninth axis. The reading's SHAPE is still
 * validated, so an unknown key cannot smuggle arbitrary JSON into the column.
 */
export function parsePreferenceVector(raw: unknown, field: string): PreferenceVector {
  if (raw === undefined || raw === null) {
    return { version: 1, comparisons_answered: 0, comparisons_offered: 0, dimensions: {} };
  }
  if (!isRecord(raw)) {
    throw badRequest(`${field} must be a JSON object.`);
  }

  const readCount = (key: string): number => {
    const value = raw[key];
    if (value === undefined || value === null) {
      return 0;
    }
    if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
      throw badRequest(`${field}.${key} must be a non-negative integer.`);
    }
    return value;
  };

  const rawVersion = raw["version"];
  let version = 1;
  if (rawVersion !== undefined && rawVersion !== null) {
    if (typeof rawVersion !== "number" || !Number.isInteger(rawVersion) || rawVersion < 1) {
      throw badRequest(`${field}.version must be a positive integer.`);
    }
    version = rawVersion;
  }

  const dimensions: Record<string, DimensionReading> = {};
  const rawDimensions = raw["dimensions"];
  if (rawDimensions !== undefined && rawDimensions !== null) {
    if (!isRecord(rawDimensions)) {
      throw badRequest(`${field}.dimensions must be a JSON object.`);
    }
    const keys = Object.keys(rawDimensions);
    if (keys.length > MAX_DIMENSIONS) {
      throw badRequest(`${field}.dimensions must contain at most ${MAX_DIMENSIONS} axes.`);
    }
    for (const key of keys) {
      if (key.length === 0 || key.length > MAX_SHORT_STRING) {
        throw badRequest(`${field}.dimensions has an unusable axis key.`);
      }
      dimensions[key] = parseDimensionReading(rawDimensions[key], `${field}.dimensions.${key}`);
    }
  }

  return {
    version,
    comparisons_answered: readCount("comparisons_answered"),
    comparisons_offered: readCount("comparisons_offered"),
    dimensions,
  };
}

// ---------------------------------------------------------------------------
// The three profile documents, in the exact shape the RPC reads them
// ---------------------------------------------------------------------------

export interface StyleProfileInput {
  primary_identity: string | null;
  secondary_identities: string[];
  style_goals: string[];
  preferred_fit: string | null;
  preference_vector: PreferenceVector;
}

export interface BodyProfileInput {
  height_value_cm: number | null;
  weight_value_kg: number | null;
  chest_cm: number | null;
  waist_cm: number | null;
  inseam_cm: number | null;
  neck_cm: number | null;
  shoe_size: string | null;
  shirt_size: string | null;
  trouser_size: string | null;
  fit_notes: string[];
  appearance: Record<string, unknown>;
}

export interface LifestyleProfileInput {
  occupation_category: string | null;
  dress_code: string | null;
  common_occasions: string[];
  typical_week: string | null;
  climate_preferences: string[];
  monthly_budget: number | null;
  currency: string | null;
  preferred_brands: string[];
  avoided_brands: string[];
  laundry_cadence: string | null;
  travel_frequency: string | null;
  religious_service_attire_needs: string | null;
  sustainability_preference: string | null;
}

export interface CompleteOnboardingBody {
  styleProfile: StyleProfileInput;
  bodyProfile: BodyProfileInput;
  lifestyleProfile: LifestyleProfileInput;
  /** Kept for logging counts only — see handler.ts. Never logged as content. */
  quizAnswerCount: number;
}

// Upper bounds on a human measurement, in the column's unit. Generous enough
// that no real person is rejected and tight enough that a fat-fingered or
// hostile value fails here with a 400 rather than at the numeric(5,2) column
// with a 500.
const MAX_HEIGHT_CM = 300;
const MAX_WEIGHT_KG = 500;
const MAX_GIRTH_CM = 400;

function parseStyleProfile(raw: unknown): StyleProfileInput {
  const record = isRecord(raw) ? raw : {};
  if (raw !== undefined && raw !== null && !isRecord(raw)) {
    throw badRequest("body.style_profile must be a JSON object.");
  }

  const secondary = optionalStringList(
    record["secondary_identities"],
    "body.style_profile.secondary_identities",
  );
  for (const [index, identity] of secondary.entries()) {
    requireOneOf(
      identity,
      `body.style_profile.secondary_identities[${index}]`,
      STYLE_IDENTITIES,
    );
  }

  return {
    primary_identity: requireOneOf(
      record["primary_identity"],
      "body.style_profile.primary_identity",
      STYLE_IDENTITIES,
    ),
    secondary_identities: secondary,
    // §6.4's goals arrive twice — once at the payload's top level and once
    // inside style_profile, because `OnboardingCompletionPayload` carries
    // both. They are built from the same `draft.goals` set, so this reads
    // whichever is present and the handler prefers the top-level one.
    style_goals: optionalStringList(record["style_goals"], "body.style_profile.style_goals"),
    preferred_fit: requireOneOf(
      record["preferred_fit"],
      "body.style_profile.preferred_fit",
      FIT_PREFERENCES,
    ),
    preference_vector: parsePreferenceVector(
      record["preference_vector"],
      "body.style_profile.preference_vector",
    ),
  };
}

function parseBodyProfile(raw: unknown): BodyProfileInput {
  if (raw !== undefined && raw !== null && !isRecord(raw)) {
    throw badRequest("body.body_profile must be a JSON object.");
  }
  const record = isRecord(raw) ? raw : {};

  // Passed through as an opaque document, matching the column's own design
  // (`appearance jsonb`, "every field is optional, free-form and
  // user-omittable"). The keys are NOT enumerated here on purpose: doing so
  // would put a third copy of AppearanceProfile's key list in the codebase
  // (Swift, the migration comment, and here) with no mechanism keeping them
  // in step. What IS enforced is that it is a bounded, flat-ish object of
  // JSON values, so it cannot be used to store an arbitrary payload.
  const rawAppearance = record["appearance"];
  let appearance: Record<string, unknown> = {};
  if (rawAppearance !== undefined && rawAppearance !== null) {
    if (!isRecord(rawAppearance)) {
      throw badRequest("body.body_profile.appearance must be a JSON object.");
    }
    const keys = Object.keys(rawAppearance);
    if (keys.length > MAX_APPEARANCE_KEYS) {
      throw badRequest(
        `body.body_profile.appearance must contain at most ${MAX_APPEARANCE_KEYS} keys.`,
      );
    }
    const serialized = JSON.stringify(rawAppearance);
    if (serialized.length > MAX_FREE_TEXT * 4) {
      throw badRequest("body.body_profile.appearance is too large.");
    }
    appearance = rawAppearance;
  }

  return {
    height_value_cm: optionalMeasurement(
      record["height_value_cm"],
      "body.body_profile.height_value_cm",
      MAX_HEIGHT_CM,
    ),
    weight_value_kg: optionalMeasurement(
      record["weight_value_kg"],
      "body.body_profile.weight_value_kg",
      MAX_WEIGHT_KG,
    ),
    chest_cm: optionalMeasurement(record["chest_cm"], "body.body_profile.chest_cm", MAX_GIRTH_CM),
    waist_cm: optionalMeasurement(record["waist_cm"], "body.body_profile.waist_cm", MAX_GIRTH_CM),
    inseam_cm: optionalMeasurement(
      record["inseam_cm"],
      "body.body_profile.inseam_cm",
      MAX_GIRTH_CM,
    ),
    neck_cm: optionalMeasurement(record["neck_cm"], "body.body_profile.neck_cm", MAX_GIRTH_CM),
    shoe_size:
      optionalString(record["shoe_size"], "body.body_profile.shoe_size", MAX_SHORT_STRING) ??
        null,
    shirt_size:
      optionalString(record["shirt_size"], "body.body_profile.shirt_size", MAX_SHORT_STRING) ??
        null,
    trouser_size:
      optionalString(record["trouser_size"], "body.body_profile.trouser_size", MAX_SHORT_STRING) ??
        null,
    fit_notes: optionalStringList(record["fit_notes"], "body.body_profile.fit_notes"),
    appearance,
  };
}

function parseLifestyleProfile(raw: unknown): LifestyleProfileInput {
  if (raw !== undefined && raw !== null && !isRecord(raw)) {
    throw badRequest("body.lifestyle_profile must be a JSON object.");
  }
  const record = isRecord(raw) ? raw : {};

  let monthlyBudget: number | null = null;
  const rawBudget = record["monthly_budget"];
  if (rawBudget !== undefined && rawBudget !== null) {
    // Swift encodes `Decimal` as a JSON number, so a string here is a bug in
    // the caller, not a format this endpoint should be lenient about — being
    // lenient would mean guessing a decimal separator.
    if (typeof rawBudget !== "number" || !Number.isFinite(rawBudget)) {
      throw badRequest("body.lifestyle_profile.monthly_budget must be a number.");
    }
    if (rawBudget < 0 || rawBudget > 100_000_000) {
      throw badRequest("body.lifestyle_profile.monthly_budget must be between 0 and 100000000.");
    }
    monthlyBudget = Math.round(rawBudget * 100) / 100;
  }

  let currency: string | null = null;
  const rawCurrency = record["currency"];
  if (rawCurrency !== undefined && rawCurrency !== null && rawCurrency !== "") {
    // `char_length(currency) = 3` is a column constraint, so a 2- or
    // 4-character code has to fail here or it fails as a 500 at INSERT.
    if (typeof rawCurrency !== "string" || !/^[A-Za-z]{3}$/.test(rawCurrency)) {
      throw badRequest(
        "body.lifestyle_profile.currency must be a three-letter ISO 4217 code.",
      );
    }
    currency = rawCurrency.toUpperCase();
  }

  return {
    occupation_category: optionalString(
      record["occupation_category"],
      "body.lifestyle_profile.occupation_category",
      MAX_SHORT_STRING,
    ) ?? null,
    dress_code: requireOneOf(
      record["dress_code"],
      "body.lifestyle_profile.dress_code",
      DRESS_CODES,
    ),
    common_occasions: optionalStringList(
      record["common_occasions"],
      "body.lifestyle_profile.common_occasions",
    ),
    typical_week: optionalString(
      record["typical_week"],
      "body.lifestyle_profile.typical_week",
      MAX_SHORT_STRING,
    ) ?? null,
    climate_preferences: optionalStringList(
      record["climate_preferences"],
      "body.lifestyle_profile.climate_preferences",
    ),
    monthly_budget: monthlyBudget,
    currency,
    preferred_brands: optionalStringList(
      record["preferred_brands"],
      "body.lifestyle_profile.preferred_brands",
    ),
    avoided_brands: optionalStringList(
      record["avoided_brands"],
      "body.lifestyle_profile.avoided_brands",
    ),
    laundry_cadence: optionalString(
      record["laundry_cadence"],
      "body.lifestyle_profile.laundry_cadence",
      MAX_SHORT_STRING,
    ) ?? null,
    travel_frequency: optionalString(
      record["travel_frequency"],
      "body.lifestyle_profile.travel_frequency",
      MAX_SHORT_STRING,
    ) ?? null,
    religious_service_attire_needs: optionalString(
      record["religious_service_attire_needs"],
      "body.lifestyle_profile.religious_service_attire_needs",
      MAX_FREE_TEXT,
    ) ?? null,
    sustainability_preference: optionalString(
      record["sustainability_preference"],
      "body.lifestyle_profile.sustainability_preference",
      MAX_FREE_TEXT,
    ) ?? null,
  };
}

/** Parses and validates the `body` object of the request envelope. */
export function parseCompleteOnboardingBody(rawBody: unknown): CompleteOnboardingBody {
  if (!isRecord(rawBody)) {
    throw badRequest('Request envelope must contain a JSON object at "body".');
  }

  const styleProfile = parseStyleProfile(rawBody["style_profile"]);

  // The top-level `style_goals` wins when present. Both come from the same
  // `draft.goals`, but the top-level one is the payload's own declared field
  // and the nested copy is incidental to reusing the StyleProfile model.
  const topLevelGoals = rawBody["style_goals"];
  if (topLevelGoals !== undefined && topLevelGoals !== null) {
    styleProfile.style_goals = optionalStringList(topLevelGoals, "body.style_goals");
  }

  const rawQuizAnswers = rawBody["quiz_answers"];
  let quizAnswerCount = 0;
  if (rawQuizAnswers !== undefined && rawQuizAnswers !== null) {
    if (!Array.isArray(rawQuizAnswers)) {
      throw badRequest("body.quiz_answers must be an array.");
    }
    if (rawQuizAnswers.length > MAX_LIST_ITEMS) {
      throw badRequest(`body.quiz_answers must contain at most ${MAX_LIST_ITEMS} items.`);
    }
    for (const [index, answer] of rawQuizAnswers.entries()) {
      if (!isRecord(answer)) {
        throw badRequest(`body.quiz_answers[${index}] must be a JSON object.`);
      }
      if (typeof answer["pair_id"] !== "string" || typeof answer["chosen_option_id"] !== "string") {
        throw badRequest(
          `body.quiz_answers[${index}] must carry string pair_id and chosen_option_id.`,
        );
      }
    }
    quizAnswerCount = rawQuizAnswers.length;
  }

  return {
    styleProfile,
    bodyProfile: parseBodyProfile(rawBody["body_profile"]),
    lifestyleProfile: parseLifestyleProfile(rawBody["lifestyle_profile"]),
    quizAnswerCount,
  };
}

/** Parses the outer `AstraRequestEnvelope` and returns its (still-raw) `body`. */
export function parseEnvelope(raw: unknown): { requestId?: string; body: unknown } {
  if (!isRecord(raw)) {
    throw badRequest("Request body must be a JSON object.");
  }
  if (!("body" in raw)) {
    throw badRequest('Request envelope is missing the required "body" field.');
  }
  const requestId = typeof raw["request_id"] === "string" ? raw["request_id"] : undefined;
  return { requestId, body: raw["body"] };
}

// ---------------------------------------------------------------------------
// Response
// ---------------------------------------------------------------------------

/**
 * The `profiles` row, in the shape `Profile` (Domain/Models/Profile.swift)
 * decodes. Every non-Optional Swift property must be present or the client's
 * decode throws — `id`, `units`, `theme`, `subscription_tier`, `created_at`
 * and `updated_at` in particular. Timestamps are ISO-8601 because
 * `AstraAPIClient` sets `dateDecodingStrategy = .iso8601`.
 */
export interface ProfileDTO {
  id: string;
  display_name: string | null;
  avatar_url: string | null;
  location_name: string | null;
  timezone: string | null;
  units: string;
  theme: string;
  onboarding_completed_at: string | null;
  subscription_tier: string;
  created_at: string;
  updated_at: string;
}
