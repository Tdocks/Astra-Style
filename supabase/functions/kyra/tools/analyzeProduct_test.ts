import { assertEquals } from "@std/assert";
import { type AnalyzeProductDeps, executeAnalyzeProduct } from "./analyzeProduct.ts";

Deno.test("invalid and unsafe product arguments never call services", async () => {
  const fail = () => {
    throw new Error("Must not call services");
  };
  const deps: AnalyzeProductDeps = { extract: fail, find: fail, evaluate: fail };
  for (
    const args of [
      {},
      { product_candidate_id: "bad" },
      { product_url: "http://127.0.0.1/private" },
      { product_url: "https://shop.example.com", product_candidate_id: "bad" },
    ]
  ) {
    assertEquals((await executeAnalyzeProduct(args, deps)).error, "INVALID_ARGUMENTS");
  }
});

Deno.test("a missing catalog product produces no invented verdict", async () => {
  const fail = () => {
    throw new Error("Must not evaluate a missing product");
  };
  const result = await executeAnalyzeProduct(
    { product_candidate_id: "11111111-1111-4111-8111-111111111111" },
    { find: () => Promise.resolve(null), extract: fail, evaluate: fail },
  );
  assertEquals(result.error, "PRODUCT_NOT_FOUND");
  assertEquals(result.verdict, undefined);
});

Deno.test("existing product evaluation preserves scores and affiliate disclosure", async () => {
  const id = "11111111-1111-4111-8111-111111111111";
  const result = await executeAnalyzeProduct({ product_candidate_id: id }, {
    extract: () => {
      throw new Error("Unexpected extraction");
    },
    find: () =>
      Promise.resolve({
        id,
        canonical_url: "https://shop.example.com/item",
        retailer: "Fixture retailer",
        name: "Fixture shirt",
        category: "top",
        affiliate_url: "https://shop.example.com/item?affiliate=fixture",
        sponsored: true,
        fields_below_confidence_threshold: [],
        availability: {},
        attributes: {},
      }),
    evaluate: () =>
      Promise.resolve({
        user_id: id,
        product_candidate_id: id,
        fills_gap: true,
        gap_details: [{
          occasion: "unconstrained",
          formality_bucket: 2,
          qualifying_before: 1,
          qualifying_after: 2,
          fills_gap: true,
        }],
        compatibility_score: 82,
        redundancy_score: 25,
        outfits_unlocked: 4,
        expected_cost_per_wear: null,
        verdict: "consider",
        reasoning: "Measured fixture",
        created_at: new Date().toISOString(),
        color_fit: null,
        lifestyle_fit: null,
        budget_fit: null,
        sponsored: true,
        unmeasured: ["price"],
        alternatives: [],
      }),
  });
  assertEquals(result.fills_gap, true);
  assertEquals(result.gap_details, [{
    occasion: "unconstrained",
    formality_bucket: 2,
    qualifying_before: 1,
    qualifying_after: 2,
    fills_gap: true,
  }]);
  assertEquals(result.redundancy_risk, 0.25);
  assertEquals(result.compatibility_score, 82);
  assertEquals(result.expected_cost_per_wear, null);
  const product = result.product as Record<string, unknown>;
  assertEquals(product.price, null);
  assertEquals(product.is_sponsored, true);
  assertEquals(typeof product.affiliate_disclosure, "string");
});
