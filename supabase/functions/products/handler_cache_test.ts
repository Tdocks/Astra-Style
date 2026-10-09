import { assertEquals, assertNotEquals } from "@std/assert";
import { MockProductExtractionProvider } from "../_shared/providers/mockProductExtraction.ts";
import type { UnlockCountResult } from "../_shared/scoring/unlockCount.ts";
import type { ProductCandidateRow } from "./candidateMapper.ts";
import { handleEvaluateProduct, type ProductsDependencies } from "./handler.ts";

const USER = "aaaaaaaa-0000-4000-8000-000000000001";
const CANDIDATE_ID = "aaaaaaaa-0000-4000-8000-000000000099";
const RESULT: UnlockCountResult = {
  unlockCount: 7,
  novel: true,
  gapsFilled: [{
    occasion: "unconstrained",
    formalityBucket: 5,
    qualifyingBefore: 0,
    qualifyingAfter: 7,
    fillsGap: true,
  }],
  combinationsScored: 12,
  degraded: [],
};

function product(): ProductCandidateRow {
  return {
    id: CANDIDATE_ID,
    canonical_url: "https://example.com/products/top",
    retailer: "Example",
    brand: "Example",
    name: "Navy shirt",
    category: "top",
    price: 80,
    currency: "USD",
    image_url: null,
    affiliate_url: null,
    availability: {},
    attributes: { color: "navy", fit: "regular", formality_score: 40 },
    sponsored: false,
    last_checked_at: null,
  };
}

function dependencies(over: Partial<ProductsDependencies> = {}): ProductsDependencies {
  return {
    extractionProvider: new MockProductExtractionProvider(),
    upsertCandidate: () => Promise.resolve(product()),
    fetchCandidate: () => Promise.resolve(product()),
    fetchCloset: () => Promise.resolve([]),
    readPreferences: () => Promise.resolve(undefined),
    listWearHistory: () => Promise.resolve([]),
    listWornOutfitItems: () => Promise.resolve([]),
    fetchLifestyle: () => Promise.resolve({ monthlyBudget: null, dressCode: null }),
    fetchAlternatives: () => Promise.resolve([]),
    persistEvaluation: () => Promise.resolve({ created_at: "2026-10-09T00:00:00Z" }),
    fetchLatestEvaluatedCandidates: () => Promise.resolve([]),
    readClosetStateVersion: () => Promise.resolve(9),
    readCompatibilityWeights: () =>
      Promise.resolve({
        weights: {
          color: 0.25,
          formality: 0.2,
          silhouette: 0.15,
          seasonWeather: 0.1,
          userPreference: 0.1,
          coWear: 0.1,
          occasion: 0.05,
          availability: 0.05,
        },
        version: 4,
      }),
    requestID: "cache-test",
    ...over,
  };
}

Deno.test("a cache hit reuses the unlock result without rewriting it", async () => {
  let reads = 0;
  let writes = 0;
  let computations = 0;
  let cacheUserID = "";
  const result = await handleEvaluateProduct(
    { product_candidate_id: CANDIDATE_ID },
    USER,
    dependencies({
      readUnlockCountCache: (userID) => {
        reads++;
        cacheUserID = userID;
        return Promise.resolve(RESULT);
      },
      writeUnlockCountCache: () => {
        writes++;
        return Promise.resolve();
      },
      computeUnlockCount: () => {
        computations++;
        return RESULT;
      },
    }),
  );
  assertEquals(result.outfits_unlocked, 7);
  assertEquals(result.gap_details?.[0]?.qualifying_after, 7);
  assertEquals(reads, 1);
  assertEquals(writes, 0);
  assertEquals(computations, 0);
  assertEquals(cacheUserID, USER);
});

Deno.test("evaluation forwards caller preferences and positive co-wear into scoring and cache identity", async () => {
  const contexts: import("../_shared/scoring/types.ts").ScoringContext[] = [];
  const keys: string[] = [];
  const run = (preferredColors: string[], rating: number) =>
    handleEvaluateProduct(
      { product_candidate_id: CANDIDATE_ID },
      USER,
      dependencies({
        readPreferences: (userID) => {
          assertEquals(userID, USER);
          return Promise.resolve({
            preferredColors,
            avoidedColors: [],
            preferredFit: "regular",
            formalityPreferenceCenter: 50,
          });
        },
        listWearHistory: (userID) => {
          assertEquals(userID, USER);
          return Promise.resolve([{ outfitId: "owned-outfit", rating }]);
        },
        listWornOutfitItems: (userID, outfitIDs) => {
          assertEquals(userID, USER);
          assertEquals(outfitIDs, ["owned-outfit"]);
          return Promise.resolve([
            { outfitId: "owned-outfit", closetItemId: "top-1", category: "top" },
            { outfitId: "owned-outfit", closetItemId: "bottom-1", category: "bottom" },
          ]);
        },
        readUnlockCountCache: () => Promise.resolve(null),
        writeUnlockCountCache: (row) => {
          keys.push(row.cache_key);
          return Promise.resolve();
        },
        computeUnlockCount: (_candidate, _closet, options) => {
          contexts.push(options.scoringContext);
          return RESULT;
        },
      }),
    );

  await run(["navy"], 5);
  await run(["black"], 5);
  await run(["navy"], 1);
  assertEquals(contexts[0]?.preferences?.preferredColors, ["navy"]);
  assertEquals(contexts[0]?.coWearByRole?.get("bottom|top"), {
    totalCoWears: 1,
    positiveCoWears: 1,
  });
  assertEquals("targetFormalityScore" in contexts[0]!, false);
  assertEquals("weather" in contexts[0]!, false);
  assertEquals(contexts[2]?.coWearByRole?.get("bottom|top"), {
    totalCoWears: 1,
    positiveCoWears: 0,
  });
  assertNotEquals(keys[0], keys[1], "preference changes must miss the prior cache key");
  assertNotEquals(keys[0], keys[2], "wear rating/history changes must miss the prior cache key");
});

