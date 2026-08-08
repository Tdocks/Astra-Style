/**
 * §6.2 — candidate-anchored pruned outfit generation.
 *
 * One anchor item is fixed into its role slot; every other slot is pruned to
 * its top-K pairwise-compatible candidates against the anchor BEFORE the
 * cross product is built, which is what keeps this `O(K^slots)` instead of
 * `O(∏|slot_i|)` (§6.1). Two callers share this file rather than each
 * building their own enumeration:
 *
 *   `unlockCount.ts`   — anchors on a candidate PRODUCT the user does not own.
 *   `wardrobeScore.ts` — anchors on each OWNED item in turn, to count §5.1's
 *                        itemVersatility_i ("how many outfits can this item
 *                        join"), reusing §6.3's dedup rule the doc itself
 *                        points §5.1 at.
 *
 * Both questions are "how many distinct, qualifying outfits include this one
 * fixed item," which is exactly what this module answers; only the anchor and
 * the pool it draws the rest of the outfit from differ between the two.
 */

import { scoreOutfit } from "./compatibility.ts";
import type { ComponentWeights, ScoreOptions } from "./compatibility.ts";
import { canonicalSignature } from "./equivalence.ts";
import type { GarmentRole, ScorableItem, ScoringContext } from "./types.ts";

const REQUIRED_ROLES: readonly GarmentRole[] = ["top", "bottom", "shoes"];

export interface PrunedGenerationOptions {
  /** §6.4's quality gate, on the same [0,1] scale as every other subscore. */
  readonly qualityThreshold: number;
  /** §6.2's K: how many top pairwise-compatible candidates survive per required/outerwear slot. */
  readonly slotK: number;
  readonly outerwearK: number;
  /** §6.2's second, tighter prune for the 5%-weighted accessory role. */
  readonly accessoryTopK: number;
  /** §6.2: 1 for the product decision page, 2 reserved for the interactive builder (not built here). */
  readonly accessorySlots: number;
  readonly weights?: ComponentWeights;
  readonly context?: ScoringContext;
  readonly scoreOptions?: Omit<ScoreOptions, "weights">;
}

/** §6.2's own worked numbers: K=10, accessory top-4, 1 accessory slot, 0.65 threshold (§5.1/§6.4). */
export const DEFAULT_GENERATION_OPTIONS: PrunedGenerationOptions = {
  qualityThreshold: 0.65,
  slotK: 10,
  outerwearK: 10,
  accessoryTopK: 4,
  accessorySlots: 1,
};

export interface GeneratedOutfit {
  readonly items: readonly ScorableItem[];
  readonly compatibilityScore: number;
  readonly signature: string;
}

export interface GenerationResult {
  /** Deduplicated (best-scoring representative per §6.3 signature), quality-filtered. */
  readonly qualifying: readonly GeneratedOutfit[];
  /** Every combination actually scored, pre-threshold/dedup — compute-budget telemetry (§6.6). */
  readonly combinationsScored: number;
}

function pairwiseScore(
  anchor: ScorableItem,
  other: ScorableItem,
  weights: ComponentWeights | undefined,
  context: ScoringContext,
): number {
  return scoreOutfit([anchor, other], context, { weights }).score;
}

/**
 * §6.2 step 2–3: rank a role's eligible items by pairwise compatibility with
 * the anchor, keep the top `k`.
 *
 * The anchor itself is excluded even if it happens to share the target role
 * with a pool item of the same id — a caller building the "before" pool for
 * §6.4's novelty check passes the anchor's own role's other owned items, and
 * the anchor must never rank against itself.
 */
function topKForRole(
  anchor: ScorableItem,
  pool: readonly ScorableItem[],
  role: GarmentRole,
  k: number,
  weights: ComponentWeights | undefined,
  context: ScoringContext,
): readonly ScorableItem[] {
  const eligible = pool.filter((item) => item.role === role && item.id !== anchor.id);
  return eligible
    .map((item) => ({ item, score: pairwiseScore(anchor, item, weights, context) }))
    .sort((a, b) => b.score - a.score)
    .slice(0, k)
    .map((r) => r.item);
}

