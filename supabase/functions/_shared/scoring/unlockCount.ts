/**
 * §6 — purchase-unlock count: how many NEW, distinct outfits a candidate
 * product would add to a wardrobe. `P4-OUTFIT-09`.
 *
 * §6.2's pruned generation and §6.3's dedup are `outfitGeneration.ts`, shared
 * with `wardrobeScore.ts`. This file adds what is specific to a purchase
 * decision: §6.4's novelty check (does an owned item already cover this),
 * gap-filling, and the complete result consumed by §6.5's cache layer.
 *
 * ─────────────────────────────────────────────────────────────────────────
 * WHAT THIS FILE DOES NOT DO, AND WHY THAT IS THE ENDPOINT'S JOB.
 *
 * §6.5's persistent storage and SHA-256 identity live in `unlockCountCache.ts`
 * and the authenticated endpoint. This module remains the deterministic scorer.
 *
 * §6.6's 500ms/800ms compute budget is a wall-clock concern, and this
 * package's rule is no clock (`types.ts`'s header; `wardrobeScore.ts` takes
 * `today` as a parameter for the same reason). `computeUnlockCount` reports
 * `combinationsScored` so the endpoint can log or alert on an unexpectedly
 * large run, but it does not time or abort itself — the endpoint wraps the
 * call in its own timeout and is the only place that can honestly know how
 * long anything took.
 * ─────────────────────────────────────────────────────────────────────────
 */

import type { ComponentWeights } from "./compatibility.ts";
import { equivalenceClass } from "./equivalence.ts";
import {
  DEFAULT_GENERATION_OPTIONS,
  generateAnchoredOutfits,
  type PrunedGenerationOptions,
} from "./outfitGeneration.ts";
import { outfitFormality } from "./subscores/formality.ts";
import type { ScorableItem, ScoringContext } from "./types.ts";

export interface UnlockCountContext {
  readonly scoringContext?: ScoringContext;
  readonly weights?: ComponentWeights;
  readonly generationOptions?: Partial<PrunedGenerationOptions>;
  /**
   * Which occasion this evaluation is asked about, for gap-filling's
   * `(occasion_tag, formalityBucket)` key. `closet_items` has no
   * `occasion_tags` column at all (`types.ts`, note 4) — only `outfits`
   * does — so there is no per-item axis to bucket generated combinations by
   * occasion. Every combination generated here is therefore bucketed under
   * this single caller-supplied label (or `"unconstrained"`), not against
   * the full set the doc's §6.4 wording implies. See this file's report note.
   */
  readonly occasion?: string;
  /**
   * Bound on how many owned same-role items are unioned into the §6.4 "before"
   * gap-analysis scan. §6.6's budget is written for evaluating ONE candidate;
   * scanning every owned item in that role to answer "how many qualifying
   * combinations already exist without the candidate" would multiply that
   * cost by however many of that role the user owns. 10 mirrors §6.2's own
   * per-slot K, on the same reasoning: bound the fan-out, not the answer's
   * shape.
   */
  readonly gapAnalysisSampleLimit?: number;
}

const DEFAULT_GAP_SAMPLE_LIMIT = 10;

export interface GapFillFlag {
  readonly occasion: string;
  readonly formalityBucket: number;
  readonly qualifyingBefore: number;
  readonly qualifyingAfter: number;
  readonly fillsGap: boolean;
}

export interface UnlockCountResult {
  /** §6.3-deduplicated, §6.4-quality-and-novelty-filtered count of outfits this candidate makes possible. */
  readonly unlockCount: number;
  /**
   * §6.4's novelty check: is there already an owned item in the candidate's
   * role and equivalence class? If so every combination the candidate could
   * anchor has a same-signature combination already achievable without it,
   * per the doc's own definition of novelty — see `hasOwnedSubstitute`.
   */
  readonly novel: boolean;
  /** One entry per distinct formality register reached among the candidate's qualifying combinations. */
  readonly gapsFilled: readonly GapFillFlag[];
  /** Every combination actually scored before threshold/dedup — §6.6 budget telemetry, not a result to display. */
  readonly combinationsScored: number;
  readonly degraded: readonly string[];
}

/**
 * §6.4's novelty check, read literally: "no already-owned substitute in the
 * candidate's equivalence class exists that would produce the same
 * signature." Equivalence class only depends on (category, colour cluster,
 * formality bucket, fit) — not on the rest of any particular combination —
 * so this is a property of the CANDIDATE against the pool, checked once,
 * rather than re-derived per generated combination. If a substitute exists,
 * swapping it into any candidate-anchored combination reproduces that
 * combination's exact signature, so nothing the candidate anchors is novel.
 */
