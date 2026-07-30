// ============================================================================
// profile/schema_test.ts
// ============================================================================
// The tests that matter most here are not the type checks — they are the two
// invariants a reviewer cannot verify by reading a type:
//
//   1. An axis absent from the preference vector stays absent, and an axis
//      present with `observations: 0` stays present. Those are different
//      facts (never asked vs asked and declined) and the whole vector design
//      exists to keep them apart — see
//      20260730180000_style_preference_vector.sql.
//   2. The four §6.10 summary columns are not accepted from this endpoint,
//      even when a client sends them.
// ============================================================================

import { assert, assertEquals, assertThrows } from "@std/assert";
import { AppError } from "../_shared/errors.ts";
import {
  ENUM_VALUES,
  parseCompleteOnboardingBody,
  parseEnvelope,
  parsePreferenceVector,
} from "./schema.ts";

// ---------------------------------------------------------------------------
// Enum sets pinned verbatim
// ---------------------------------------------------------------------------
// These lists are duplicated from 20260728100100_core_enums.sql because an
// Edge Function cannot read pg_enum. Asserting them here means an edit to
// schema.ts fails a test rather than production: a value silently dropped
// from this list becomes a 400 on a legitimate payload, and a value silently
// added becomes a 500 at the INSERT.

Deno.test("style identity values match the style_identity Postgres enum", () => {
  assertEquals([...ENUM_VALUES.styleIdentity], [
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
  ]);
});

Deno.test("fit preference values match the fit_preference Postgres enum", () => {
  assertEquals([...ENUM_VALUES.fitPreference], [
    "slim",
    "tailored",
    "regular",
    "relaxed",
    "oversized",
  ]);
});

Deno.test("dress code values match the dress_code Postgres enum", () => {
  assertEquals([...ENUM_VALUES.dressCode], [
    "ultra_casual",
    "casual",
    "smart_casual",
    "business_casual",
    "business_formal",
    "black_tie",
    "formal",
    "athletic",
  ]);
});

// ---------------------------------------------------------------------------
// The preference vector
// ---------------------------------------------------------------------------

Deno.test("an axis that was never asked about stays absent from the vector", () => {
  const vector = parsePreferenceVector({
    version: 1,
    comparisons_answered: 3,
    comparisons_offered: 3,
    dimensions: {
      formality: { score: 0.5, confidence: "low", observations: 1, agreement: 1 },
    },
  }, "vector");

  assertEquals(Object.keys(vector.dimensions), ["formality"]);
  // The seven axes the comparison set could not probe must not appear at all.
  // Adding them with a zero score would claim seven measurements that were
  // never taken.
  assertEquals(vector.dimensions["colour_tolerance"], undefined);
  assertEquals(vector.dimensions["texture"], undefined);
});

Deno.test("an axis asked about with no preference survives as observations 0, not as absent", () => {
  const vector = parsePreferenceVector({
    version: 1,
    comparisons_answered: 2,
    comparisons_offered: 3,
    dimensions: {
      texture: { score: null, confidence: "insufficient", observations: 0, agreement: null },
    },
  }, "vector");

  const texture = vector.dimensions["texture"];
  assert(texture !== undefined, "an asked-but-declined axis must not be dropped");
  assertEquals(texture.score, null);
  assertEquals(texture.observations, 0);
  assertEquals(texture.confidence, "insufficient");
  assertEquals(texture.agreement, null);
});

Deno.test("a null score is preserved rather than defaulted to zero", () => {
  const vector = parsePreferenceVector({
    dimensions: {
      silhouette: { score: null, confidence: "insufficient", observations: 0, agreement: null },
    },
  }, "vector");
  // `0` would read downstream as "measured, and neutral"; `null` reads as
  // "probed, no signal". Those produce different Style DNA.
  assertEquals(vector.dimensions["silhouette"]?.score, null);
});

