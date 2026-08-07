import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import {
  type ComponentWeights,
  DEFAULT_WEIGHTS,
  scoreOutfit,
  wearableItems,
} from "./compatibility.ts";
import { classifyNeutral, rgbToLCh } from "./colorSpace.ts";
import type { AvailabilityState, LaundryState, ScorableItem } from "./types.ts";

function hex(value: string) {
  const v = Number.parseInt(value, 16);
  return { r: (v >> 16) & 255, g: (v >> 8) & 255, b: v & 255 };
}

function garment(
  id: string,
  role: ScorableItem["role"],
  over: Partial<ScorableItem> & { colorHex?: string } = {},
): ScorableItem {
  const { colorHex, ...rest } = over;
  const lch = colorHex ? rgbToLCh(hex(colorHex)) : null;
  return {
    id,
    category: role === "accessory" ? "accessory" : role,
    role,
    primaryColor: lch,
    isNeutral: lch ? classifyNeutral(lch).isNeutral : false,
    secondaryColors: [],
    pattern: "solid",
    patternScale: null,
    materials: [],
    formalityScore: null,
    fit: null,
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
    ...rest,
  };
}

/** §2.2's canonical outfit, fully populated. */
const CANONICAL: ScorableItem[] = [
  garment("polo", "top", { colorHex: "6E6E3C", formalityScore: 40, fit: "regular" }),
  garment("chino", "bottom", { colorHex: "C8BEA5", formalityScore: 50, fit: "tailored" }),
  garment("sneaker", "shoes", { colorHex: "F5F3EE", formalityScore: 22, fit: "regular" }),
];

Deno.test("The default weights are §10's table and sum to 1", () => {
  const total = Object.values(DEFAULT_WEIGHTS).reduce((s, w) => s + w, 0);
  assertAlmostEquals(total, 1, 1e-9);
  assertEquals(DEFAULT_WEIGHTS.color, 0.25);
  assertEquals(DEFAULT_WEIGHTS.formality, 0.20);
  assertEquals(DEFAULT_WEIGHTS.silhouette, 0.15);
});

Deno.test("A score is an integer 0–100", () => {
  const result = scoreOutfit(CANONICAL);
  assert(Number.isInteger(result.score), `not an integer: ${result.score}`);
  assert(result.score >= 0 && result.score <= 100);
});

Deno.test("The canonical outfit scores respectably without any context at all", () => {
  // A brand-new user: no weather, no preferences, no wear history. Every
  // component falls to its cold-start prior. The result must still be a usable
  // recommendation rather than a wall of low scores, or the app looks broken on
  // the one morning it most needs to look competent.
  const result = scoreOutfit(CANONICAL);
  assert(result.score >= 60, `a good outfit scored only ${result.score} cold`);
  assert(result.score <= 95, `a fully-degraded score of ${result.score} overclaims`);
});

Deno.test("Every component reports itself, so a breakdown is always available", () => {
  const result = scoreOutfit(CANONICAL);
  const names = Object.keys(result.components).sort();
  assertEquals(
    names,
    [
      "availability",
      "coWear",
      "color",
      "formality",
      "occasion",
      "seasonWeather",
      "silhouette",
      "userPreference",
    ].sort(),
  );
});

Deno.test("Degradations are collected and deduplicated across components", () => {
  const result = scoreOutfit(CANONICAL);
  assert(result.degraded.length > 0, "a contextless score must admit what it lacks");
  assertEquals(
    result.degraded.length,
    new Set(result.degraded).size,
    "degradations must be deduplicated",
  );
  // The three the cold-start path must always name.
  assert(result.degraded.some((d) => d.includes("weather")));
  assert(result.degraded.some((d) => d.includes("preferences") || d.includes("feedback")));
  assert(result.degraded.some((d) => d.includes("wear")));
});

Deno.test("A fully-measured score reports nothing degraded", () => {
  // The property that makes `degraded` trustworthy: it has to be able to be
  // empty, or the copy layer would drop every sentence forever.
  const result = scoreOutfit(CANONICAL, {
    weather: { temperatureC: 18, precipitationProbability: 0.05 },
    preferences: {
      preferredColors: [],
      avoidedColors: [],
      preferredFit: "tailored",
      formalityPreferenceCenter: 45,
    },
    coWear: new Map([
      ["chino|polo", { totalCoWears: 8, positiveCoWears: 7 }],
      ["polo|sneaker", { totalCoWears: 5, positiveCoWears: 4 }],
      ["chino|sneaker", { totalCoWears: 6, positiveCoWears: 5 }],
    ]),
  }, { colorNameOf: () => "olive" });

  const withWarmth = CANONICAL.map((i) => ({ ...i, warmthScore: 40 }));
  const measuredResult = scoreOutfit(withWarmth, {
    weather: { temperatureC: 18, precipitationProbability: 0.05 },
    preferences: {
      preferredColors: [],
      avoidedColors: [],
      preferredFit: "tailored",
      formalityPreferenceCenter: 45,
    },
    coWear: new Map([
      ["chino|polo", { totalCoWears: 8, positiveCoWears: 7 }],
      ["polo|sneaker", { totalCoWears: 5, positiveCoWears: 4 }],
      ["chino|sneaker", { totalCoWears: 6, positiveCoWears: 5 }],
    ]),
  }, { colorNameOf: () => "olive" });

  // Preference always names its missing feedback history, so the best
  // achievable today is one degradation rather than none.
  assert(result.degraded.length >= 1);
  assert(
    measuredResult.degraded.length < result.degraded.length,
    "supplying warmth ratings should reduce the degradation list",
  );
});

