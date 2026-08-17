// ============================================================================
// products/ranking.ts
// ============================================================================
// P6-SHOP-09 / spec §17 ("Sponsored products must be labeled") and §11
// ("Separate sponsored placement from organic ranking") as ONE isolated,
// unit-tested function — the "distinct code path from organic ranking in
// P6-SHOP-04" the ticket asks for.
//
// THE GUARANTEE, AND HOW THE TYPE SYSTEM (NOT JUST A COMMENT) ENFORCES IT.
//
// `RankableCandidate.organicScore` is computed entirely upstream of this
// file, in `products/evaluation.ts`'s `computeCandidateCompatibility` —
// which never reads a `sponsored`/`affiliate_url` field at all; neither
// exists anywhere in that function's input type. So by the time a value
// reaches `rankProductCandidates` below, "how well does this product fit
// the wardrobe" has already been decided with no way for sponsorship to
// have touched it — this file's ONLY job is to sort by that already-final
// number and attach the `sponsored` label afterward, for display. Reading
// `sponsored` here to break a tie, weight the sort, or reorder anything
// would be the exact violation §11/§17 forbid, so it is never read for
// anything but pass-through — see `ranking_test.ts`'s guardrail test,
// which asserts a lower-scoring sponsored candidate never outranks a
// higher-scoring organic one.
//
// WHERE THIS IS CALLED FROM. `products/handler.ts`'s evaluate flow uses
// this to rank the small set of same-category alternatives it surfaces
// alongside the primary verdict (spec §5.5 step 3's "alternatives") — see
// that file for the real, load-bearing caller. This is not a
// speculative utility awaiting a future endpoint.
// ============================================================================

export interface RankableCandidate {
  readonly id: string;
  /** Computed with zero knowledge of `sponsored` — see this file's header. */
  readonly organicScore: number;
  readonly sponsored: boolean;
}

export interface RankedCandidate extends RankableCandidate {
  /** 1-based position after organic-only sorting. */
  readonly rank: number;
}

/**
 * Sorts strictly by `organicScore` descending. Ties keep their input
 * order (a stable sort) rather than being broken by `sponsored` in either
 * direction — an explicit choice, not an accident of the sort
 * implementation: breaking ties toward sponsored items would be exactly
 * the "sponsored availability changes ranking" failure §11 forbids, and
 * breaking them AWAY from sponsored items would be its mirror image (a
 * penalty for being sponsored, which is not what "separate" means either).
 * `Array.prototype.sort` in V8/Deno is a stable sort per the ECMAScript
 * spec, so this relies on documented platform behavior, not luck.
 */
export function rankProductCandidates(
  candidates: readonly RankableCandidate[],
): readonly RankedCandidate[] {
  return [...candidates]
    .sort((a, b) => b.organicScore - a.organicScore)
    .map((candidate, index) => ({ ...candidate, rank: index + 1 }));
}
