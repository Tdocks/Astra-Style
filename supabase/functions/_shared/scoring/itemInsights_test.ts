import { assert, assertEquals } from "jsr:@std/assert@1";
import { computeItemInsights, type InsightItem } from "./itemInsights.ts";
import { labFromLCh, redundancyScore } from "./redundancy.ts";
function item(id: string, overrides: Partial<InsightItem> = {}): InsightItem {
  return {
    id,
    category: "top",
    role: "top",
    primaryColor: { l: 20, c: 0, h: 0 },
    isNeutral: true,
    secondaryColors: [],
    pattern: null,
    patternScale: null,
    materials: ["cotton"],
    formalityScore: 45,
    fit: "regular",
    seasonality: ["summer"],
    warmthScore: 30,
    waterResistanceScore: 0,
    laundryState: "clean",
    availabilityState: "available",
    archivedAt: null,
    condition: "good",
    ...overrides,
  };
}
Deno.test("insight redundancy matches shared wardrobe formula and excludes archive/other seasons", () => {
  const target = item("target"),
    duplicate = item("duplicate"),
    archived = item("archived", { archivedAt: new Date() }),
    winter = item("winter", { seasonality: ["winter"] });
  const result = computeItemInsights(target, [target, duplicate, archived, winter], []);
  assertEquals(result.redundancyScore, 100);
  assertEquals(result.similarItems.map((x) => x.itemId), ["duplicate"]);
  const projection = (i: InsightItem) => ({
    id: i.id,
    category: i.category,
    role: i.role,
    primaryColorLab: i.primaryColor ? labFromLCh(i.primaryColor) : null,
    formalityScore: i.formalityScore,
    fit: i.fit,
    materials: i.materials,
    seasonality: i.seasonality,
  });
  assertEquals(
    result.redundancyScore,
    Math.round(
      redundancyScore(projection(target), [projection(target), projection(duplicate)]) * 100,
    ),
  );
  assertEquals(computeItemInsights(target, [target, archived, winter], []).redundancyScore, 0);
});
Deno.test("pairing uses available complementary pieces and exposes missing context", () => {
  const target = item("target"),
    pants = item("pants", { category: "bottom", role: "bottom" }),
    wash = item("wash", { category: "shoes", role: "shoes", laundryState: "laundry" });
  const result = computeItemInsights(target, [target, pants, wash, item("same-role")], []);
  assertEquals(result.pairings.map((x) => x.itemId), ["pants"]);
  assert(result.pairings[0]);
  assert(result.pairings[0].missingInputs.length > 0);
  assertEquals(
    computeItemInsights({ ...target, availabilityState: "unavailable" }, [pants], []).pairings,
    [],
  );
});
Deno.test("saved gallery excludes unrelated and archived looks; replacement requires recorded condition", () => {
  const target = item("target");
  const result = computeItemInsights(target, [target], [
    { id: "look", itemIds: ["target"], archivedAt: null },
    { id: "other", itemIds: ["other"], archivedAt: null },
    { id: "archived", itemIds: ["target"], archivedAt: new Date() },
  ]);
  assertEquals(result.savedOutfitIds, ["look"]);
  assertEquals(result.replacementReason, null);
  assertEquals(
    computeItemInsights({ ...target, condition: "damaged" }, [target], []).replacementReason,
    "recorded_damage",
  );
});
Deno.test("unknown target attributes remain disclosed instead of implying certainty", () => {
  const target = item("target", {
    primaryColor: null,
    fit: null,
    materials: [],
    formalityScore: null,
  });
  assertEquals(computeItemInsights(target, [target], []).missingRedundancyInputs, [
    "color",
    "fit",
    "material",
    "formality",
  ]);
});
