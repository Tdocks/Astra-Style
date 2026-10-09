import { assert, assertEquals, assertNotEquals } from "@std/assert";
import { resolveColorName } from "./colorVocabulary.ts";
import { computeUnlockCount } from "./unlockCount.ts";
import type { ScorableItem, ScoringContext } from "./types.ts";
import {
  asHypotheticalOwnership,
  isUnlockCountResult,
  unlockCountCacheKey,
} from "./unlockCountCache.ts";

const navy = resolveColorName("navy");
if (navy === null) throw new Error("expected navy color fixture");
const CANDIDATE: ScorableItem = {
  id: "candidate-a",
  category: "top",
  role: "top",
  primaryColor: navy.lch,
  isNeutral: navy.isNeutral,
  secondaryColors: [],
  pattern: "solid",
  patternScale: null,
  materials: ["cotton"],
  formalityScore: 40,
  fit: "regular",
  seasonality: ["fall"],
  warmthScore: 50,
  waterResistanceScore: 10,
  laundryState: "clean",
  availabilityState: "available",
};

function key(over: Partial<Parameters<typeof unlockCountCacheKey>[0]> = {}) {
  return unlockCountCacheKey({
    userId: "caller-id",
    candidate: CANDIDATE,
    closetStateVersion: 2,
    compatibilityWeightsVersion: 3,
    ...over,
  });
}

Deno.test("cache keys are stable SHA-256 values and include caller, candidate, graph, and all context", async () => {
  const base = await key();
  assertEquals(await key(), base);
  assertEquals(base.length, 64);
  assert(/^[0-9a-f]{64}$/.test(base));
  assertNotEquals(await key({ userId: "peer-id" }), base);
  assertNotEquals(await key({ closetStateVersion: 3 }), base);
  assertNotEquals(await key({ compatibilityWeightsVersion: 4 }), base);
  assertNotEquals(await key({ candidate: { ...CANDIDATE, secondaryColors: [navy.lch] } }), base);
  assertNotEquals(await key({ scoringContext: { wardrobeGraph: "womenswear" } }), base);
  assertNotEquals(await key({ scoringContext: { targetFormalityScore: 75 } }), base);
});

Deno.test("map context canonicalization ignores insertion order", async () => {
  const first: ScoringContext = {
    coWear: new Map([
      ["a|b", { positiveCoWears: 4, totalCoWears: 6 }],
      ["c|d", { positiveCoWears: 1, totalCoWears: 3 }],
    ]),
  };
  const reversed: ScoringContext = {
    coWear: new Map([
      ["c|d", { totalCoWears: 3, positiveCoWears: 1 }],
      ["a|b", { totalCoWears: 6, positiveCoWears: 4 }],
    ]),
  };
  assertEquals(await key({ scoringContext: first }), await key({ scoringContext: reversed }));
});

Deno.test("hypothetical candidate wear state does not change key identity", async () => {
  const laundryChange = {
    ...CANDIDATE,
    laundryState: "laundry" as const,
    availabilityState: "lost" as const,
  };
  assertEquals(await key({ candidate: laundryChange }), await key());
});

Deno.test("hypothetical scoring normalizes owned wearability before computing", () => {
  const bottom: ScorableItem = {
    ...CANDIDATE,
    id: "owned-bottom",
    category: "bottom",
    role: "bottom",
    laundryState: "clean",
    availabilityState: "available",
  };
  const shoes: ScorableItem = {
    ...CANDIDATE,
    id: "owned-shoes",
    category: "shoes",
    role: "shoes",
    laundryState: "clean",
    availabilityState: "available",
  };
  const dirty = { ...bottom, laundryState: "laundry" as const, availabilityState: "lost" as const };
  const available = computeUnlockCount(CANDIDATE, [bottom, shoes]);
  const hypothetical = computeUnlockCount(CANDIDATE, [asHypotheticalOwnership(dirty), shoes]);
  assertEquals(hypothetical, available);
});

Deno.test("malformed or unbounded cache rows fail validation and become misses", () => {
  assertEquals(isUnlockCountResult({ ...RESULT_FIXTURE, unlockCount: -1 }), false);
  assertEquals(isUnlockCountResult({ ...RESULT_FIXTURE, unlockCount: 1.5 }), false);
  assertEquals(isUnlockCountResult({ ...RESULT_FIXTURE, gapsFilled: [{ occasion: "x" }] }), false);
  assertEquals(isUnlockCountResult({ ...RESULT_FIXTURE, degraded: [4] }), false);
  assertEquals(
    isUnlockCountResult({
      ...RESULT_FIXTURE,
      gapsFilled: Array(12).fill(RESULT_FIXTURE.gapsFilled[0]),
    }),
    false,
  );
});

const RESULT_FIXTURE = {
  unlockCount: 1,
  novel: true,
  gapsFilled: [{
    occasion: "unconstrained",
    formalityBucket: 5,
    qualifyingBefore: 0,
    qualifyingAfter: 1,
    fillsGap: true,
  }],
  combinationsScored: 3,
  degraded: [],
};
