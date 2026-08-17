import { assertEquals } from "@std/assert";
import { projectedCostPerWear, versatilityMultiplier } from "./costPerWear.ts";

Deno.test("versatilityMultiplier: 0 versatility -> 0.5, 1.0 versatility -> 1.5", () => {
  assertEquals(versatilityMultiplier(0), 0.5);
  assertEquals(versatilityMultiplier(1), 1.5);
  assertEquals(versatilityMultiplier(0.5), 1.0);
});

Deno.test("versatilityMultiplier: clamps out-of-range input", () => {
  assertEquals(versatilityMultiplier(-1), 0.5);
  assertEquals(versatilityMultiplier(2), 1.5);
});

Deno.test("projectedCostPerWear: null price yields null value, never $0 or NaN", () => {
  const result = projectedCostPerWear(null, "top", 0.5);
  assertEquals(result.value, null);
  assertEquals(result.isProjected, true);
});

Deno.test("projectedCostPerWear: an unmodeled category (fragrance) yields null, not a fabricated rate", () => {
  const result = projectedCostPerWear(50, "fragrance", 0.5);
  assertEquals(result.value, null);
});

Deno.test("projectedCostPerWear: computes a finite, positive value for a priced top", () => {
  const result = projectedCostPerWear(100, "top", 0.5);
  // baseRate(top)=25 * multiplier(0.5)=1.0 -> 25 projected wears/yr -> 100/25 = 4.
  assertEquals(result.value, 4);
});

Deno.test("projectedCostPerWear: never divides by zero even at zero versatility", () => {
  const result = projectedCostPerWear(100, "outerwear", 0);
  assertEquals(Number.isFinite(result.value), true);
  assertEquals(result.value !== null && result.value > 0, true);
});

Deno.test("projectedCostPerWear: higher versatility yields a lower (better) cost per wear at the same price", () => {
  const low = projectedCostPerWear(100, "shoes", 0.1);
  const high = projectedCostPerWear(100, "shoes", 0.9);
  assertEquals(low.value !== null && high.value !== null && high.value < low.value, true);
});

Deno.test("projectedCostPerWear: always reports usedDefaultCadence and a degraded reason", () => {
  const result = projectedCostPerWear(100, "top", 0.5);
  assertEquals(result.usedDefaultCadence, true);
  assertEquals(result.degraded.length > 0, true);
});
