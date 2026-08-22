// ============================================================================
// outfits/candidateGeneration.ts
// ============================================================================
// Turns a user's closet into a ranked, deduplicated list of full outfits —
// the part of `P4-OUTFIT-07` that `docs/05-wardrobe-graph.md` §6.1 warns
// cannot be a naive cross-product: `|tops| x |bottoms| x |shoes| x ...` blows
// past a million combinations for a closet well within an active user's
// reach, and every one of those would need a `scoreOutfit` call.
//
// §6.2's own pruning ("candidate-anchored pruned generation") is written
// for the purchase-unlock-count use case, where there IS an anchor: the
// product being considered is fixed into its slot before anything else is
// pruned. `/outfits/generate` has no such anchor — every slot is free
// unless the caller locked an item into it — so the technique here is beam
// search instead: build outfits one role at a time, score every partial
// after each role is added, and keep only the best `BEAM_WIDTH` partials
// before extending to the next role. This is the same underlying idea §6.2
// names ("prune before the next cross-product multiplies it"), adapted to a
// generation problem that has no single fixed candidate to prune around.
// Complexity is `O(BEAM_WIDTH x max(|role_i|))` per role — linear in closet
// size, not exponential in slot count — which is what keeps this fast for a
// 50+ item closet without ever materialising the full cross-product.
//
// Near-duplicate collapsing follows §6.3 exactly: an outfit's canonical
// signature is the sorted tuple of each item's `(role, colour bucket,
// formality bucket, fit)`, and two outfits sharing a signature count as one.
// Unlike §6.3's use of that signature for a cached, potentially-large
// unlock count, the candidate set here is at most a few dozen full outfits
// held in memory for one request, so plain string equality replaces the
// doc's SHA-1-truncated hash — hashing exists there to keep a cache key
// small, which is not a problem this function has.
// ============================================================================

import {
  type CompatibilityScore,
  type ComponentWeights,
  type ScoreOptions,
  scoreOutfit,
  wearableItems,
} from "../_shared/scoring/compatibility.ts";
import type { GarmentRole, ScorableItem, ScoringContext } from "../_shared/scoring/types.ts";
import { canonicalSignature } from "../_shared/scoring/equivalence.ts";
import { buildReason } from "./reason.ts";

export interface GenerateCandidateOutfitsOptions {
  readonly desiredCount: number;
  readonly lockedItemIds: ReadonlySet<string>;
  readonly excludedItemIds: ReadonlySet<string>;
  readonly context?: ScoringContext;
  readonly weights?: ComponentWeights;
  /**
   * Clock for freshness rotation. Production omits this and uses now;
   * tests freeze it so "worn an hour ago" is a fact, not a race.
   */
  readonly now?: Date;
}

export interface GeneratedOutfit {
  readonly items: readonly ScorableItem[];
  readonly score: CompatibilityScore;
  readonly reason: string;
}

const REQUIRED_ROLES: readonly GarmentRole[] = ["top", "bottom", "shoes"];
const ROLE_DISPLAY_ORDER: readonly GarmentRole[] = [
  "top",
  "bottom",
  "shoes",
  "outerwear",
  "accessory",
];

/** How many partial outfits survive each ply. Larger finds more of the true top-N; smaller is faster. */
const BEAM_WIDTH = 8;

/**
 * Section 6.2's own accessory prune ("cap accessories to top 4 candidates
 * ... reserving 2-accessory enumeration for the interactive outfit
 * builder"), reused here for the same reason: accessories are 5% of the
 * compatibility weight (`roleWeights.ts`) and rarely decide whether a
 * combination is viable, so spending beam width on many accessory
 * candidates buys little.
 */
const ACCESSORY_POOL_CAP = 4;
const MAX_ACCESSORIES_PER_OUTFIT = 2;

/**
 * How long a wear keeps a garment out of the next look, when he owns
 * another in the same role.
 *
 * Twenty-four hours, not a calendar date: Wear This at 8am must not return
 * the same shirt at 7am tomorrow, and may return it the morning after. The
 * 0.05 availability weight cannot beat colour, so this is a hard drop of
 * recently-worn candidates — not a scoring nudge. If dropping them would
 * empty a role, they stay: the only look is still a look.
 */
const ROTATION_WINDOW_MS = 24 * 60 * 60 * 1000;

function wornWithinWindow(item: ScorableItem, now: Date): boolean {
  const worn = item.lastWornAt;
  if (worn == null) return false;
  return now.getTime() - worn.getTime() < ROTATION_WINDOW_MS;
}

/**
 * When a role has more than one wearable item, drop the ones worn inside
 * `ROTATION_WINDOW_MS` — unless that would leave the role empty, or the
 * item is locked (he asked for it).
 */
