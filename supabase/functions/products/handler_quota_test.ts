import { assertEquals } from "@std/assert";
import { MockProductExtractionProvider } from "../_shared/providers/mockProductExtraction.ts";
import { morningLoopQuotaError } from "../_shared/premium.ts";
import type { ProductEvaluationDTO } from "./schema.ts";
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
    readPreferences: () => Promise.resolve(undefined),
    listWearHistory: () => Promise.resolve([]),
    listWornOutfitItems: () => Promise.resolve([]),
    fetchLifestyle: () => Promise.resolve({ monthlyBudget: null, dressCode: null }),
    fetchAlternatives: () => Promise.resolve([]),
    persistEvaluation: async (row, payload) => {
      const premium = await (over.hasActivePremiumSubscription?.(
        row.user_id,
        new Date().toISOString(),
      ) ??
        Promise.resolve(false));
      const used = await (over.countEvaluations?.(row.user_id) ?? Promise.resolve(1));
      if (!premium && used >= 1) {
        throw morningLoopQuotaError(
          "paste_product_evaluation_trial",
          1,
          0,
          "trial used",
        );
      }
      return { ...payload, created_at: "2026-08-23T00:00:00Z" };
    },
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
    assertEquals(
      (error as { category?: string }).category,
      "subscription_limit_reached",
    );
    assertEquals((error as { details?: Record<string, unknown> }).details, {
      limit: "paste_product_evaluation_trial",
      limit_count: 1,
      remaining: 0,
      resets_at: null,
    });
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
    assertEquals(
      (error as { category?: string }).category,
      "subscription_limit_reached",
    );
    assertEquals((error as { details?: Record<string, unknown> }).details, {
      limit: "paste_product_evaluation_trial",
      limit_count: 1,
      remaining: 0,
      resets_at: null,
    });
  }
});

Deno.test("a committed evaluation retry returns its full DTO before candidate or scorer reads", async () => {
  const saved = {
    user_id: USER,
    product_candidate_id: "aaaaaaaa-0000-4000-8000-000000000099",
    compatibility_score: 73,
    redundancy_score: 12,
    outfits_unlocked: 4,
    expected_cost_per_wear: null,
    verdict: "consider",
    reasoning: "Saved recommendation.",
    created_at: "2026-08-23T00:00:00Z",
    color_fit: null,
    lifestyle_fit: null,
    budget_fit: null,
    sponsored: false,
    unmeasured: [],
    alternatives: [],
  } as ProductEvaluationDTO;
  const replayed = await handleEvaluateProduct(
    { product_candidate_id: saved.product_candidate_id },
    USER,
    deps({
      fetchCandidate: () => Promise.reject(new Error("must not fetch candidate on replay")),
      findEvaluationReplay: (userID, requestID, fingerprint) => {
        assertEquals(userID, USER);
        assertEquals(requestID, "quota-test");
        assertEquals(fingerprint.length, 64);
        return Promise.resolve(saved);
      },
    }),
  );
  assertEquals(replayed, saved);
});

Deno.test("premium skips the paste-evaluate quota", async () => {
  const row = await handleExtractProduct(
    { url: SAFE_URL },
    USER,
    deps({ hasActivePremiumSubscription: () => Promise.resolve(true) }),
  );
  assertEquals(typeof row.name, "string");
});
