// ============================================================================
// _shared/scoring/leastRecentlyWorn.ts
// ============================================================================
// *** THIS IS NOT THE REAL COMPATIBILITY SCORER. ***
//
// docs/05-wardrobe-graph.md §2 defines the real, eventual algorithm: eight
// weighted pairwise components (color harmony in CIE LCh, formality
// alignment, silhouette compatibility, season/weather fit, user preference,
// historical co-wear, occasion relevance, availability), combined via
// role-pair aggregation weights, producing a 0-100 score with a real
// explanation. None of that is implemented here.
//
// docs/01-build-roadmap.md, "Vertical slice first", is explicit that this
// slice exists to prove deployment/auth/data-flow, not recommendation
// quality, and names the exact placeholder to build: "pick one top + one
// bottom + one pair of shoes if available" preferring freshness of rotation
// over any notion of visual compatibility. That is precisely what
// `LeastRecentlyWornScorer` below does — nothing more.
//
// ---------------------------------------------------------------------------
// THE SEAM
// ---------------------------------------------------------------------------
// `OutfitScorer` is the interface every caller depends on. When the real
// `CompatibilityScorer` (docs/05-wardrobe-graph.md) is built, it should
// implement this same interface, and each caller swaps in the new
// implementation via its `Deps.scorer` field with no other change required.
//
// This file moved from `outfits/scorer.ts` to `_shared/scoring/` on
// 2026-08-06, on the terms its own header set out: a second caller arrived.
// `daily-brief` needs the same placeholder to pick a primary outfit and its
// alternatives, and one function reaching into another function's directory
// would couple two separate deploy units (ADR 0013). Callers today are
// `outfits/handler.ts` and `daily-brief/handler.ts`; `/outfits/rank` and
// `/products/evaluate` are the next two named in
// docs/05-wardrobe-graph.md's header ("a pure-function scoring core shared
// by both"). No caller of this interface should ever come to depend
// on `LeastRecentlyWornScorer`-specific behavior (e.g. "outfits are always
// exactly 3 items") beyond what `OutfitScorer` promises, so that swap stays
// a one-line change.
// ============================================================================

export type ClothingCategory =
  | "top"
  | "bottom"
  | "outerwear"
  | "shoes"
  | "accessory"
  | "watch"
  | "fragrance";

/** The subset of `closet_items` columns (see supabase/migrations/20260728100300_closet.sql) this slice's scoring needs. */

/**
 * The interface the real `CompatibilityScorer` will implement later — see
 * "THE SEAM" above. `items` is expected to already be ownership-scoped
 * (only the authenticated caller's own closet items) and availability-
 * filtered (excluding archived/dirty/unavailable items) by the caller;
 * this interface is about *which combination* to pick, not *whose* items
 * or *which items are eligible at all*.
 */

/**
 * A required outfit needs exactly one item from each of these categories.
 * The real scorer additionally considers `outerwear` and up to two
 * `accessory` items (docs/05-wardrobe-graph.md §6.1); this slice
 * deliberately does not, per the roadmap's explicit exclusion list.
 */
const REQUIRED_ROLES: readonly ClothingCategory[] = ["top", "bottom", "shoes"];

/**
 * A fixed, clearly-labeled placeholder so the response shape matches
 * `OutfitRecommendation.compatibilityScore` (an `Int` the iOS client
 * expects on every recommendation). This is NOT a computed compatibility
 * score — do not use it for ranking, filtering, or any product decision.
 * The real value, once `CompatibilityScorer` lands, is `round(100 * sum(weight_i
 * * subscore_i))` per docs/05-wardrobe-graph.md §2.
 */
export const SLICE_PLACEHOLDER_COMPATIBILITY_SCORE = 65;

function lastWornSortKey(item: OutfitScorerRow): number {
  // Never-worn items (`last_worn_at === null`) sort first (most negative),
  // i.e. they are preferred over anything with a recorded wear — matching
  // the roadmap's "preferring least-recently-worn" instruction.
  if (item.last_worn_at === null) {
    return -Infinity;
  }
  const parsed = Date.parse(item.last_worn_at);
  return Number.isNaN(parsed) ? -Infinity : parsed;
}

/**
 * docs/01-build-roadmap.md's named slice implementation: "pick one top + one
 * bottom + one pair of shoes if available", preferring least-recently-worn
 * items. No color, formality, silhouette, weather, preference, co-wear, or
 * occasion signal is consulted — see the module header for why.
 */