Deno.test("an absent vector is the skipped-quiz value, not an error", () => {
  const vector = parsePreferenceVector(undefined, "vector");
  assertEquals(vector.comparisons_answered, 0);
  assertEquals(vector.comparisons_offered, 0);
  assertEquals(Object.keys(vector.dimensions).length, 0);
});

Deno.test("fractional observations survive — a partial-weight loading is not an integer", () => {
  const vector = parsePreferenceVector({
    dimensions: {
      contrast_preference: { score: -0.6, confidence: "low", observations: 1.5, agreement: 0.6 },
    },
  }, "vector");
  assertEquals(vector.dimensions["contrast_preference"]?.observations, 1.5);
});

Deno.test("an unrecognised axis key is preserved, so an older function accepts a newer client", () => {
  const vector = parsePreferenceVector({
    dimensions: {
      formality: { score: 0.2, confidence: "low", observations: 1, agreement: 1 },
      // A hypothetical ninth axis. Rejecting it would break the app for every
      // user on a newer build the moment one shipped.
      pattern_tolerance: { score: 0.4, confidence: "low", observations: 1, agreement: 1 },
    },
  }, "vector");
  assertEquals(Object.keys(vector.dimensions).sort(), ["formality", "pattern_tolerance"]);
});

Deno.test("a malformed reading is a 400, not a silently-dropped axis", () => {
  const error = assertThrows(
    () =>
      parsePreferenceVector({
        dimensions: { formality: { score: 5, confidence: "low", observations: 1 } },
      }, "vector"),
    AppError,
  );
  assertEquals(error.status, 400);
  assertEquals(error.category, "validation");
});

Deno.test("an unknown confidence band is rejected rather than coerced", () => {
  assertThrows(
    () =>
      parsePreferenceVector({
        dimensions: { formality: { score: 0.1, confidence: "pretty sure", observations: 1 } },
      }, "vector"),
    AppError,
  );
});

// ---------------------------------------------------------------------------
// The body
// ---------------------------------------------------------------------------

const FULL_BODY = {
  style_goals: ["dress_better_daily", "shop_more_intelligently"],
  style_profile: {
    user_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    primary_identity: "quiet_luxury",
    secondary_identities: ["minimalist", "executive"],
    style_goals: ["dress_better_daily", "shop_more_intelligently"],
    preferred_colors: [],
    avoided_colors: [],
    preferred_fit: "tailored",
    preference_vector: {
      version: 1,
      comparisons_answered: 3,
      comparisons_offered: 3,
      dimensions: {
        formality: { score: 0.8, confidence: "moderate", observations: 2, agreement: 1 },
      },
    },
    created_at: "2026-07-30T12:00:00Z",
    updated_at: "2026-07-30T12:00:00Z",
  },
  body_profile: {
    user_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    height_value_cm: 180.34000000000003,
    chest_cm: 101.6,
    fit_notes: ["broad_chest"],
    appearance: { skin_undertone: "Warm", wears_glasses: true },
    created_at: "2026-07-30T12:00:00Z",
    updated_at: "2026-07-30T12:00:00Z",
  },
  lifestyle_profile: {
    user_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    occupation_category: "technology",
    dress_code: "business_casual",
    typical_week: "Mostly in an office",
    common_occasions: ["Client dinners"],
    climate_preferences: [],
    monthly_budget: 250,
    currency: "gbp",
    preferred_brands: [],
    avoided_brands: [],
    created_at: "2026-07-30T12:00:00Z",
    updated_at: "2026-07-30T12:00:00Z",
  },
  quiz_answers: [{ pair_id: "pair-1", chosen_option_id: "a" }],
};

