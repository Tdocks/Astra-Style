import { assert, assertEquals } from "jsr:@std/assert@1";
import { DEFAULT_WEIGHTS, scoreOutfit } from "./compatibility.ts";
import {
  loadCompatibilityWeightsConfig,
  parseCompatibilityWeightsConfig,
} from "./compatibilityWeights.ts";
import { rgbToLCh } from "./colorSpace.ts";
import type { ScorableItem } from "./types.ts";

function garment(
  id: string,
  role: ScorableItem["role"],
  colorHex: string,
  formalityScore: number,
): ScorableItem {
  const value = Number.parseInt(colorHex, 16);
  const color = rgbToLCh({ r: value >> 16, g: (value >> 8) & 255, b: value & 255 });
  return {
    id,
    category: role,
    role,
    primaryColor: color,
    isNeutral: false,
    secondaryColors: [],
    pattern: "solid",
    patternScale: null,
    materials: [],
    formalityScore,
    fit: "regular",
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
  };
}

const validRow = (weights: unknown = DEFAULT_WEIGHTS, version = 7) => ({ weights, version });

Deno.test("compatibility config accepts a bounded vector and preserves valid zero weights", () => {
  const weights = { ...DEFAULT_WEIGHTS, coWear: 0, color: 0.35 };
  assertEquals(parseCompatibilityWeightsConfig(validRow(weights)), { weights, version: 7 });
});

Deno.test("invalid compatibility config falls back to defaults while retaining safe version", () => {
  for (
    const weights of [
      { ...DEFAULT_WEIGHTS, color: Number.NaN },
      { ...DEFAULT_WEIGHTS, color: -0.1 },
      { ...DEFAULT_WEIGHTS, color: 1.1 },
      { ...DEFAULT_WEIGHTS, extra: 0 },
      Object.fromEntries(Object.keys(DEFAULT_WEIGHTS).map((key) => [key, 0])),
      { ...DEFAULT_WEIGHTS, color: "0.25" },
    ]
  ) {
    assertEquals(parseCompatibilityWeightsConfig(validRow(weights)).weights, DEFAULT_WEIGHTS);
    assertEquals(parseCompatibilityWeightsConfig(validRow(weights)).version, 7);
  }
  assertEquals(parseCompatibilityWeightsConfig({ ...validRow(), version: 0 }).version, 1);
});

Deno.test("loaded config changes actual compatibility scoring, not just response metadata", () => {
  const parsed = parseCompatibilityWeightsConfig(validRow({
    ...DEFAULT_WEIGHTS,
    color: 1,
    formality: 0,
    silhouette: 0,
    seasonWeather: 0,
    userPreference: 0,
    coWear: 0,
    occasion: 0,
    availability: 0,
  }));
  const outfit = [
    garment("top", "top", "111111", 90),
    garment("bottom", "bottom", "EEEEEE", 20),
  ];
  assert(scoreOutfit(outfit).score !== scoreOutfit(outfit, {}, { weights: parsed.weights }).score);
  assertEquals(scoreOutfit(outfit, {}, { weights: parsed.weights }).weights, parsed.weights);
});

Deno.test("loader reads only the singleton service configuration and safely degrades on read failure", async () => {
  const calls: unknown[] = [];
  const fakeClient = {
    from(table: string) {
      calls.push(table);
      return {
        select(columns: string) {
          calls.push(columns);
          return {
            eq(column: string, value: boolean) {
              calls.push([column, value]);
              return { maybeSingle: () => Promise.resolve({ data: validRow(), error: null }) };
            },
          };
        },
      };
    },
  };
  assertEquals((await loadCompatibilityWeightsConfig(fakeClient)).version, 7);
  assertEquals(calls, ["compatibility_weights_config", "weights, version", ["singleton", true]]);

  const failed = {
    from() {
      return {
        select() {
          return {
            eq() {
              return { maybeSingle: () => Promise.resolve({ data: null, error: {} }) };
            },
          };
        },
      };
    },
  };
  assertEquals(await loadCompatibilityWeightsConfig(failed), {
    weights: DEFAULT_WEIGHTS,
    version: 1,
  });
});
