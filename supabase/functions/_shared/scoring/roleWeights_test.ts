import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import { aggregatePairs, rolePairKey, weightedPairs } from "./roleWeights.ts";
import type { GarmentRole } from "./types.ts";

const item = (id: string, role: GarmentRole) => ({ id, role });

const TOP = item("t", "top");
const BOTTOM = item("b", "bottom");
const SHOES = item("s", "shoes");
const OUTERWEAR = item("o", "outerwear");

function totalWeight(pairs: readonly { weight: number }[]): number {
  return pairs.reduce((sum, p) => sum + p.weight, 0);
}

Deno.test("rolePairKey is order-free", () => {
  assertEquals(rolePairKey("top", "bottom"), rolePairKey("bottom", "top"));
});

Deno.test("Weights always renormalise to 1, whatever the outfit contains", () => {
  // The property that makes the table usable. If this ever drifts, every
  // pairwise component silently scores on a different scale than the others.
  const outfits = [
    [TOP, BOTTOM, SHOES],
    [TOP, BOTTOM, SHOES, OUTERWEAR],
    [TOP, BOTTOM],
    [TOP, BOTTOM, SHOES, OUTERWEAR, item("a1", "accessory")],
    [TOP, BOTTOM, SHOES, item("a1", "accessory"), item("a2", "accessory")],
  ];
  for (const outfit of outfits) {
    const pairs = weightedPairs(outfit);
    assertAlmostEquals(totalWeight(pairs), 1, 1e-9, `outfit of ${outfit.length}`);
  }
});

Deno.test("The doc's canonical three-piece outfit renormalises 0.75 → 1", () => {
  // §2.2's worked example divides by exactly this. If the arithmetic here
  // changes, every worked example in the doc stops reproducing.
  const pairs = weightedPairs([TOP, BOTTOM, SHOES]);
  assertEquals(pairs.length, 3);
  const byKey = new Map(pairs.map((p) => [rolePairKey(p.a.role, p.b.role), p.weight]));
  assertAlmostEquals(byKey.get(rolePairKey("top", "bottom"))!, 0.35 / 0.75, 1e-9);
  assertAlmostEquals(byKey.get(rolePairKey("top", "shoes"))!, 0.20 / 0.75, 1e-9);
  assertAlmostEquals(byKey.get(rolePairKey("bottom", "shoes"))!, 0.20 / 0.75, 1e-9);
});

Deno.test("Top–bottom outweighs every other pair, which is the point of the table", () => {
  const pairs = weightedPairs([TOP, BOTTOM, SHOES, OUTERWEAR]);
  const topBottom = pairs.find((p) =>
    rolePairKey(p.a.role, p.b.role) === rolePairKey("top", "bottom")
  )!;
  for (const other of pairs) {
    if (other === topBottom) continue;
    assert(
      topBottom.weight > other.weight,
      `top-bottom (${topBottom.weight}) should outweigh ${other.a.role}-${other.b.role}`,
    );
  }
});

Deno.test("Accessories are capped at 0.10 of the raw budget however many are worn", () => {
  // A man in a watch, a belt, a scarf and a pocket square must not have his
  // accessories out-vote his trousers.
  const many = [TOP, BOTTOM, SHOES];
  for (let i = 0; i < 6; i++) many.push(item(`a${i}`, "accessory"));
  const pairs = weightedPairs(many);
  const accessoryShare = pairs
    .filter((p) => p.a.role === "accessory" || p.b.role === "accessory")
    .reduce((sum, p) => sum + p.weight, 0);
  // 0.10 of a 0.85 raw total once renormalised.
  assertAlmostEquals(accessoryShare, 0.10 / 0.85, 1e-9);
  assert(accessoryShare < 0.13, `accessories took ${accessoryShare} of the outfit`);
});

Deno.test("Two accessories are never paired with each other", () => {
  const pairs = weightedPairs([TOP, BOTTOM, item("a1", "accessory"), item("a2", "accessory")]);
  const accessoryPair = pairs.find((p) => p.a.role === "accessory" && p.b.role === "accessory");
  assertEquals(accessoryPair, undefined);
});

Deno.test("Outerwear–shoes carries no weight rather than an invented one", () => {
  // §2.1 does not list it. Dropping it is the honest reading; giving it a
  // default would be inventing a rule the design never made.
  const pairs = weightedPairs([OUTERWEAR, SHOES]);
  assertEquals(pairs.length, 0);
});

Deno.test("A single garment has no pairs, and that is null rather than zero", () => {
  // Zero would say "these clash". There is nothing to clash with.
  assertEquals(weightedPairs([TOP]).length, 0);
  assertEquals(aggregatePairs([TOP], () => 1), null);
  assertEquals(aggregatePairs([], () => 1), null);
});

Deno.test("aggregatePairs returns the constant when every pair scores the same", () => {
  // Sanity on the renormalisation: weights summing to 1 means a uniform 0.8
  // has to come back as 0.8 exactly, for any outfit shape.
  for (const outfit of [[TOP, BOTTOM], [TOP, BOTTOM, SHOES], [TOP, BOTTOM, SHOES, OUTERWEAR]]) {
    assertAlmostEquals(aggregatePairs(outfit, () => 0.8)!, 0.8, 1e-9);
  }
});

Deno.test("A worked aggregate matches hand arithmetic", () => {
  // top-bottom 0.9, top-shoes 0.6, bottom-shoes 0.3 over the 0.75 outfit:
  // (0.35×0.9 + 0.20×0.6 + 0.20×0.3) / 0.75 = (0.315+0.12+0.06)/0.75 = 0.66
  const score = aggregatePairs([TOP, BOTTOM, SHOES], (a, b) => {
    const key = rolePairKey(a.role, b.role);
    if (key === rolePairKey("top", "bottom")) return 0.9;
    if (key === rolePairKey("top", "shoes")) return 0.6;
    return 0.3;
  });
  assertAlmostEquals(score!, 0.66, 1e-9);
});