Deno.test("a closet mutation during scoring prevents publishing the old snapshot", async () => {
  let versionReads = 0;
  let writes = 0;
  let computations = 0;
  const result = await handleEvaluateProduct(
    { product_candidate_id: CANDIDATE_ID },
    USER,
    dependencies({
      readClosetStateVersion: () => Promise.resolve([9, 10, 10][versionReads++] ?? 10),
      readUnlockCountCache: () => Promise.resolve(null),
      writeUnlockCountCache: () => {
        writes++;
        return Promise.resolve();
      },
      computeUnlockCount: () => {
        computations++;
        return { ...RESULT, unlockCount: 0, combinationsScored: 0 };
      },
    }),
  );
  assertEquals(result.outfits_unlocked, 0);
  assertEquals(writes, 0);
  assertEquals(computations, 1);
});

Deno.test("missing or unavailable closet version bypasses cache without failing the evaluation", async () => {
  let cacheReads = 0;
  let writes = 0;
  let computations = 0;
  const result = await handleEvaluateProduct(
    { product_candidate_id: CANDIDATE_ID },
    USER,
    dependencies({
      readClosetStateVersion: () => Promise.resolve(null),
      readUnlockCountCache: () => {
        cacheReads++;
        return Promise.resolve(RESULT);
      },
      writeUnlockCountCache: () => {
        writes++;
        return Promise.resolve();
      },
      computeUnlockCount: () => {
        computations++;
        return { ...RESULT, unlockCount: 1 };
      },
    }),
  );
  assertEquals(result.outfits_unlocked, 1);
  assertEquals(cacheReads, 0);
  assertEquals(writes, 0);
  assertEquals(computations, 1);
});

Deno.test("throwing cache-read or cache-write transport preserves the recommendation and history", async () => {
  let computations = 0;
  let persistedUnlockCount = -1;
  const result = await handleEvaluateProduct(
    { product_candidate_id: CANDIDATE_ID },
    USER,
    dependencies({
      readClosetStateVersion: () => Promise.resolve(9),
      readUnlockCountCache: () => Promise.reject(new Error("cache read transport failed")),
      writeUnlockCountCache: () => Promise.reject(new Error("cache write transport failed")),
      computeUnlockCount: () => {
        computations++;
        return { ...RESULT, unlockCount: 1 };
      },
      persistEvaluation: (row) => {
        persistedUnlockCount = row.outfits_unlocked;
        return Promise.resolve({ created_at: "2026-10-09T00:00:00Z" });
      },
    }),
  );
  assertEquals(result.outfits_unlocked, 1);
  assertEquals(persistedUnlockCount, 1);
  assertEquals(computations, 1);
});

Deno.test("throwing closet-version transport bypasses cache and still persists the verdict", async () => {
  let computations = 0;
  let persisted = false;
  const result = await handleEvaluateProduct(
    { product_candidate_id: CANDIDATE_ID },
    USER,
    dependencies({
      readClosetStateVersion: () => Promise.reject(new Error("version transport failed")),
      readUnlockCountCache: () => Promise.reject(new Error("cache must not be read")),
      writeUnlockCountCache: () => Promise.reject(new Error("cache must not be written")),
      computeUnlockCount: () => {
        computations++;
        return { ...RESULT, unlockCount: 1 };
      },
      persistEvaluation: () => {
        persisted = true;
        return Promise.resolve({ created_at: "2026-10-09T00:00:00Z" });
      },
    }),
  );
  assertEquals(result.outfits_unlocked, 1);
  assertEquals(persisted, true);
  assertEquals(computations, 1);
});

Deno.test("a version change after cache lookup prevents publishing the computed result", async () => {
  let versionReads = 0;
  let writes = 0;
  const versions = [9, 9, 10];
  await handleEvaluateProduct(
    { product_candidate_id: CANDIDATE_ID },
    USER,
    dependencies({
      readClosetStateVersion: () => Promise.resolve(versions[versionReads++] ?? 10),
      readUnlockCountCache: () => Promise.resolve(null),
      writeUnlockCountCache: () => {
        writes++;
        return Promise.resolve();
      },
      computeUnlockCount: () => ({ ...RESULT, unlockCount: 1 }),
    }),
  );
  assertEquals(versionReads, 3);
  assertEquals(writes, 0);
});

Deno.test("a cache miss stores computed data when the closet version remains stable", async () => {
  let writes = 0;
  let computations = 0;
  const result = await handleEvaluateProduct(
    { product_candidate_id: CANDIDATE_ID },
    USER,
    dependencies({
      readUnlockCountCache: () => Promise.resolve(null),
      writeUnlockCountCache: (row) => {
        writes++;
        assertEquals(row.user_id, USER);
        assertEquals(row.closet_state_version, 9);
        assertEquals(row.weights_version, 4);
        assertEquals(row.result.unlockCount, 1);
        return Promise.resolve();
      },
      computeUnlockCount: () => {
        computations++;
        return { ...RESULT, unlockCount: 1 };
      },
    }),
  );
  assertEquals(result.outfits_unlocked, 1);
  assertEquals(writes, 1);
  assertEquals(computations, 1);
});
