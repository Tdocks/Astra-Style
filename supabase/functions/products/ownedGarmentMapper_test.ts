import { assert, assertEquals } from "@std/assert";
import { mapProductCandidateRowToEvaluationInput } from "./candidateMapper.ts";
import { evaluateProductCandidate } from "./evaluation.ts";
import { mapOwnedGarmentForProductEvaluation } from "./ownedGarmentMapper.ts";
import type { ClosetItemMapperRow } from "../_shared/scoring/closetItemMapper.ts";

const FALL_WINTER = ["fall", "winter"];

function closetRow(
  id: string,
  category: string,
  color: string,
  material: readonly { fiber: string; percentage: number }[],
  formality: number,
): ClosetItemMapperRow {
  return {
    id,
    category,
    primary_color: color,
    secondary_colors: [],
    pattern: "solid",
    material,
    fit: "regular",
    seasonality: FALL_WINTER,
    formality_score: formality,
    warmth_score: null,
    water_resistance_score: null,
    laundry_state: "clean",
    availability_state: "available",
  };
}

Deno.test("product evaluation keeps known closet colors for duplicate scoring", () => {
  const closet = [
    mapOwnedGarmentForProductEvaluation(
      closetRow("owned-jacket", "outerwear", "brown", [
        { fiber: "shearling", percentage: 50 },
        { fiber: "leather", percentage: 50 },
      ], 55),
    )!,
    mapOwnedGarmentForProductEvaluation(
      closetRow("owned-chinos", "bottom", "olive", [{ fiber: "cotton", percentage: 100 }], 45),
    )!,
    mapOwnedGarmentForProductEvaluation(
      closetRow("owned-boots", "shoes", "brown", [{ fiber: "leather", percentage: 100 }], 50),
    )!,
  ];
  const productRow = {
    id: "candidate-jacket",
    canonical_url: "https://example.com/products/test-shearling-jacket",
    retailer: "Example",
    brand: "Example",
    name: "Shearling Jacket",
    category: "outerwear",
    price: 998,
    currency: "USD",
    image_url: null,
    affiliate_url: null,
    availability: {},
    attributes: {
      color: "brown",
      materials: ["shearling", "leather"],
      fit: "regular",
      formality_score: 55,
      seasonality: FALL_WINTER,
    },
    sponsored: false,
    last_checked_at: null,
  } as const;
  const mappedCandidate = mapProductCandidateRowToEvaluationInput(productRow);
  assert(mappedCandidate.item);
  assert(mappedCandidate.redundancyItem);

  const result = evaluateProductCandidate({
    candidate: mappedCandidate.item,
    closet: closet.map((item) => item.scorable),
    candidatePrice: productRow.price,
    redundancyCandidate: mappedCandidate.redundancyItem,
    redundancyCloset: closet.map((item) => item.redundancy),
    lifestyle: { monthlyBudget: null, dressCode: null },
  });

  assert(result.redundancyScore >= 85);
  assertEquals(result.verdict, "skip");
  assert(result.reasoning.includes("already own something very close"));
});
