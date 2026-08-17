// ============================================================================
// products/evaluation.ts
// ============================================================================
// The pure compute core of `POST /products/evaluate` (P6-SHOP-04): every
// score on spec §6.19's product decision page, plus the Kyra verdict.
// No DB, no network, no clock — same rule every file under
// `_shared/scoring/` follows, and for the same reason: `handler.ts` is the
// only place that fetches, and this file is what `evaluation_test.ts`
// exercises with fixture closets, not a live Supabase project.
//
// SPONSORSHIP HAS NO PARAMETER HERE. THAT IS THE P6-SHOP-09 GUARANTEE.
//
// Search this file for the word "sponsor" and find nothing: `EvaluationInputs`
// has no `sponsored`/`affiliate_url` field, `computeVerdict` takes none, and
// `evaluateProductCandidate`'s signature has no way to receive one. Spec §11's
// "affiliate availability must not change Kyra's verdict" is not a rule this
// file remembers to follow — it is a rule this file's type signature makes
// impossible to violate by accident. `products/handler.ts` reads `sponsored`
// only AFTER calling this function, purely to attach it to the response as a
// label (see `products/ranking.ts`'s matching header for the corresponding
// guarantee on multi-candidate ranking).
//
// WHY COMPATIBILITY REUSES `generateAnchoredOutfits` AT `qualityThreshold: 0`
// RATHER THAN A NEW FORMULA. `unlockCount.ts` (P4-OUTFIT-09, reused verbatim
// below for `outfits_unlocked`) already anchors the candidate against the
// owned pool and scores every resulting combination — but it only exposes a
// COUNT of qualifying combinations, not a score to show as "wardrobe
// compatibility". Re-running the same anchored generation with the quality
// gate opened to 0 (so nothing is filtered before the max is taken) answers
// a different, complementary question — "how well does the BEST pairing
// score" — using the identical, already-tested `outfitGeneration.ts` engine
// rather than a second, drifting implementation of "how does a candidate
// pair with a wardrobe."
// ============================================================================

import { scoreOutfit } from "../_shared/scoring/compatibility.ts";
import {
  DEFAULT_GENERATION_OPTIONS,
  generateAnchoredOutfits,
} from "../_shared/scoring/outfitGeneration.ts";
import { computeUnlockCount, type UnlockCountContext } from "../_shared/scoring/unlockCount.ts";
import {
  DUPLICATE_SIMILARITY_THRESHOLD,
  type RedundancyItem,
  redundancyScore,
} from "../_shared/scoring/redundancy.ts";
import { expectedVersatility } from "../_shared/scoring/wardrobeScore.ts";
import type { ScorableItem, ScoringContext } from "../_shared/scoring/types.ts";
import { unitClamp } from "../_shared/scoring/types.ts";
import { projectedCostPerWear } from "./costPerWear.ts";

export type KyraVerdict = "buy" | "consider" | "wait_for_sale" | "skip";

/**
 * `lifestyle_profiles.dress_code` (`dress_code` enum,
 * `20260728100100_core_enums.sql`) mapped onto the same 0–100 formality
 * scale `_shared/scoring` already scores garments on — the same kind of
 * ladder `subscores/formality.ts`'s `CATEGORY_DEFAULT_FORMALITY` uses for
 * an unclassified garment, applied here to a lifestyle setting instead of
 * a category. Not in the spec verbatim (dress codes aren't numerically
 * scaled anywhere in `docs/00-master-spec.md`); this is the same kind of
 * defensible interpolation `docs/04-data-model.md`'s "ambiguities resolved"
 * section already documents for this exact enum.
 */
const DRESS_CODE_FORMALITY_CENTER: Record<string, number> = {
  ultra_casual: 15,
  casual: 30,
  athletic: 20,
  smart_casual: 45,
  business_casual: 55,
  business_formal: 70,
  formal: 85,
  black_tie: 90,
};

/** Same divisor `redundancy.ts`'s `formalityTerm` uses for a lifestyle-scale (not garment-pair-scale, see `formality.ts`'s ZEROING_GAP=40) comparison — a full 0–100 gap is "no fit at all", not "40 points is already zero" as it is between two garments in one outfit. */
const LIFESTYLE_FORMALITY_GAP_CEILING = 100;

