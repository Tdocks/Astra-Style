import { assert, assertAlmostEquals } from "jsr:@std/assert@1";
import {
  isDuplicateRisk,
  labFromLCh,
  type RedundancyItem,
  redundancyScore,
  seasonalityOverlaps,
  similarity,
} from "./redundancy.ts";
import { rgbToLab } from "./colorSpace.ts";

function item(id: string, over: Partial<RedundancyItem> = {}): RedundancyItem {
  return {
    id,
    category: "top",
    role: "top",
    primaryColorLab: null,
    formalityScore: null,
    fit: null,
    materials: [],
    seasonality: [],
    ...over,
  };
}

Deno.test("Test 30 (§9): two items identical in colour/formality/fit/material score similarity >= 0.85 and flag as duplicate", () => {
  const navy = rgbToLab({ r: 20, g: 30, b: 70 });
  const a = item("a", {
    primaryColorLab: navy,
    formalityScore: 40,
    fit: "regular",
    materials: ["cotton"],
  });
  const b = item("b", {
    primaryColorLab: navy,
    formalityScore: 40,
    fit: "regular",
    materials: ["cotton"],
  });
  const score = similarity(a, b);
  assert(score >= 0.85, `expected >=0.85, got ${score}`);
  assert(isDuplicateRisk(a, b));
});

Deno.test("Two items far apart in every axis score low similarity and are not flagged", () => {
  const navy = rgbToLab({ r: 20, g: 30, b: 70 });
  const cream = rgbToLab({ r: 245, g: 240, b: 220 });
  const a = item("a", {
    primaryColorLab: navy,
    formalityScore: 20,
    fit: "slim",
    materials: ["wool"],
  });
  const b = item("b", {
    primaryColorLab: cream,
    formalityScore: 90,
    fit: "oversized",
    materials: ["linen"],
  });
  assert(!isDuplicateRisk(a, b));
});

Deno.test("Test 31 (§9): non-overlapping seasonality excludes items from each other's redundancy set regardless of raw similarity", () => {
  const navy = rgbToLab({ r: 20, g: 30, b: 70 });
  const linenShirt = item("linen", {
    primaryColorLab: navy,
    formalityScore: 40,
    fit: "regular",
    materials: ["linen"],
    seasonality: ["summer"],
  });
  const woolSweater = item("wool", {
    primaryColorLab: navy,
    formalityScore: 40,
    fit: "regular",
    materials: ["linen"], // deliberately overlapping material, to isolate the seasonality gate
    seasonality: ["winter"],
  });
  // Raw similarity would be very high (same colour/formality/fit/material) —
  // the seasonality gate is what must keep them out of each other's set.
  assert(similarity(linenShirt, woolSweater) >= 0.85);
  assert(!seasonalityOverlaps(linenShirt.seasonality, woolSweater.seasonality));
  assertAlmostEquals(redundancyScore(linenShirt, [linenShirt, woolSweater]), 0);
});

Deno.test("Untagged seasonality (empty array) is treated as 'all seasons', not excluded from every comparison", () => {
  const navy = rgbToLab({ r: 20, g: 30, b: 70 });
  const a = item("a", {
    primaryColorLab: navy,
    formalityScore: 40,
    fit: "regular",
    seasonality: [],
  });
  const b = item("b", {
    primaryColorLab: navy,
    formalityScore: 40,
    fit: "regular",
    seasonality: ["winter"],
  });
  assert(seasonalityOverlaps(a.seasonality, b.seasonality));
});

Deno.test("redundancyScore is the MAX similarity to any comparator, not the mean", () => {
  const navy = rgbToLab({ r: 20, g: 30, b: 70 });
  const cream = rgbToLab({ r: 245, g: 240, b: 220 });
  const target = item("target", { primaryColorLab: navy, formalityScore: 40, fit: "regular" });
  const near = item("near", { primaryColorLab: navy, formalityScore: 40, fit: "regular" });
  const far = item("far", { primaryColorLab: cream, formalityScore: 10, fit: "oversized" });
  const score = redundancyScore(target, [target, near, far]);
  assertAlmostEquals(score, similarity(target, near), 1e-9);
});

Deno.test("labFromLCh round-trips a neutral colour to ~zero chroma in Lab", () => {
  const lab = labFromLCh({ l: 50, c: 0, h: 0 });
  assertAlmostEquals(lab.a, 0, 1e-9);
  assertAlmostEquals(lab.b, 0, 1e-9);
});
