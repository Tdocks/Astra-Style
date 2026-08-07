import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import {
  availabilitySubscore,
  coWearKey,
  coWearSubscore,
  idealTemperatureC,
  NO_OCCASION_PRIOR,
  NO_PREFERENCE_PRIOR,
  NO_WEATHER_PRIOR,
  occasionSubscore,
  seasonWeatherSubscore,
  userPreferenceSubscore,
} from "./context.ts";
import type { LaundryState, ScorableItem, ScoringContext } from "../types.ts";

function garment(
  id: string,
  role: ScorableItem["role"],
  over: Partial<ScorableItem> = {},
): ScorableItem {
  return {
    id,
    category: role === "accessory" ? "accessory" : role,
    role,
    primaryColor: null,
    isNeutral: false,
    secondaryColors: [],
    pattern: null,
    patternScale: null,
    materials: [],
    formalityScore: null,
    fit: null,
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
    ...over,
  };
}

// ── §2.5 weather ────────────────────────────────────────────────────────────

Deno.test("The warmth mapping runs on the column's 0–100 scale, not the doc's 0–10", () => {
  // The bug this rescale exists to prevent: read on the doc's scale, an
  // overcoat at 85 maps to −267°C and no winter garment ever suits any day.
  assertAlmostEquals(idealTemperatureC(0), 30, 1e-9);
  assertAlmostEquals(idealTemperatureC(100), -5, 1e-9);
  assertAlmostEquals(idealTemperatureC(50), 12.5, 1e-9);
  const overcoat = idealTemperatureC(85);
  assert(overcoat > -10 && overcoat < 5, `an overcoat should suit cold, not ${overcoat}°C`);
});

Deno.test("A heavy coat suits a cold day and a linen shirt suits a hot one", () => {
  const cold: ScoringContext = { weather: { temperatureC: 2, precipitationProbability: 0 } };
  const hot: ScoringContext = { weather: { temperatureC: 29, precipitationProbability: 0 } };
  const coat = [garment("coat", "outerwear", { warmthScore: 90 })];
  const linen = [garment("linen", "top", { warmthScore: 5 })];

  assert(seasonWeatherSubscore(coat, cold).value > 0.8);
  assert(seasonWeatherSubscore(coat, hot).value < 0.2);
  assert(seasonWeatherSubscore(linen, hot).value > 0.8);
  assert(seasonWeatherSubscore(linen, cold).value < 0.2);
});

Deno.test("Rain penalises exposed garments only, not the shirt under the coat", () => {
  const wet: ScoringContext = { weather: { temperatureC: 12, precipitationProbability: 0.9 } };
  const dry: ScoringContext = { weather: { temperatureC: 12, precipitationProbability: 0.05 } };

  const suede = [garment("suede", "shoes", { warmthScore: 50, waterResistanceScore: 5 })];
  const shirt = [garment("shirt", "top", { warmthScore: 50, waterResistanceScore: 5 })];

  assert(seasonWeatherSubscore(suede, wet).value < seasonWeatherSubscore(suede, dry).value);
  assertAlmostEquals(
    seasonWeatherSubscore(shirt, wet).value,
    seasonWeatherSubscore(shirt, dry).value,
    1e-9,
  );
});

Deno.test("A waterproof shoe is not penalised by rain", () => {
  const wet: ScoringContext = { weather: { temperatureC: 12, precipitationProbability: 0.9 } };
  const boot = [garment("boot", "shoes", { warmthScore: 50, waterResistanceScore: 80 })];
  assert(seasonWeatherSubscore(boot, wet).value > 0.9);
});

Deno.test("No forecast is a mild prior, not a penalty, and it is reported", () => {
  const score = seasonWeatherSubscore([garment("x", "top", { warmthScore: 50 })], {});
  assertEquals(score.value, NO_WEATHER_PRIOR);
  assert(score.degraded[0]!.includes("weather"));
});

// ── §2.6 preference ─────────────────────────────────────────────────────────

Deno.test("Cold start is 0.7 — neither distrust nor a promise", () => {
  const score = userPreferenceSubscore([garment("x", "top")], {});
  assertEquals(score.value, NO_PREFERENCE_PRIOR);
  assert(score.degraded.length > 0);
});

Deno.test("An avoided colour overrides everything else about the garment", () => {
  // A man who said "never orange" must not be talked into orange by a good
  // silhouette score.
  const context: ScoringContext = {
    preferences: {
      preferredColors: [],
      avoidedColors: ["orange"],
      preferredFit: "slim",
      formalityPreferenceCenter: 50,
    },
  };
  const orange = garment("o", "top", { fit: "slim", formalityScore: 50 });
  const navy = garment("n", "top", { fit: "slim", formalityScore: 50 });
  const nameOf = (i: ScorableItem) => (i.id === "o" ? "Orange" : "navy");

  const avoided = userPreferenceSubscore([orange], context, nameOf).value;
  const fine = userPreferenceSubscore([navy], context, nameOf).value;
  assert(avoided < 0.2, `an avoided colour should be near-zero, got ${avoided}`);
  assert(fine > 0.9, `a preferred garment should score high, got ${fine}`);
});