Deno.test("a complete payload parses into the three profile documents", () => {
  const body = parseCompleteOnboardingBody(FULL_BODY);

  assertEquals(body.styleProfile.primary_identity, "quiet_luxury");
  assertEquals(body.styleProfile.secondary_identities, ["minimalist", "executive"]);
  assertEquals(body.styleProfile.preferred_fit, "tailored");
  assertEquals(body.styleProfile.style_goals, ["dress_better_daily", "shop_more_intelligently"]);
  // Rounded to numeric(5,2), the column's own scale, rather than relying on
  // Postgres to round the full double an inch->cm conversion produces.
  assertEquals(body.bodyProfile.height_value_cm, 180.34);
  assertEquals(body.bodyProfile.fit_notes, ["broad_chest"]);
  assertEquals(body.bodyProfile.appearance["skin_undertone"], "Warm");
  assertEquals(body.lifestyleProfile.dress_code, "business_casual");
  assertEquals(body.lifestyleProfile.typical_week, "Mostly in an office");
  assertEquals(body.lifestyleProfile.currency, "GBP");
  assertEquals(body.quizAnswerCount, 1);
});

Deno.test("the four Style DNA summary fields are not read from the request at all", () => {
  const hostile = structuredClone(FULL_BODY) as Record<string, unknown>;
  const styleProfile = hostile["style_profile"] as Record<string, unknown>;
  styleProfile["formality_preference"] = "very_formal";
  styleProfile["logo_tolerance"] = 100;
  styleProfile["trend_tolerance"] = 100;
  styleProfile["accessory_preference"] = "bold";
  styleProfile["style_summary"] = "Whatever the client felt like writing.";
  styleProfile["preferred_colors"] = ["hot pink"];

  const body = parseCompleteOnboardingBody(hostile);

  // The parsed document has no home for any of them, so nothing downstream
  // can write them even by accident. `StyleProfileInput` has five fields.
  assertEquals(Object.keys(body.styleProfile).sort(), [
    "preference_vector",
    "preferred_fit",
    "primary_identity",
    "secondary_identities",
    "style_goals",
  ]);
});

Deno.test("an empty payload is valid — every onboarding step except identity is skippable", () => {
  const body = parseCompleteOnboardingBody({});
  assertEquals(body.styleProfile.primary_identity, null);
  assertEquals(body.styleProfile.style_goals, []);
  assertEquals(body.bodyProfile.height_value_cm, null);
  assertEquals(body.bodyProfile.appearance, {});
  assertEquals(body.lifestyleProfile.currency, null);
  assertEquals(body.quizAnswerCount, 0);
});

Deno.test("an unknown style identity is a 400 rather than a Postgres cast failure", () => {
  const error = assertThrows(
    () => parseCompleteOnboardingBody({ style_profile: { primary_identity: "dark_academia" } }),
    AppError,
  );
  assertEquals(error.status, 400);
});

Deno.test("an unknown dress code is a 400", () => {
  assertThrows(
    () => parseCompleteOnboardingBody({ lifestyle_profile: { dress_code: "smart_formal" } }),
    AppError,
  );
});

Deno.test("a two-letter currency is a 400, because the column checks length 3", () => {
  assertThrows(
    () => parseCompleteOnboardingBody({ lifestyle_profile: { currency: "GB" } }),
    AppError,
  );
});

Deno.test("a zero or negative measurement is a 400, because the column checks > 0", () => {
  assertThrows(
    () => parseCompleteOnboardingBody({ body_profile: { chest_cm: 0 } }),
    AppError,
  );
  assertThrows(
    () => parseCompleteOnboardingBody({ body_profile: { height_value_cm: -5 } }),
    AppError,
  );
});

Deno.test("an absurd measurement is a 400 rather than a numeric(5,2) overflow", () => {
  assertThrows(
    () => parseCompleteOnboardingBody({ body_profile: { height_value_cm: 99999 } }),
    AppError,
  );
});

Deno.test("a non-object body is rejected", () => {
  assertThrows(() => parseCompleteOnboardingBody("not an object"), AppError);
  assertThrows(() => parseCompleteOnboardingBody([1, 2, 3]), AppError);
});

Deno.test("an envelope with no body field is rejected", () => {
  assertThrows(() => parseEnvelope({ request_id: "r" }), AppError);
});

Deno.test("the envelope's request_id is read when present", () => {
  const parsed = parseEnvelope({ request_id: "abc", client_version: "ios/1.0", body: {} });
  assertEquals(parsed.requestId, "abc");
});
