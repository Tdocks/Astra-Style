import { assert, assertEquals } from "@std/assert";
import { buildReason } from "./reason.ts";
import { DEFAULT_WEIGHTS } from "../_shared/scoring/compatibility.ts";
import type { CompatibilityScore, ComponentName } from "../_shared/scoring/compatibility.ts";
import {
  degradedScore,
  measured,
  type ScorableItem,
  type Subscore,
} from "../_shared/scoring/types.ts";

function garment(id: string, role: ScorableItem["role"]): ScorableItem {
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
  };
}

const ALL_DEGRADED: Record<ComponentName, Subscore> = {
  color: degradedScore(0.6, "colour of x (never analysed)"),
  formality: degradedScore(1, "a second garment to compare formality against"),
  silhouette: degradedScore(0.75, "a second garment to compare silhouette against"),
  seasonWeather: degradedScore(0.75, "today's weather (no forecast available)"),
  userPreference: degradedScore(0.7, "your stated colour, fit and formality preferences"),
  coWear: degradedScore(0.667, "what you have worn together before (no wear history yet)"),
  occasion: measured(0.8),
  availability: measured(1),
};

function scoreWith(overrides: Partial<Record<ComponentName, Subscore>>): CompatibilityScore {
  const components = { ...ALL_DEGRADED, ...overrides };
  return {
    score: 70,
    components,
    weights: DEFAULT_WEIGHTS,
    degraded: Object.values(components).flatMap((c) => c.degraded),
    formalityRegister: 50,
  };
}

Deno.test("falls back to a structural sentence when every component is degraded", () => {
  const items = [garment("t", "top"), garment("b", "bottom"), garment("s", "shoes")];
  const reason = buildReason(items, scoreWith({}));
  assertEquals(reason, "Put together from your closet: top, bottom, shoes.");
});

Deno.test("never mentions a component the score itself marked degraded", () => {
  const items = [garment("t", "top"), garment("b", "bottom")];
  const reason = buildReason(
    items,
    scoreWith({ color: degradedScore(0.95, "colour of t (never analysed)") }),
  );
  assert(!reason.toLowerCase().includes("color"), `reason leaked a degraded claim: ${reason}`);
});

Deno.test("names a measured, strong component", () => {
  const items = [garment("t", "top"), garment("b", "bottom")];
  const reason = buildReason(items, scoreWith({ color: measured(0.9) }));
  assertEquals(reason, "The colors work well together.");
});

Deno.test("combines up to two measured strong components, heaviest first", () => {
  const items = [garment("t", "top"), garment("b", "bottom")];
  const reason = buildReason(
    items,
    scoreWith({ color: measured(0.9), formality: measured(0.85), silhouette: measured(0.9) }),
  );
  assertEquals(reason, "The colors work well together and everything matches in formality.");
});

Deno.test("a measured but weak component is not claimed", () => {
  const items = [garment("t", "top"), garment("b", "bottom")];
  const reason = buildReason(items, scoreWith({ color: measured(0.5) }));
  assertEquals(reason, "Put together from your closet: top, bottom.");
});

Deno.test("role counts pluralize for more than one of the same role", () => {
  const items = [
    garment("t", "top"),
    garment("b", "bottom"),
    garment("s", "shoes"),
    garment("a1", "accessory"),
    garment("a2", "accessory"),
  ];
  const reason = buildReason(items, scoreWith({}));
  assertEquals(reason, "Put together from your closet: top, bottom, shoes, 2 accessories.");
});