// The contract and its row type now live in `outfitScorer.ts` — see that
// file's header for why they could not stay here once a second implementation
// existed. Re-exported so existing importers of this module keep working.
import type {
  OutfitScorer,
  OutfitScorerOptions,
  OutfitScorerRow,
  ScoredOutfit,
} from "./outfitScorer.ts";

export type { OutfitScorer, OutfitScorerOptions, OutfitScorerRow, ScoredOutfit };
/** Historic name for the row type, kept so existing importers still resolve. */
export type ClosetItemRow = OutfitScorerRow;

export class LeastRecentlyWornScorer implements OutfitScorer {
  generate(items: readonly OutfitScorerRow[], options: OutfitScorerOptions): ScoredOutfit[] {
    const { desiredCount, lockedItemIds, excludedItemIds } = options;
    if (desiredCount <= 0) {
      return [];
    }

    // Exclusion takes precedence over locking: an item that is both locked
    // and excluded in the same request (a contradictory client request) is
    // filtered out here before the locked-item lookup below ever sees it,
    // so it is simply not pinned rather than causing an error.
    const eligible = items.filter((item) => !excludedItemIds.has(item.id));

    const buckets = new Map<ClothingCategory, ClosetItemRow[]>();
    for (const role of REQUIRED_ROLES) {
      buckets.set(role, []);
    }
    for (const item of eligible) {
      buckets.get(item.category as ClothingCategory)?.push(item);
    }
    for (const bucket of buckets.values()) {
      bucket.sort((a, b) => lastWornSortKey(a) - lastWornSortKey(b));
    }

    // A closet's worth of missing required roles means no outfit can be
    // formed at all — this is a legitimate empty-closet/thin-closet state
    // (docs/05-wardrobe-graph.md §8, "0 items" / early cold-start rows),
    // not an error; the handler returns an empty list, and the client's
    // existing empty-state UI (spec §21) is what should show.
    for (const role of REQUIRED_ROLES) {
      if ((buckets.get(role) ?? []).length === 0) {
        return [];
      }
    }

    // A locked item pins that role to exactly that item for every
    // generated outfit (mirrors the outfit builder's "locking an item ...
    // changes only the unlocked slots" behavior, spec §5.4 exit criteria,
    // even though full rank/regenerate is out of scope for this slice).
    // If more than one locked item shares a role, the least-recently-worn
    // one among them wins — locked items are still sorted into their
    // bucket above, so this falls out of the same ordering.
    const lockedByRole = new Map<ClothingCategory, ClosetItemRow>();
    for (const role of REQUIRED_ROLES) {
      const lockedInRole = (buckets.get(role) ?? []).find((item) => lockedItemIds.has(item.id));
      if (lockedInRole) {
        lockedByRole.set(role, lockedInRole);
      }
    }

    const unlockedRoleCounts = REQUIRED_ROLES
      .filter((role) => !lockedByRole.has(role))
      .map((role) => (buckets.get(role) ?? []).length);
    const maxCombinations = unlockedRoleCounts.length > 0 ? Math.min(...unlockedRoleCounts) : 1;
    const outfitCount = Math.min(desiredCount, maxCombinations);

    const results: ScoredOutfit[] = [];
    for (let i = 0; i < outfitCount; i++) {
      const itemIds: string[] = [];
      for (const role of REQUIRED_ROLES) {
        const chosen = lockedByRole.get(role) ?? (buckets.get(role) ?? [])[i];
        // Every role is guaranteed non-empty by the check above, and `i`
        // is bounded by `maxCombinations`, so `chosen` is always defined
        // for an unlocked role; TypeScript can't see that invariant, so we
        // fail loudly rather than silently skip a role if it were ever
        // violated by a future edit.
        if (!chosen) {
          throw new Error(`Internal error: no candidate item for role "${role}" at index ${i}.`);
        }
        itemIds.push(chosen.id);
      }
      results.push({
        itemIds,
        compatibilityScore: SLICE_PLACEHOLDER_COMPATIBILITY_SCORE,
        reason: "Picked from your least-recently-worn top, bottom, and shoes — a deterministic " +
          "vertical-slice placeholder, not the real compatibility scorer (docs/05-wardrobe-graph.md §2).",
      });
    }
    return results;
  }
}