/** Every subset of `items` with size 0..maxSize, including the empty subset (no accessory chosen). */
function subsetsUpTo<T>(items: readonly T[], maxSize: number): readonly T[][] {
  const result: T[][] = [[]];
  const build = (start: number, chosen: readonly T[]) => {
    for (let i = start; i < items.length; i++) {
      const next = [...chosen, items[i]!];
      result.push(next);
      if (next.length < maxSize) build(i + 1, next);
    }
  };
  build(0, []);
  return result;
}

function cartesian(lists: readonly (readonly ScorableItem[])[]): readonly ScorableItem[][] {
  let result: ScorableItem[][] = [[]];
  for (const list of lists) {
    const next: ScorableItem[][] = [];
    for (const partial of result) {
      for (const item of list) next.push([...partial, item]);
    }
    result = next;
  }
  return result;
}

/**
 * §6.2's full pipeline: fix `anchor`, prune every other slot against it, and
 * score+dedup+threshold the cross product per §6.3/§6.4.
 *
 * `pool` must already be wearability-filtered (or deliberately not — see
 * `wardrobeScore.ts`'s note on why its versatility scan does NOT apply §2.9's
 * hard filter) by the caller; this function does not re-derive that policy.
 */
export function generateAnchoredOutfits(
  anchor: ScorableItem,
  pool: readonly ScorableItem[],
  options: Partial<PrunedGenerationOptions> = {},
): GenerationResult {
  const opts: PrunedGenerationOptions = { ...DEFAULT_GENERATION_OPTIONS, ...options };
  const context = opts.context ?? {};

  const requiredRolesToFill = REQUIRED_ROLES.filter((r) => r !== anchor.role);
  const fillOuterwear = anchor.role !== "outerwear";
  const fillAccessory = anchor.role !== "accessory";

  const requiredCandidateLists: (readonly ScorableItem[])[] = [];
  for (const role of requiredRolesToFill) {
    const candidates = topKForRole(anchor, pool, role, opts.slotK, opts.weights, context);
    if (candidates.length === 0) {
      // A required role with zero eligible items means no outfit can be
      // built at all, regardless of what else the wardrobe holds — e.g. a
      // top being scored for versatility in a closet with no shoes.
      return { qualifying: [], combinationsScored: 0 };
    }
    requiredCandidateLists.push(candidates);
  }

  const outerwearCandidates = fillOuterwear
    ? topKForRole(anchor, pool, "outerwear", opts.outerwearK, opts.weights, context)
    : [];
  const outerwearOptions: readonly (ScorableItem | null)[] = [null, ...outerwearCandidates];

  const accessoryCandidates = fillAccessory
    ? topKForRole(anchor, pool, "accessory", opts.accessoryTopK, opts.weights, context)
    : [];
  const accessorySubsets = subsetsUpTo(accessoryCandidates, opts.accessorySlots);

  const requiredCombos = cartesian(requiredCandidateLists);

  const bySignature = new Map<string, GeneratedOutfit>();
  let combinationsScored = 0;

  for (const required of requiredCombos) {
    for (const outerwear of outerwearOptions) {
      for (const accessories of accessorySubsets) {
        const items = [anchor, ...required, ...(outerwear ? [outerwear] : []), ...accessories];
        combinationsScored++;
        const compatibilityScore = scoreOutfit(items, context, {
          weights: opts.weights,
          ...opts.scoreOptions,
        }).score;
        if (compatibilityScore / 100 < opts.qualityThreshold) continue;

        const signature = canonicalSignature(items);
        const existing = bySignature.get(signature);
        if (!existing || compatibilityScore > existing.compatibilityScore) {
          bySignature.set(signature, { items, compatibilityScore, signature });
        }
      }
    }
  }

  return { qualifying: [...bySignature.values()], combinationsScored };
}