export interface LifestyleInputs {
  readonly monthlyBudget: number | null;
  readonly dressCode: string | null;
}

/**
 * Everything the verdict needs that is not the candidate or the closet.
 *
 * Both fields are nullable because both genuinely are: §6.6's onboarding lets
 * a man answer "I don't know" to every measurement and skip lifestyle
 * entirely. A null here removes its term from the verdict rather than
 * substituting a population average — a budget fit computed against a budget
 * nobody stated is a number about nothing.
 */
export interface EvaluationInputs {
  readonly candidate: ScorableItem;
  readonly closet: readonly ScorableItem[];
  readonly candidatePrice: number | null;
  readonly redundancyCandidate: RedundancyItem;
  readonly redundancyCloset: readonly RedundancyItem[];
  readonly lifestyle: LifestyleInputs;
  readonly scoringContext?: ScoringContext;
  readonly occasion?: string;
}

export interface EvaluationResult {
  /** 0–100, the `user_product_evaluations.compatibility_score` column. */
  readonly compatibilityScore: number;
  /** 0–100. HIGH means "you already own this", which pushes toward skip. */
  readonly redundancyScore: number;
  readonly outfitsUnlocked: number;
  readonly expectedCostPerWear: number | null;
  readonly verdict: KyraVerdict;
  readonly reasoning: string;
  /**
   * The three §6.19 sub-fits, 0-1, each `null` when the input it needs is not
   * on file. Nullable rather than zero-filled: a budget fit of 0 says "this
   * blows your budget", and a man who never set a budget has not blown it.
   */
  readonly colorFit: number | null;
  readonly lifestyleFit: number | null;
  readonly budgetFit: number | null;
  /** Everything the verdict could not read, named. Surfaced, never hidden. */
  readonly degraded: readonly string[];
}

/**
 * How well the candidate pairs with what he already owns, 0–1.
 *
 * The BEST achievable pairing, not the mean. A jacket that goes with exactly
 * one pair of trousers he owns is still a jacket he can wear — averaging over
 * every combination would score it as though he had to wear it with all of
 * them at once, and would punish a large closet for containing variety.
 *
 * `qualityThreshold: 0` because the quality gate exists to COUNT things worth
 * wearing (that is `unlockCount`'s job, below); here it would filter away the
 * very combinations whose maximum we are about to take.
 */
function computeCandidateCompatibility(
  candidate: ScorableItem,
  closet: readonly ScorableItem[],
  scoringContext: ScoringContext | undefined,
): { readonly score: number; readonly pairable: boolean; readonly colorFit: number | null } {
  if (closet.length === 0) return { score: 0, pairable: false, colorFit: null };

  const generated = generateAnchoredOutfits(candidate, closet, {
    ...DEFAULT_GENERATION_OPTIONS,
    qualityThreshold: 0,
    ...(scoringContext !== undefined ? { context: scoringContext } : {}),
  });

  if (generated.qualifying.length > 0) {
    // `GeneratedOutfit.compatibilityScore` is 0-100 (it is `scoreOutfit`'s
    // rounded output); everything downstream of here is 0-1, so it is
    // normalised once, at the boundary, rather than at each read site.
    const bestOutfit = generated.qualifying.reduce((a, b) =>
      b.compatibilityScore > a.compatibilityScore ? b : a
    );
    // Re-scored once to read the colour component off the SAME combination
    // the headline number came from. Averaging colour across every generated
    // combination would report a colour fit for an outfit nobody is being
    // shown.
    const detail = scoreOutfit(bestOutfit.items, scoringContext ?? {});
    return {
      score: unitClamp(bestOutfit.compatibilityScore / 100),
      pairable: true,
      colorFit: detail.components.color?.value ?? null,
    };
  }

  // No complete outfit could be built — he may own no trousers at all. That is
  // a fact about the CLOSET, not about the candidate, so fall back to the best
  // pairwise score rather than reporting zero compatibility for a shirt that
  // goes perfectly with the one pair of shoes he owns.
  let bestPair = 0;
  let bestColor: number | null = null;
  for (const owned of closet) {
    if (owned.id === candidate.id) continue;
    const scored = scoreOutfit([candidate, owned], scoringContext ?? {});
    if (scored.score >= bestPair) {
      bestPair = scored.score;
      bestColor = scored.components.color?.value ?? null;
    }
  }
  return { score: unitClamp(bestPair / 100), pairable: false, colorFit: bestColor };
}

