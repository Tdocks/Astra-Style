import { assert, assertEquals } from "jsr:@std/assert@1";
import { scoreOutfit } from "./compatibility.ts";
import { generateAnchoredOutfits } from "./outfitGeneration.ts";
import { classifyNeutral, rgbToLCh } from "./colorSpace.ts";
import type { ScorableItem } from "./types.ts";

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
    fit: "regular",
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
    ...rest,
  };
}

const ANCHOR = garment("anchor-top", "top", { colorHex: "6E6E3C", formalityScore: 40 });

// formalityScore climbs away from the anchor's 40 as `i` grows, so pairwise
// compatibility (§2.3: penalty grows with |Δf|) is monotonically decreasing in
// `i` and bottom-0 (Δf=0, an exact match) is unambiguously the single best.
function bottoms(n: number): ScorableItem[] {
  return Array.from(
    { length: n },
    (_, i) => garment(`bottom-${i}`, "bottom", { colorHex: "C8BEA5", formalityScore: 40 + i * 3 }),
  );
}
function shoes(): ScorableItem[] {
  return [garment("shoe", "shoes", { colorHex: "F5F3EE", formalityScore: 22 })];
}

Deno.test("A required role with zero eligible items produces zero qualifying outfits, not an error", () => {
  const result = generateAnchoredOutfits(ANCHOR, [...bottoms(3)] /* no shoes at all */);
  assertEquals(result.qualifying.length, 0);
});

Deno.test("The anchor is fixed into every generated combination", () => {
  const pool = [...bottoms(3), ...shoes()];
  const result = generateAnchoredOutfits(ANCHOR, pool, { qualityThreshold: 0 });
  assert(result.qualifying.length > 0);
  for (const combo of result.qualifying) {
    assert(combo.items.some((i) => i.id === ANCHOR.id));
  }
});

Deno.test("§6.3 dedup: near-duplicate combinations collapse to one signature, keeping the best score", () => {
  // Two bottoms in the same equivalence class (same colour/formality bucket/fit).
  const pool = [
    garment("chino-a", "bottom", { colorHex: "C8BEA5", formalityScore: 50, fit: "regular" }),
    garment("chino-b", "bottom", { colorHex: "CBC1A8", formalityScore: 51, fit: "regular" }),
    ...shoes(),
  ];
  const result = generateAnchoredOutfits(ANCHOR, pool, { qualityThreshold: 0 });
  // Both bottoms + the one pair of shoes + no outerwear/accessories should
  // collapse to exactly one qualifying signature, not two.
  assertEquals(result.qualifying.length, 1);
});

Deno.test("Test 25 (§9), boundary form: raising the threshold past an outfit's own score excludes it; at or below its score includes it", () => {
  const pool = [
    garment("bottom", "bottom", { colorHex: "C8BEA5", formalityScore: 50 }),
    ...shoes(),
  ];
  const combo = [ANCHOR, pool[0]!, pool[1]!];
  const observedScore = scoreOutfit(combo).score; // integer 0-100
  const fraction = observedScore / 100;

  const included = generateAnchoredOutfits(ANCHOR, pool, { qualityThreshold: fraction });
  assertEquals(included.qualifying.length, 1, "at its own score, the combination must qualify");

  const excluded = generateAnchoredOutfits(ANCHOR, pool, { qualityThreshold: fraction + 0.01 });
  assertEquals(
    excluded.qualifying.length,
    0,
    "just above its own score, the combination must be excluded",
  );
});

Deno.test("Test 29 (§9): pruning to a small K still keeps the single best pairwise-compatible item in the pool", () => {
  // 15 bottoms whose formality gap to the anchor's 40 grows monotonically —
  // bottom-0 is closest (Δf=10) and therefore the single best pairwise match.
  const pool = [...bottoms(15), ...shoes()];
  const tightlyPruned = generateAnchoredOutfits(ANCHOR, pool, { slotK: 2, qualityThreshold: 0 });
  const usedBottomIds = new Set(
    tightlyPruned.qualifying.flatMap((c) =>
      c.items.filter((i) => i.role === "bottom").map((i) => i.id)
    ),
  );
  assert(
    usedBottomIds.has("bottom-0"),
    "the single best-matching bottom must survive an aggressive prune",
  );
  // And the worst-matching bottoms (formality furthest from the anchor) must
  // have been pruned away entirely — pruning that kept everyone would not be
  // pruning.
  assert(!usedBottomIds.has("bottom-14"));
});

Deno.test("combinationsScored counts every combination actually evaluated, independent of how many qualify", () => {
  const pool = [...bottoms(2), ...shoes()];
  const result = generateAnchoredOutfits(ANCHOR, pool, { qualityThreshold: 1.1 }); // nothing can qualify
  assertEquals(result.qualifying.length, 0);
  assert(
    result.combinationsScored > 0,
    "combinations should still have been scored and rejected, not skipped",
  );
});