function applyFreshnessRotation(
  byRole: Map<GarmentRole, ScorableItem[]>,
  lockedItemIds: ReadonlySet<string>,
  now: Date,
): void {
  for (const [role, items] of byRole) {
    if (items.length <= 1) continue;
    const fresh = items.filter((item) =>
      lockedItemIds.has(item.id) || !wornWithinWindow(item, now)
    );
    if (fresh.length > 0) byRole.set(role, fresh);
  }
}

interface PartialCombo {
  readonly items: readonly ScorableItem[];
  readonly score: CompatibilityScore;
}

function tiebreakKey(items: readonly ScorableItem[]): string {
  return [...items.map((i) => i.id)].sort().join(",");
}

/** Deterministic regardless of engine: highest score first, then a stable id-based key. */
function prune(expanded: readonly PartialCombo[], beamWidth: number): PartialCombo[] {
  return [...expanded]
    .sort((a, b) => {
      if (b.score.score !== a.score.score) return b.score.score - a.score.score;
      const ak = tiebreakKey(a.items);
      const bk = tiebreakKey(b.items);
      return ak < bk ? -1 : ak > bk ? 1 : 0;
    })
    .slice(0, beamWidth);
}

/** One ply for a REQUIRED role: every partial x every candidate, no "skip" branch. */
function extendRequired(
  beam: readonly PartialCombo[],
  candidates: readonly ScorableItem[],
  context: ScoringContext,
  scoreOptions: ScoreOptions,
): PartialCombo[] {
  const expanded: PartialCombo[] = [];
  for (const partial of beam) {
    for (const candidate of candidates) {
      const items = [...partial.items, candidate];
      expanded.push({ items, score: scoreOutfit(items, context, scoreOptions) });
    }
  }
  return prune(expanded, BEAM_WIDTH);
}

/** One ply for an OPTIONAL role: every partial's unchanged form ("skip") plus every extension. */
function extendOptional(
  beam: readonly PartialCombo[],
  candidates: readonly ScorableItem[],
  context: ScoringContext,
  scoreOptions: ScoreOptions,
): PartialCombo[] {
  const expanded: PartialCombo[] = [...beam];
  for (const partial of beam) {
    const already = new Set(partial.items.map((i) => i.id));
    for (const candidate of candidates) {
      if (already.has(candidate.id)) continue;
      const items = [...partial.items, candidate];
      expanded.push({ items, score: scoreOutfit(items, context, scoreOptions) });
    }
  }
  return prune(expanded, BEAM_WIDTH);
}

// §6.3's canonical signature lives in `_shared/scoring/equivalence.ts` and is
// imported above, NOT reimplemented here.
//
// It briefly was reimplemented here, and the two copies did not agree: this
// file bucketed hue by a flat 30° division while the shared one uses §5.4's
// hue-bin clustering. Both are defensible in isolation and the disagreement is
// not visible in either. It is visible on a Home screen, where the daily brief
// deduplicates outfits with one rule and the purchase-unlock count beside it
// deduplicates with the other, and the two answer differently whether two looks
// are "the same" — for the same closet, in the same session, six inches apart.
//
// That is the failure mode of building the generator and the unlock count at
// the same time, and the reason there is one §6.3 rather than a copy per
// caller. If the bucketing needs to change, it changes once.

function dropNearDuplicates(rankedDescending: readonly PartialCombo[]): PartialCombo[] {
  const seen = new Set<string>();
  const kept: PartialCombo[] = [];
  for (const combo of rankedDescending) {
    const signature = canonicalSignature(combo.items);
    if (seen.has(signature)) continue;
    seen.add(signature);
    kept.push(combo);
  }
  return kept;
}

function orderForDisplay(items: readonly ScorableItem[]): ScorableItem[] {
  return [...items].sort(
    (a, b) => ROLE_DISPLAY_ORDER.indexOf(a.role) - ROLE_DISPLAY_ORDER.indexOf(b.role),
  );
}

/**
 * Generates up to `desiredCount` ranked, deduplicated full outfits from a
 * closet, honouring locked/excluded items.
 *
 * LOCKED-ITEM SEMANTICS: a locked item id that cannot be resolved to a
 * wearable, non-excluded candidate — because it was excluded in the same
 * request, is currently unwearable (section 2.9), or belongs to a category
 * with no scoring role at all (fragrance) — makes the request as stated
 * unsatisfiable. Returning outfits anyway would mean either silently
 * dropping the caller's stated constraint or silently substituting a
 * different item for the one they locked; both are the confounded reading
 * CLAUDE.md's governing rule forbids. This returns an empty list instead,
 * the same shape the rest of this codebase already uses for "no outfit is
 * currently possible" (see `LeastRecentlyWornScorer`'s empty-required-role
 * case).
 *
 * FRESHNESS ROTATION: when a required (or optional) role has two or more
 * wearable items, garments worn in the last 24 hours are dropped before
 * combinations are built. Wear This otherwise cannot change tomorrow's
 * look — availability is 5% of the score and colour will keep winning.
 * If dropping them would empty the role, they stay: the only look is
 * still a look. A locked item is never rotated out.
 */