/**
 * How well the price sits against a stated monthly budget, 0–1.
 *
 * Not a hard gate. A man who says $200/month and finds a $220 coat has not
 * made a mistake, and a verdict that flips to `skip` at $201 would be
 * arithmetic pretending to be judgement. The term decays smoothly and reaches
 * zero at twice the budget, where the purchase genuinely is a different
 * decision from the one he planned.
 */
function computeBudgetFit(price: number | null, monthlyBudget: number | null): number | null {
  if (price === null || monthlyBudget === null || monthlyBudget <= 0) return null;
  if (price <= monthlyBudget) return 1;
  return unitClamp(1 - (price - monthlyBudget) / monthlyBudget);
}

/**
 * How well the garment's formality sits against how he actually dresses, 0–1.
 *
 * §7's recurring failure is the black-tie dinner jacket recommended to a man
 * who works from home. The gap is measured against the register his stated
 * dress code centres on, over the full 0–100 lifestyle scale rather than
 * `formality.ts`'s 40-point garment-pair scale — see the constant's note.
 */
function computeLifestyleFit(candidate: ScorableItem, dressCode: string | null): number | null {
  if (dressCode === null) return null;
  const centre = DRESS_CODE_FORMALITY_CENTER[dressCode];
  if (centre === undefined || candidate.formalityScore === null) return null;
  const gap = Math.abs(candidate.formalityScore - centre);
  return unitClamp(1 - gap / LIFESTYLE_FORMALITY_GAP_CEILING);
}

/** Where each verdict band begins. Ordered, and read in order below. */
const BUY_THRESHOLD = 0.68;
const CONSIDER_THRESHOLD = 0.5;

/**
 * §26's four-way verdict.
 *
 * `wait_for_sale` is NOT a weaker `buy` — it is the specific case where the
 * garment is right and only the price is wrong, which is the one situation
 * where "not yet" is better advice than either yes or no. It is therefore
 * checked before the score bands rather than derived from them: a piece that
 * would score `buy` but blows the budget is exactly what the case exists for,
 * and so is one that would score `consider`.
 *
 * A near-duplicate is `skip` regardless of how well it scores, because it
 * scores well FOR THE SAME REASON the thing he already owns did.
 */
function computeVerdict(
  compatibility: number,
  redundancy: number,
  budgetFit: number | null,
  lifestyleFit: number | null,
  unlockCount: number,
): { readonly verdict: KyraVerdict; readonly composite: number } {
  const terms: number[] = [compatibility, 1 - redundancy];
  if (lifestyleFit !== null) terms.push(lifestyleFit);
  // Unlocking nothing is not disqualifying — a replacement for a worn-out
  // staple unlocks little by construction — so this is one term among several.
  terms.push(unitClamp(unlockCount / 10));
  const composite = terms.reduce((a, b) => a + b, 0) / terms.length;

  if (redundancy >= DUPLICATE_SIMILARITY_THRESHOLD) {
    return { verdict: "skip", composite };
  }
  if (budgetFit !== null && budgetFit < 0.5 && composite >= CONSIDER_THRESHOLD) {
    return { verdict: "wait_for_sale", composite };
  }
  if (composite >= BUY_THRESHOLD) return { verdict: "buy", composite };
  if (composite >= CONSIDER_THRESHOLD) return { verdict: "consider", composite };
  return { verdict: "skip", composite };
}

/**
 * The sentence shown under the verdict.
 *
 * Assembled from the terms that actually decided it, in the order they
 * mattered — never a template with the verdict word swapped in. §11 forbids
 * fit-certainty claims from imagery, so nothing here says how it will fit;
 * every clause is about the wardrobe, the price, or the arithmetic.
 *
 * Kyra's real voice (P5-KYRA-02) does not write this. When it does, only this
 * function changes.
 */
