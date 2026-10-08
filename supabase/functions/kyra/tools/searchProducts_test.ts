import { assertEquals } from "@std/assert";
import {
  executeSearchProducts,
  matchesProductFilters,
  parseProductSearch,
} from "./searchProducts.ts";

Deno.test("search filters reject malformed ranges, budgets and limits", () => {
  for (
    const overrides of [
      { limit: 26 },
      { price_max: -1 },
      { price_max: Infinity },
      { formality_range: [80, 20] },
      { formality_range: [0, 101] },
      { query_text: " " },
    ]
  ) {
    assertEquals(parseProductSearch({ query_text: "casual shirt", ...overrides }), null);
  }
  assertEquals(parseProductSearch({ query_text: " casual shirt " })?.limit, 10);
});

Deno.test("empty catalog produces no invented products", async () => {
  const result = await executeSearchProducts({ query_text: "shirt" }, {
    search: () => Promise.resolve([]),
  });
  assertEquals(result.error, "NO_RESULTS");
  assertEquals(result.products, []);
});

Deno.test("organic relevance wins over sponsorship and duplicate results are removed", async () => {
  const product = (id: string, sponsored: boolean) => ({
    id,
    canonical_url: "https://shop.example.com/item",
    retailer: "Fixture",
    name: "Shirt",
    category: "top",
    availability: {},
    attributes: {},
    sponsored,
    fields_below_confidence_threshold: [],
    affiliate_url: sponsored ? "https://shop.example.com/affiliate" : undefined,
  });
  const result = await executeSearchProducts({ query_text: "shirt", limit: 2 }, {
    search: () =>
      Promise.resolve([
        { product: product("sponsored", true), relevance: 0.4 },
        { product: product("organic", false), relevance: 0.9 },
        { product: product("organic", false), relevance: 0.8 },
      ]),
  });
  const products = result.products as Record<string, unknown>[];
  assertEquals(products.map((row) => row.product_candidate_id), ["organic", "sponsored"]);
  assertEquals(products[0]?.price, null);
  assertEquals(typeof products[1]?.affiliate_disclosure, "string");
});

Deno.test("strict product filters reject missing attributes and inferred category defaults", () => {
  const args = parseProductSearch({
    query_text: "shirt",
    category: "top",
    price_max: 100,
    color: "Navy",
    formality_range: [20, 50],
  });
  if (!args) throw new Error("Invalid fixture");
  const product = {
    id: "fixture",
    canonical_url: "https://shop.example.com/item",
    retailer: "Fixture",
    name: "Shirt",
    category: "top",
    price: 80,
    availability: {},
    attributes: { color: "navy", formality_score: 30 },
    sponsored: false,
    fields_below_confidence_threshold: [] as string[],
  };
  assertEquals(matchesProductFilters(product, args), true);
  assertEquals(matchesProductFilters({ ...product, price: undefined }, args), false);
  assertEquals(matchesProductFilters({ ...product, attributes: {} }, args), false);
  assertEquals(
    matchesProductFilters({ ...product, fields_below_confidence_threshold: ["category"] }, args),
    false,
  );
  assertEquals(matchesProductFilters({ ...product, price: 101 }, args), false);
});
