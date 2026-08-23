import { assertEquals } from "@std/assert";
import { MockProductExtractionProvider } from "../_shared/providers/mockProductExtraction.ts";
import type { ProductCandidateRow } from "./candidateMapper.ts";
import {
  handleEvaluateProduct,
  handleExtractProduct,
  type ProductsDependencies,
} from "./handler.ts";

const USER = "aaaaaaaa-0000-4000-8000-000000000001";
const SAFE_URL = "https://www.example-retailer.com/products/navy-blazer";

function candidateRow(id: string): ProductCandidateRow {
  return {
    id,
    canonical_url: SAFE_URL,
    retailer: "example-retailer.com",
    brand: "Example",
    name: "Navy oxford",
    category: "top",
    price: 128,
    currency: "USD",
    image_url: null,
    affiliate_url: null,
    availability: {},
    attributes: { color: "navy", material: "cotton", fit: "regular" },
    sponsored: false,
    last_checked_at: "2026-08-23T00:00:00Z",
  };
}

function deps(over: Partial<ProductsDependencies> = {}): ProductsDependencies {
  return {
    extractionProvider: new MockProductExtractionProvider(),
    upsertCandidate: (row) =>
      Promise.resolve({
        ...candidateRow("cand-1"),
        canonical_url: row.canonical_url,
        name: row.name,
      }),
    fetchCandidate: () => Promise.resolve(candidateRow("cand-1")),
    fetchCloset: () => Promise.resolve([]),
    fetchLifestyle: () => Promise.resolve({ monthlyBudget: null, dressCode: null }),
    fetchAlternatives: () => Promise.resolve([]),
    persistEvaluation: () => Promise.resolve({ created_at: "2026-08-23T00:00:00Z" }),
    fetchLatestEvaluatedCandidates: () => Promise.resolve([]),
    requestID: "quota-test",
    hasActivePremiumSubscription: () => Promise.resolve(false),
    countEvaluations: () => Promise.resolve(1),
    ...over,
  };
}

Deno.test("extract 429s after the free paste-evaluate pair", async () => {
  try {
    await handleExtractProduct({ url: SAFE_URL }, USER, deps());
    throw new Error("expected quota");
  } catch (error) {
    assertEquals((error as { status?: number }).status, 429);
  }
});

Deno.test("evaluate 429s after the free paste-evaluate pair", async () => {
  try {
    await handleEvaluateProduct(
      { product_candidate_id: "aaaaaaaa-0000-4000-8000-000000000099" },
      USER,
      deps(),
    );
    throw new Error("expected quota");
  } catch (error) {
    assertEquals((error as { status?: number }).status, 429);
  }
});

Deno.test("premium skips the paste-evaluate quota", async () => {
  const row = await handleExtractProduct(
    { url: SAFE_URL },
    USER,
    deps({ hasActivePremiumSubscription: () => Promise.resolve(true) }),
  );
  assertEquals(typeof row.name, "string");
});
