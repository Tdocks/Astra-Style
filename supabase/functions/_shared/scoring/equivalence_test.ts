import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import {
  canonicalSignature,
  colorClusterId,
  equivalenceClass,
  formalityBucket,
  hueBin,
  sameEquivalenceClass,
} from "./equivalence.ts";
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
    fit: null,
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
    ...rest,
  };
}

Deno.test("hueBin covers 0-11 across the full circle, wrapping at 360", () => {
  assertEquals(hueBin(0), 0);
  assertEquals(hueBin(29), 0);
  assertEquals(hueBin(30), 1);
  assertEquals(hueBin(359), 11);
  assertEquals(hueBin(360), 0);
  assertEquals(hueBin(-10), 11); // 350°
});

Deno.test("A functional neutral clusters as 'neutral' regardless of hue bin", () => {
  const white = garment("w", "top", { colorHex: "FFFFFF" });
  assertEquals(colorClusterId(white), "neutral");
});

Deno.test("An unanalysed colour folds into the neutral bucket rather than getting its own", () => {
  const unanalysed = garment("u", "top", {});
  assertEquals(unanalysed.primaryColor, null);
  assertEquals(colorClusterId(unanalysed), "neutral");
});

Deno.test("§6.3 formalityBucket floors to the nearest 10, using §2.3's category default when unclassified", () => {
  assertEquals(formalityBucket({ formalityScore: 42, role: "top" }), 4);
  assertEquals(formalityBucket({ formalityScore: 40, role: "top" }), 4);
  // top's category default is 45 → bucket 4.
  assertEquals(formalityBucket({ formalityScore: null, role: "top" }), 4);
  // outerwear's category default is 50 → bucket 5, not top's.
  assertEquals(formalityBucket({ formalityScore: null, role: "outerwear" }), 5);
});

Deno.test("Test 23 (§9): two white t-shirts of the same formality bucket and fit collapse to one signature", () => {
  const outfitA = [
    garment("shirt-1", "top", { colorHex: "FFFFFF", formalityScore: 30, fit: "regular" }),
    garment("chino", "bottom", { colorHex: "C8BEA5", formalityScore: 30, fit: "regular" }),
    garment("sneaker", "shoes", { colorHex: "F5F3EE", formalityScore: 20, fit: "regular" }),
  ];
  const outfitB = [
    garment("shirt-2", "top", { colorHex: "F8F8F5", formalityScore: 31, fit: "regular" }),
    garment("chino", "bottom", { colorHex: "C8BEA5", formalityScore: 30, fit: "regular" }),
    garment("sneaker", "shoes", { colorHex: "F5F3EE", formalityScore: 20, fit: "regular" }),
  ];
  assert(
    sameEquivalenceClass(outfitA[0]!, outfitB[0]!),
    "two whites in the same formality bucket/fit should be equivalent",
  );
  assertEquals(canonicalSignature(outfitA), canonicalSignature(outfitB));
});

Deno.test("Test 24 (§9): swapping a white top for a red one (different colour cluster) does NOT collapse", () => {
  const white = garment("shirt-white", "top", {
    colorHex: "FFFFFF",
    formalityScore: 30,
    fit: "regular",
  });
  const red = garment("shirt-red", "top", {
    colorHex: "C0392B",
    formalityScore: 30,
    fit: "regular",
  });
  assertEquals(
    classifyNeutral(rgbToLCh(hex("C0392B"))).isNeutral,
    false,
    "fixture assumption: this red is chromatic",
  );

  const rest = [
    garment("chino", "bottom", { colorHex: "C8BEA5", formalityScore: 30, fit: "regular" }),
    garment("sneaker", "shoes", { colorHex: "F5F3EE", formalityScore: 20, fit: "regular" }),
  ];
  assert(!sameEquivalenceClass(white, red));
  assertNotEquals(canonicalSignature([white, ...rest]), canonicalSignature([red, ...rest]));
});

Deno.test("canonicalSignature is order-independent (sorted before hashing)", () => {
  const items = [
    garment("top", "top", { colorHex: "223344", formalityScore: 40, fit: "regular" }),
    garment("bottom", "bottom", { colorHex: "556677", formalityScore: 45, fit: "tailored" }),
  ];
  assertEquals(canonicalSignature(items), canonicalSignature([...items].reverse()));
});

Deno.test("equivalenceClass reads the item's own fit, unmodified", () => {
  const slim = garment("a", "top", { fit: "slim" });
  const relaxed = garment("b", "top", { fit: "relaxed" });
  assertEquals(equivalenceClass(slim).fit, "slim");
  assertNotEquals(equivalenceClass(slim).fit, equivalenceClass(relaxed).fit);
});