function buildReasoning(
  verdict: KyraVerdict,
  compatibility: number,
  redundancy: number,
  unlockCount: number,
  costPerWear: number | null,
  budgetFit: number | null,
  lifestyleFit: number | null,
): string {
  const clauses: string[] = [];

  if (redundancy >= DUPLICATE_SIMILARITY_THRESHOLD) {
    clauses.push("you already own something very close to this");
  } else if (redundancy >= 0.6) {
    clauses.push("it overlaps with something already in your closet");
  }

  if (compatibility >= 0.7) {
    clauses.push("it works with a lot of what you own");
  } else if (compatibility >= 0.45) {
    clauses.push("it works with some of what you own");
  } else {
    clauses.push("it doesn't pair easily with what you own");
  }

  if (unlockCount > 0) {
    clauses.push(`it opens up ${unlockCount} new outfit${unlockCount === 1 ? "" : "s"}`);
  }
  if (lifestyleFit !== null && lifestyleFit < 0.5) {
    clauses.push("it's dressed differently from how you've said you dress");
  }
  if (budgetFit !== null && budgetFit < 0.5) {
    clauses.push("it's over the monthly budget you set");
  }
  if (costPerWear !== null) {
    clauses.push(
      `worn as often as most pieces in this category, it works out around $${
        costPerWear.toFixed(2)
      } a wear`,
    );
  }

  const lead: Record<KyraVerdict, string> = {
    buy: "Worth buying",
    consider: "Worth thinking about",
    wait_for_sale: "Right piece, wrong price",
    skip: "Skip this one",
  };
  return `${lead[verdict]} — ${clauses.join(", ")}.`;
}

/**
 * P6-SHOP-04's whole job, as one pure function.
 *
 * `outfits_unlocked` is `computeUnlockCount` verbatim — P4-OUTFIT-09's
 * algorithm, written and unit-tested months ago and, until this file, called
 * by nothing anywhere in the codebase.
 */
export function evaluateProductCandidate(inputs: EvaluationInputs): EvaluationResult {
  const degraded: string[] = [];

  const { score: compatibility, pairable, colorFit } = computeCandidateCompatibility(
    inputs.candidate,
    inputs.closet,
    inputs.scoringContext,
  );
  if (!pairable) {
    degraded.push(
      inputs.closet.length === 0
        ? "your closet (it's empty, so there was nothing to pair this against)"
        : "a complete outfit around this piece (you're missing a role it needs), so this is a best-pairing score",
    );
  }

  const redundancy = redundancyScore(inputs.redundancyCandidate, inputs.redundancyCloset);

  const unlock = computeUnlockCount(
    inputs.candidate,
    inputs.closet,
    {
      ...(inputs.scoringContext !== undefined ? { scoringContext: inputs.scoringContext } : {}),
      ...(inputs.occasion !== undefined ? { occasion: inputs.occasion } : {}),
    } satisfies UnlockCountContext,
  );

  const versatility = expectedVersatility(inputs.closet.length + 1);
  const costPerWear = projectedCostPerWear(
    inputs.candidatePrice,
    inputs.candidate.category,
    versatility,
  );
  degraded.push(...costPerWear.degraded);

  const budgetFit = computeBudgetFit(inputs.candidatePrice, inputs.lifestyle.monthlyBudget);
  if (budgetFit === null && inputs.lifestyle.monthlyBudget === null) {
    degraded.push("your monthly clothing budget (you haven't set one)");
  }

  const lifestyleFit = computeLifestyleFit(inputs.candidate, inputs.lifestyle.dressCode);
  if (lifestyleFit === null) {
    degraded.push("how formally you usually dress (no dress code on file)");
  }

  const { verdict } = computeVerdict(
    compatibility,
    redundancy,
    budgetFit,
    lifestyleFit,
    unlock.unlockCount,
  );

  return {
    // The two score columns are 0–100 integers, matching
    // `user_product_evaluations` and Swift's `ProductEvaluation`.
    compatibilityScore: Math.round(compatibility * 100),
    redundancyScore: Math.round(redundancy * 100),
    outfitsUnlocked: unlock.unlockCount,
    expectedCostPerWear: costPerWear.value,
    colorFit,
    lifestyleFit,
    budgetFit,
    verdict,
    reasoning: buildReasoning(
      verdict,
      compatibility,
      redundancy,
      unlock.unlockCount,
      costPerWear.value,
      budgetFit,
      lifestyleFit,
    ),
    degraded,
  };
}