function hasOwnedSubstitute(candidate: ScorableItem, pool: readonly ScorableItem[]): boolean {
  const candidateClass = equivalenceClass(candidate);
  return pool.some((item) => {
    if (item.role !== candidate.role) return false;
    const itemClass = equivalenceClass(item);
    return itemClass.category === candidateClass.category &&
      itemClass.colorCluster === candidateClass.colorCluster &&
      itemClass.formalityBucket === candidateClass.formalityBucket &&
      itemClass.fit === candidateClass.fit;
  });
}

function bucketOfOutfit(items: readonly ScorableItem[]): number {
  const register = outfitFormality(items);
  // outfitFormality returns null only for zero scoreable items, which cannot
  // happen for a generated combination (every combination fills the required
  // roles) — the fallback bucket exists only so this stays total.
  return Math.floor((register ?? 50) / 10);
}

/**
 * §6.4's "before" count for one formality bucket: qualifying combinations the
 * wardrobe can already build using something in the candidate's OWN role,
 * without the candidate. There is no natural single anchor for "the whole
 * wardrobe minus the candidate," so this unions the candidate-role's owned
 * items (bounded to `sampleLimit`, most-recently-considered order is
 * irrelevant — see the field's own comment) each anchored in turn, which
 * answers exactly the question gap-filling asks: was this formality register
 * already reachable through this role.
 */
function qualifyingBeforeInBucket(
  candidate: ScorableItem,
  pool: readonly ScorableItem[],
  bucket: number,
  options: Partial<PrunedGenerationOptions>,
  sampleLimit: number,
): number {
  const sameRoleOwned = pool.filter((item) => item.role === candidate.role).slice(0, sampleLimit);
  const signatures = new Set<string>();
  for (const standIn of sameRoleOwned) {
    const rest = pool.filter((item) => item.id !== standIn.id);
    const generated = generateAnchoredOutfits(standIn, rest, options);
    for (const combo of generated.qualifying) {
      if (bucketOfOutfit(combo.items) === bucket) signatures.add(combo.signature);
    }
  }
  return signatures.size;
}

/**
 * §6's full pipeline for one candidate against one wardrobe.
 *
 * `candidate` is NOT included in `pool` — it is the item being evaluated for
 * purchase, so by definition it is not yet owned. `pool` should be every
 * wearable-or-not owned item (see `wardrobeScore.ts`'s note on why this
 * package does not apply §2.9's hard filter to a hypothetical-ownership
 * question; the same reasoning applies here — §6.5 explicitly says laundry
 * state must not invalidate an unlock-count cache, which only makes sense if
 * laundry state was never part of the computation).
 */
export function computeUnlockCount(
  candidate: ScorableItem,
  pool: readonly ScorableItem[],
  context: UnlockCountContext = {},
): UnlockCountResult {
  const generationOptions: Partial<PrunedGenerationOptions> = {
    ...DEFAULT_GENERATION_OPTIONS,
    ...context.generationOptions,
    ...(context.weights !== undefined ? { weights: context.weights } : {}),
    ...(context.scoringContext !== undefined ? { context: context.scoringContext } : {}),
  };

  const generated = generateAnchoredOutfits(candidate, pool, generationOptions);
  const novel = !hasOwnedSubstitute(candidate, pool);

  const degraded: string[] = [];
  if (context.occasion === undefined) {
    degraded.push(
      "occasion tags for these combinations (closet_items has no occasion_tags column; " +
        'gap-filling is scored against a single caller-supplied occasion, or "unconstrained" if none was given)',
    );
  }
  const occasionLabel = context.occasion ?? "unconstrained";

  if (!novel) {
    // §6.4: an owned item already covers this equivalence class, so nothing
    // the candidate anchors is net-new — see `hasOwnedSubstitute`'s comment.
    return {
      unlockCount: 0,
      novel: false,
      gapsFilled: [],
      combinationsScored: generated.combinationsScored,
      degraded,
    };
  }

  const buckets = new Set(generated.qualifying.map((combo) => bucketOfOutfit(combo.items)));
  const sampleLimit = context.gapAnalysisSampleLimit ?? DEFAULT_GAP_SAMPLE_LIMIT;

  const gapsFilled: GapFillFlag[] = [];
  for (const bucket of buckets) {
    const before = qualifyingBeforeInBucket(
      candidate,
      pool,
      bucket,
      generationOptions,
      sampleLimit,
    );
    const afterCount = before +
      generated.qualifying.filter((combo) => bucketOfOutfit(combo.items) === bucket).length;
    gapsFilled.push({
      occasion: occasionLabel,
      formalityBucket: bucket,
      qualifyingBefore: before,
      qualifyingAfter: afterCount,
      fillsGap: before < 2 && afterCount >= 2,
    });
  }

  return {
    unlockCount: generated.qualifying.length,
    novel: true,
    gapsFilled,
    combinationsScored: generated.combinationsScored,
    degraded,
  };
}

// ── §6.5 cache key ──────────────────────────────────────────────────────────
