import { assert, assertEquals } from "jsr:@std/assert@1";
import { computeUnlockCount } from "./unlockCount.ts";
import { classifyNeutral, rgbToLCh } from "./colorSpace.ts";
import type { Fit, GarmentRole, ScorableItem } from "./types.ts";

function hex(value: string) {
  const v = Number.parseInt(value, 16);
  return { r: (v >> 16) & 255, g: (v >> 8) & 255, b: v & 255 };
}

function garment(
  id: string,
  role: GarmentRole,
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
    formalityScore: 40,
    fit: "regular" as Fit,
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
    ...rest,
  };
}

const TOP = garment("top1", "top", { colorHex: "FFFFFF" });
const BOTTOM = garment("bottom1", "bottom", { colorHex: "C8BEA5" });

Deno.test("Deterministic and reproducible: identical inputs produce identical results", () => {
  const candidate = garment("candidate-shoe", "shoes", { colorHex: "222222", fit: "slim" });
  const pool = [
    TOP,
    BOTTOM,
    garment("owned-shoe", "shoes", { colorHex: "774411", fit: "oversized" }),
  ];

  const first = computeUnlockCount(candidate, pool);
  const second = computeUnlockCount(candidate, pool);

  assertEquals(first.unlockCount, second.unlockCount);
  assertEquals(first.novel, second.novel);
  assertEquals(first.combinationsScored, second.combinationsScored);
  assertEquals(
    first.gapsFilled.map((g) => g.fillsGap),
    second.gapsFilled.map((g) => g.fillsGap),
  );
});

Deno.test("Result changes when a new item is added to the closet: adding the missing required role unlocks the candidate", () => {
  const candidate = garment("candidate-shoe", "shoes", { colorHex: "222222", fit: "slim" });

  const withoutBottom = computeUnlockCount(candidate, [TOP]); // no bottom at all: no outfit possible
  assertEquals(withoutBottom.unlockCount, 0);

  const withBottom = computeUnlockCount(candidate, [TOP, BOTTOM]);
  assert(
    withBottom.unlockCount > withoutBottom.unlockCount,
    "adding the missing bottom must unlock at least one outfit",
  );
});

Deno.test("Test 26 (§9): a candidate whose equivalence class is already owned contributes zero net-new unlocks", () => {
  const ownedShoe = garment("owned-shoe", "shoes", {
    colorHex: "202020",
    fit: "regular",
    formalityScore: 40,
  });
  // Same category, colour cluster (both near-black/neutral), formality bucket, and fit as ownedShoe.
  const candidate = garment("candidate-shoe", "shoes", {
    colorHex: "1A1A1A",
    fit: "regular",
    formalityScore: 41,
  });

  const result = computeUnlockCount(candidate, [TOP, BOTTOM, ownedShoe]);
  assertEquals(result.novel, false);
  assertEquals(result.unlockCount, 0);
});

Deno.test("A candidate with no owned equivalence-class substitute is novel and can unlock outfits", () => {
  const ownedShoe = garment("owned-shoe", "shoes", {
    colorHex: "774411",
    fit: "oversized",
    formalityScore: 40,
  });
  const candidate = garment("candidate-shoe", "shoes", {
    colorHex: "222222",
    fit: "slim",
    formalityScore: 40,
  });

  const result = computeUnlockCount(candidate, [TOP, BOTTOM, ownedShoe]);
  assertEquals(result.novel, true);
  assert(result.unlockCount >= 1);
});

Deno.test("Test 27 (§9): gap-filling flips true when a bucket goes from 1 pre-existing qualifying combo to >=2", () => {
  const top = garment("top", "top", { colorHex: "FFFFFF", formalityScore: 40, fit: "regular" });
  const bottom = garment("bottom", "bottom", {
    colorHex: "C8BEA5",
    formalityScore: 40,
    fit: "regular",
  });
  const ownedShoe = garment("owned-shoe", "shoes", {
    colorHex: "1A2A3A",
    formalityScore: 40,
    fit: "regular",
  });
  const candidateShoe = garment("candidate-shoe", "shoes", {
    colorHex: "8A6A2A",
    formalityScore: 40,
    fit: "oversized",
  });

  const result = computeUnlockCount(candidateShoe, [top, bottom, ownedShoe], {
    occasion: "everyday-casual",
  });

  assertEquals(result.novel, true);
  assert(result.gapsFilled.length > 0, "expected at least one formality bucket to be reached");
  const gap = result.gapsFilled[0]!;
  assertEquals(gap.qualifyingBefore, 1);
  assertEquals(gap.qualifyingAfter, 2);
  assertEquals(gap.fillsGap, true);
  assertEquals(gap.occasion, "everyday-casual");
});

Deno.test("Test 27 (§9), negative case: a bucket already at >=2 qualifying combos is not flagged", () => {
  const top = garment("top", "top", { colorHex: "FFFFFF", formalityScore: 40, fit: "regular" });
  const bottom = garment("bottom", "bottom", {
    colorHex: "C8BEA5",
    formalityScore: 40,
    fit: "regular",
  });
  const ownedShoeA = garment("owned-shoe-a", "shoes", {
    colorHex: "1A2A3A",
    formalityScore: 40,
    fit: "regular",
  });
  const ownedShoeB = garment("owned-shoe-b", "shoes", {
    colorHex: "8A6A2A",
    formalityScore: 40,
    fit: "slim",
  });
  const candidateShoe = garment("candidate-shoe", "shoes", {
    colorHex: "2A8A2A",
    formalityScore: 40,
    fit: "oversized",
  });

  const result = computeUnlockCount(candidateShoe, [top, bottom, ownedShoeA, ownedShoeB]);
  const gap = result.gapsFilled[0]!;
  assertEquals(gap.qualifyingBefore >= 2, true);
  assertEquals(gap.fillsGap, false);
});

Deno.test("women's graph: a dress candidate unlocks against shoes without a top", () => {
  const dress = garment("candidate-dress", "dress", { colorHex: "2244AA", fit: "regular" });
  const shoes = garment("owned-shoes", "shoes", { colorHex: "202020", fit: "regular" });
  const menswear = computeUnlockCount(dress, [shoes], {
    scoringContext: { wardrobeGraph: "menswear_3_role" },
    generationOptions: { qualityThreshold: 0 },
  });
  assertEquals(menswear.unlockCount, 0);

  const womenswear = computeUnlockCount(dress, [shoes], {
    scoringContext: { wardrobeGraph: "womenswear" },
    generationOptions: { qualityThreshold: 0 },
  });
  assert(
    womenswear.unlockCount > 0,
    "dress + shoes must form an outfit on the women's graph",
  );
});