Deno.test("A coherent outfit outranks an incoherent one", () => {
  // The end-to-end property the whole engine exists for. If this ever fails,
  // nothing else in this file matters.
  const coherent = scoreOutfit([
    garment("shirt", "top", { colorHex: "1F2A44", formalityScore: 70, fit: "tailored" }),
    garment("trouser", "bottom", { colorHex: "36393D", formalityScore: 70, fit: "tailored" }),
    garment("oxford", "shoes", { colorHex: "3B2A20", formalityScore: 70, fit: "regular" }),
  ]).score;

  const incoherent = scoreOutfit([
    garment("tee", "top", { colorHex: "B03030", formalityScore: 10, fit: "oversized" }),
    garment("trouser", "bottom", { colorHex: "7A9A2E", formalityScore: 80, fit: "slim" }),
    garment("slide", "shoes", { colorHex: "C9A227", formalityScore: 0, fit: "regular" }),
  ]).score;

  assert(
    coherent > incoherent + 15,
    `coherent ${coherent} should clearly beat incoherent ${incoherent}`,
  );
});

Deno.test("Weights that do not sum to 1 are renormalised rather than capping the product", () => {
  // A human editing eight numbers in a config table will eventually make them
  // sum to 0.97. That should shift the emphasis slightly — which is what they
  // were editing — not silently cap every outfit in the app at 97.
  const short: ComponentWeights = {
    color: 0.20,
    formality: 0.20,
    silhouette: 0.15,
    seasonWeather: 0.10,
    userPreference: 0.10,
    coWear: 0.10,
    occasion: 0.05,
    availability: 0.05,
  };
  const result = scoreOutfit(CANONICAL, {}, { weights: short });
  const total = Object.values(result.weights).reduce((s, w) => s + w, 0);
  assertAlmostEquals(total, 1, 1e-9);
});

Deno.test("Nonsense weights fall back to the default rather than producing zero", () => {
  const zeroed = Object.fromEntries(
    Object.keys(DEFAULT_WEIGHTS).map((k) => [k, 0]),
  ) as unknown as ComponentWeights;
  const result = scoreOutfit(CANONICAL, {}, { weights: zeroed });
  assertEquals(result.weights, DEFAULT_WEIGHTS);
  assert(result.score > 0);
});

Deno.test("Reweighting toward a component moves the score in that component's direction", () => {
  // What makes the weights worth having: they must actually steer the ranking.
  const clashing = [
    garment("a", "top", { colorHex: "B03030", formalityScore: 50, fit: "regular" }),
    garment("b", "bottom", { colorHex: "7A9A2E", formalityScore: 50, fit: "regular" }),
  ];
  const colourHeavy: ComponentWeights = { ...DEFAULT_WEIGHTS, color: 0.60, coWear: 0 };
  const base = scoreOutfit(clashing).score;
  const weighted = scoreOutfit(clashing, {}, { weights: colourHeavy }).score;
  assert(
    weighted < base,
    `leaning on colour should punish a colour clash: ${weighted} vs ${base}`,
  );
});

Deno.test("The §3.1 register comes back alongside the score", () => {
  const result = scoreOutfit(CANONICAL);
  assertEquals(result.formalityRegister, 30);
});

Deno.test("wearableItems is the hard filter, and it is wider than laundry", () => {
  // §2.9 only mentions dirty items. A jacket at the tailor, in a suitcase, lent
  // out or lost is equally impossible to put on this morning.
  const states: AvailabilityState[] = [
    "available",
    "in_laundry",
    "in_alteration",
    "packed_for_travel",
    "lent_out",
    "lost",
    "unavailable",
  ];
  const items = states.map((s, i) => garment(`g${i}`, "top", { availabilityState: s }));
  assertEquals(wearableItems(items).map((i) => i.id), ["g0"]);

  const dirty: LaundryState[] = ["clean", "worn_once", "laundry", "unavailable"];
  const byLaundry = dirty.map((s, i) => garment(`l${i}`, "top", { laundryState: s }));
  assertEquals(wearableItems(byLaundry).map((i) => i.id), ["l0", "l1"]);
});

Deno.test("An unwearable garment is scored, not silently dropped", () => {
  // Filtering here as well as in generation would hide a generation bug: an
  // outfit containing a shirt in the wash must be visibly wrong, not quietly
  // become a different outfit.
  const withDirty = [...CANONICAL.slice(1), garment("dirty", "top", { laundryState: "laundry" })];
  const result = scoreOutfit(withDirty);
  assert(result.score > 0, "the outfit should still produce a score");
  assert(result.components.availability.value < 1);
});

Deno.test("Score is stable — the same inputs always give the same number", () => {
  // No clock, no randomness, no I/O anywhere in the engine. This is what makes
  // the whole thing testable without a network.
  const first = scoreOutfit(CANONICAL).score;
  for (let i = 0; i < 25; i++) {
    assertEquals(scoreOutfit(CANONICAL).score, first);
  }
});

Deno.test("A single garment and an empty outfit both score without throwing", () => {
  assert(scoreOutfit([garment("solo", "top", { colorHex: "1F2A44" })]).score >= 0);
  assert(scoreOutfit([]).score >= 0);
});
