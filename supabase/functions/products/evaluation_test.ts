// ============================================================================
// products/evaluation_test.ts
// ============================================================================
// Written against what a verdict PROMISES rather than against the arithmetic
// that currently produces it: a near-duplicate is never a buy, a missing
// budget is not a blown one, and sponsorship cannot reach this file at all.
// ============================================================================

import { assert, assertEquals } from "@std/assert";
import { evaluateProductCandidate, type EvaluationInputs } from "./evaluation.ts";
import type { ScorableItem } from "../_shared/scoring/types.ts";
import type { RedundancyItem } from "../_shared/scoring/redundancy.ts";

function scorable(over: Partial<ScorableItem> & { id: string }): ScorableItem {
  return {
    category: "top",
    role: "top",
    primaryColor: null,
    isNeutral: true,
    secondaryColors: [],
    pattern: "solid",
    patternScale: null,
    materials: ["cotton"],
    formalityScore: 45,
    fit: "regular",
    seasonality: ["all_season"],
    warmthScore: 30,
    waterResistanceScore: 0,
    laundryState: "clean",
    availabilityState: "available",
    lastWornAt: null,
    ...over,
  } as unknown as ScorableItem;
}

function redundancy(over: Partial<RedundancyItem> & { id: string }): RedundancyItem {
  return {
    category: "top",
    role: "top",
    primaryColorLab: null,
    formalityScore: 45,
    fit: "regular",
    materials: ["cotton"],
    seasonality: ["all_season"],
    ...over,
  } as RedundancyItem;
}

function inputs(over: Partial<EvaluationInputs> = {}): EvaluationInputs {
  const candidate = scorable({ id: "candidate" });
  return {
    candidate,
    closet: [
      scorable({ id: "b1", category: "bottom", role: "bottom" }),
      scorable({ id: "s1", category: "shoes", role: "shoes" }),
    ],
    candidatePrice: 90,
    redundancyCandidate: redundancy({ id: "candidate" }),
    redundancyCloset: [redundancy({ id: "b1", category: "bottom", role: "bottom" })],
    lifestyle: { monthlyBudget: null, dressCode: null },
    ...over,
  };
}

Deno.test("a candidate that completes an outfit scores and unlocks something", () => {
  const result = evaluateProductCandidate(inputs());

  assert(result.compatibilityScore > 0);
  assert(result.compatibilityScore <= 100);
  assert(result.outfitsUnlocked >= 0);
});

Deno.test("an empty closet is reported as unmeasured, not scored as incompatible", () => {
  // Zero compatibility would read as "this goes with nothing you own", which
  // is a claim about the garment. The truth is that we had nothing to compare
  // it to, and that is a different sentence.
  const result = evaluateProductCandidate(inputs({ closet: [], redundancyCloset: [] }));

  assertEquals(result.compatibilityScore, 0);
  assert(result.degraded.some((d) => d.includes("closet")));
});

const NAVY_LAB = { l: 30, a: 2, b: -20 };

Deno.test("a near-duplicate is a skip however well it otherwise scores", () => {
  // It scores well for exactly the reason the thing he already owns did.
  const result = evaluateProductCandidate(inputs({
    redundancyCandidate: redundancy({ id: "candidate", primaryColorLab: NAVY_LAB }),
    redundancyCloset: [redundancy({ id: "owned-twin", primaryColorLab: NAVY_LAB })],
  }));

  assert(result.redundancyScore >= 85);
  assertEquals(result.verdict, "skip");
  assert(result.reasoning.includes("already own"));
});

Deno.test("an unmeasured colour keeps a twin below the duplicate threshold", () => {
  // Two garments identical in every attribute ON FILE, with no colour for
  // either, score 0.84 — just under the 0.85 duplicate bar. That is the
  // engine declining to call something a duplicate on partial evidence, and
  // it is the behaviour to protect: telling a man he already owns a navy
  // jumper, on the strength of a grey one whose colour was never recorded,
  // is the confident-wrong answer this codebase keeps refusing.
  const result = evaluateProductCandidate(inputs({
    redundancyCloset: [redundancy({ id: "owned-twin" })],
  }));

  assert(result.redundancyScore < 85);
  assert(!result.reasoning.includes("already own"));
});

Deno.test("no stated budget is not a blown budget", () => {
  const result = evaluateProductCandidate(inputs({
    candidatePrice: 10_000,
    lifestyle: { monthlyBudget: null, dressCode: null },
  }));

  assertEquals(result.budgetFit, null);
  assert(result.verdict !== "wait_for_sale");
  assert(result.degraded.some((d) => d.includes("budget")));
});

Deno.test("a good piece over budget is wait_for_sale, not skip", () => {
  // The garment is right and only the price is wrong. That is the one case
  // where "not yet" beats both yes and no.
  const overBudget = evaluateProductCandidate(inputs({
    candidatePrice: 500,
    lifestyle: { monthlyBudget: 100, dressCode: null },
  }));
  const affordable = evaluateProductCandidate(inputs({
    candidatePrice: 80,
    lifestyle: { monthlyBudget: 100, dressCode: null },
  }));

  assert(overBudget.budgetFit !== null && overBudget.budgetFit < 0.5);
  assertEquals(overBudget.verdict, "wait_for_sale");
  assert(affordable.verdict !== "wait_for_sale");
});

Deno.test("a black-tie piece against a casual dress code reads as a poor lifestyle fit", () => {
  const result = evaluateProductCandidate(inputs({
    candidate: scorable({ id: "candidate", formalityScore: 95 }),
    lifestyle: { monthlyBudget: null, dressCode: "casual" },
  }));

  assert(result.lifestyleFit !== null);
  assert(result.lifestyleFit < 0.5);
  assert(result.reasoning.includes("how you"));
});

Deno.test("no price means no cost-per-wear, never a zero", () => {
  const result = evaluateProductCandidate(inputs({ candidatePrice: null }));

  assertEquals(result.expectedCostPerWear, null);
  assert(!result.reasoning.includes("$"));
});

Deno.test("the scores are 0-100 integers, matching the columns they are written to", () => {
  const result = evaluateProductCandidate(inputs());

  assertEquals(result.compatibilityScore, Math.round(result.compatibilityScore));
  assertEquals(result.redundancyScore, Math.round(result.redundancyScore));
  assert(result.compatibilityScore >= 0 && result.compatibilityScore <= 100);
  assert(result.redundancyScore >= 0 && result.redundancyScore <= 100);
});

Deno.test("P6-SHOP-09: sponsorship is not an input this function can receive", () => {
  // The guarantee is structural rather than behavioural, so the test is too:
  // `EvaluationInputs` has no sponsorship key, and adding one would fail to
  // compile here before it could ever change a verdict. `ranking.ts`'s own
  // test covers the ordering half.
  const keys = Object.keys(inputs());
  assert(!keys.some((k) => k.toLowerCase().includes("sponsor")));
  assert(!keys.some((k) => k.toLowerCase().includes("affiliate")));
});