Deno.test("Preferred fit and formality proximity both lift the score", () => {
  const context: ScoringContext = {
    preferences: {
      preferredColors: [],
      avoidedColors: [],
      preferredFit: "slim",
      formalityPreferenceCenter: 60,
    },
  };
  const onPoint = userPreferenceSubscore(
    [garment("a", "top", { fit: "slim", formalityScore: 60 })],
    context,
  ).value;
  const wrongFit = userPreferenceSubscore(
    [garment("a", "top", { fit: "oversized", formalityScore: 60 })],
    context,
  ).value;
  const farFormality = userPreferenceSubscore(
    [garment("a", "top", { fit: "slim", formalityScore: 5 })],
    context,
  ).value;
  assert(onPoint > wrongFit);
  assert(onPoint > farFormality);
});

Deno.test("Preference always reports the missing feedback history", () => {
  // The implicit half of §2.6 has no data source yet. The doc's own rule is to
  // redistribute to the explicit term — which is what happens — but the outfit
  // card must not claim personalisation from it.
  const context: ScoringContext = {
    preferences: {
      preferredColors: [],
      avoidedColors: [],
      preferredFit: "slim",
      formalityPreferenceCenter: 50,
    },
  };
  const score = userPreferenceSubscore([garment("a", "top", { fit: "slim" })], context);
  assert(score.degraded.some((d) => d.includes("feedback")));
});

// ── §2.7 co-wear ────────────────────────────────────────────────────────────

Deno.test("An untested pair opens at 2/3, not 1/2", () => {
  // Absence of negative history is not evidence of a bad pairing. A raw
  // positive rate would structurally bury every new garment.
  const score = coWearSubscore([garment("a", "top"), garment("b", "bottom")], {});
  assertAlmostEquals(score.value, 2 / 3, 1e-9);
});

Deno.test("A well-worn happy pair beats an untested one, which beats a disliked one", () => {
  const liked = new Map([[coWearKey("a", "b"), { totalCoWears: 10, positiveCoWears: 10 }]]);
  const disliked = new Map([[coWearKey("a", "b"), { totalCoWears: 10, positiveCoWears: 0 }]]);
  const items = [garment("a", "top"), garment("b", "bottom")];

  const good = coWearSubscore(items, { coWear: liked }).value;
  const untested = coWearSubscore(items, {}).value;
  const bad = coWearSubscore(items, { coWear: disliked }).value;

  assert(good > untested, `${good} should beat the untested ${untested}`);
  assert(untested > bad, `${untested} should beat the disliked ${bad}`);
});

Deno.test("A brand-new garment inherits the user's general taste for that role pair", () => {
  // The fallback that stops a garment bought yesterday being treated as
  // suspect. It also marks itself degraded — the score is about tops and
  // bottoms in general, not about these two.
  const byRole = new Map([["bottom|top", { totalCoWears: 20, positiveCoWears: 18 }]]);
  const score = coWearSubscore([garment("new", "top"), garment("b", "bottom")], {
    coWearByRole: byRole,
  });
  assert(score.value > 0.8, `role fallback should carry the signal, got ${score.value}`);
  assert(score.degraded.some((d) => d.includes("specific")));
});

Deno.test("A measured specific pair is not marked degraded", () => {
  const exact = new Map([[coWearKey("a", "b"), { totalCoWears: 6, positiveCoWears: 5 }]]);
  const score = coWearSubscore([garment("a", "top"), garment("b", "bottom")], { coWear: exact });
  assertEquals(score.degraded, []);
});

Deno.test("coWearKey is order-free", () => {
  assertEquals(coWearKey("a", "b"), coWearKey("b", "a"));
});

// ── §2.8 occasion ───────────────────────────────────────────────────────────

Deno.test("No occasion asked about is not a reason to mark anything down", () => {
  // "What should I wear today" is the overwhelmingly common request.
  const score = occasionSubscore({});
  assertEquals(score.value, NO_OCCASION_PRIOR);
  assertEquals(score.degraded, []);
});

Deno.test("An exact tag match scores 1; an adjacent one lands in between; unrelated bottoms out", () => {
  const target = { targetOccasion: "business-casual" };
  assertEquals(occasionSubscore(target, ["business-casual"]).value, 1);
  const adjacent = occasionSubscore(target, ["business-formal"]).value;
  const unrelated = occasionSubscore(target, ["athletic"]).value;
  assert(adjacent > unrelated && adjacent < 1, `adjacent ${adjacent} should sit between`);
  assertAlmostEquals(unrelated, 0.2, 1e-9);
});

Deno.test("A named occasion with no tags to match reports the missing column", () => {
  const score = occasionSubscore({ targetOccasion: "date-night" }, []);
  assertEquals(score.value, NO_OCCASION_PRIOR);
  assert(score.degraded[0]!.includes("occasion tags"));
});

// ── §2.9 availability ───────────────────────────────────────────────────────

Deno.test("Clean beats worn-once, nudging a man through his wardrobe", () => {
  const clean = availabilitySubscore([garment("a", "top", { laundryState: "clean" })]).value;
  const worn = availabilitySubscore([garment("a", "top", { laundryState: "worn_once" })]).value;
  assertEquals(clean, 1);
  assertEquals(worn, 0.75);
});

Deno.test("Availability is a mean across the outfit", () => {
  const states: LaundryState[] = ["clean", "worn_once"];
  const value = availabilitySubscore(
    states.map((s, i) => garment(`g${i}`, "top", { laundryState: s })),
  ).value;
  assertAlmostEquals(value, 0.875, 1e-9);
});