export function generateCandidateOutfits(
  items: readonly ScorableItem[],
  options: GenerateCandidateOutfitsOptions,
): GeneratedOutfit[] {
  if (options.desiredCount <= 0) return [];

  const context = options.context ?? {};
  const scoreOptions: ScoreOptions = { weights: options.weights };

  // Section 2.9's hard filter, run BEFORE any combination is built —
  // `wearableItems`'s header: filtering afterwards would waste the
  // combinatorics and could return an empty ranking with no explanation.
  const wearable = wearableItems(items).filter((item) => !options.excludedItemIds.has(item.id));

  const byRole = new Map<GarmentRole, ScorableItem[]>();
  for (const item of wearable) {
    const bucket = byRole.get(item.role);
    if (bucket) bucket.push(item);
    else byRole.set(item.role, [item]);
  }

  applyFreshnessRotation(byRole, options.lockedItemIds, options.now ?? new Date());

  const lockedByRole = new Map<GarmentRole, ScorableItem>();
  const lockedAccessories: ScorableItem[] = [];
  for (const item of wearable) {
    if (!options.lockedItemIds.has(item.id)) continue;
    if (item.role === "accessory") {
      lockedAccessories.push(item);
    } else if (!lockedByRole.has(item.role)) {
      // First match wins for a required/outerwear role with more than one
      // locked item in it (a contradictory request) — deterministic, and no
      // worse than any other arbitrary tiebreak, since the request itself
      // was already self-contradictory.
      lockedByRole.set(item.role, item);
    }
  }
  const resolvedLockIds = new Set(
    [...lockedByRole.values(), ...lockedAccessories].map((i) => i.id),
  );
  const hasUnresolvableLock = [...options.lockedItemIds].some((id) => !resolvedLockIds.has(id));
  if (hasUnresolvableLock) {
    return [];
  }

  let beam: PartialCombo[] = [{ items: [], score: scoreOutfit([], context, scoreOptions) }];

  for (const role of REQUIRED_ROLES) {
    const locked = lockedByRole.get(role);
    const candidates = locked ? [locked] : (byRole.get(role) ?? []);
    if (candidates.length === 0) {
      return []; // no outfit can be formed without this required role
    }
    beam = extendRequired(beam, candidates, context, scoreOptions);
  }

  const outerwearLocked = lockedByRole.get("outerwear");
  if (outerwearLocked) {
    beam = extendRequired(beam, [outerwearLocked], context, scoreOptions);
  } else {
    const outerwearCandidates = byRole.get("outerwear") ?? [];
    if (outerwearCandidates.length > 0) {
      beam = extendOptional(beam, outerwearCandidates, context, scoreOptions);
    }
  }

  // Locked accessories are unconditional additions, not something the
  // pruned pool below is trusted to keep — the "appears in every result"
  // guarantee must not depend on beam search happening to retain it.
  if (lockedAccessories.length > 0) {
    beam = beam.map((partial) => {
      const combinedItems = [...partial.items, ...lockedAccessories];
      return { items: combinedItems, score: scoreOutfit(combinedItems, context, scoreOptions) };
    });
  }

  const accessoryPool = (byRole.get("accessory") ?? [])
    .filter((item) => !lockedAccessories.some((locked) => locked.id === item.id))
    .slice(0, ACCESSORY_POOL_CAP);

  const remainingAccessorySlots = Math.max(
    0,
    MAX_ACCESSORIES_PER_OUTFIT - lockedAccessories.length,
  );
  for (let slot = 0; slot < remainingAccessorySlots && accessoryPool.length > 0; slot++) {
    beam = extendOptional(beam, accessoryPool, context, scoreOptions);
  }

  const ranked = prune(beam, beam.length); // final full sort, same ordering rule as every ply
  const deduped = dropNearDuplicates(ranked);

  return deduped.slice(0, options.desiredCount).map((combo) => {
    const displayItems = orderForDisplay(combo.items);
    return {
      items: displayItems,
      score: combo.score,
      reason: buildReason(displayItems, combo.score),
    };
  });
}
