// ============================================================================
// products/costPerWear.ts
// ============================================================================
// `docs/05-wardrobe-graph.md` §7.2's PROJECTED cost-per-wear — the only
// variant `/products/evaluate` can ever compute, since a purchase candidate
// has `wear_count == 0` by definition and §7.2 is explicit that the
// `price_paid / wear_count` path "must never reach that code path" for a
// zero-wear item.
//
// WHAT §7.2 ASKS FOR THAT THIS FILE DOES NOT HAVE THE INPUTS TO GIVE.
//
// §7.2's full formula is
//   projectedAnnualWears = categoryBaseRate(category, subcategory)
//                          × versatilityMultiplier(normalizedVersatility)
//                          × userCadenceMultiplier
// and this file's `categoryBaseRate` is keyed on `ClothingCategory` alone,
// not `(category, subcategory)` — `product_candidates` has no subcategory
// column at all (§9's field list, `20260728100600_commerce.sql`), so a
// per-subcategory rate table has no column to key its lookup on. The rate
// below is the category's rough population-weighted average across its
// subcategories (a "top" candidate scores between a t-shirt's 40/yr and a
// blazer's ~10/yr, not at either extreme).
//
// `userCadenceMultiplier` is fixed at its documented default of `1.0`
// rather than computed from the caller's real wear history. §7.2 defaults
// it to `1.0` itself "with fewer than 5 historical wears in that category
// to average over" — this file simply never tries to clear that bar, since
// doing so needs a same-category wear-count query `products/handler.ts`
// does not perform in this vertical slice. This is a real, documented
// simplification, not a silent one: `projectedCostPerWear`'s caller
// receives `usedDefaultCadence: true` on every call, and
// `products/evaluation.ts` adds a matching `unmeasured` entry so the wire
// response never implies a personalized cadence was used.
// ============================================================================

import type { ClothingCategory } from "../_shared/scoring/types.ts";

/**
 * §7.2's seed examples, blended per category rather than subcategory (see
 * this file's header): everyday tee ≈40/yr, dress shirt ≈15/yr, occasion
 * blazer ≈6/yr, formal suit ≈4/yr, everyday sneaker ≈60/yr, dress shoe
 * ≈20/yr. `fragrance` has no entry — "wears per year" does not honestly
 * describe how a fragrance is used, and `products/evaluation.ts`'s no-role
 * branch (the same one that skips compatibility scoring for fragrance)
 * never calls this function for one.
 */
const CATEGORY_BASE_RATE: Partial<Record<ClothingCategory, number>> = {
  top: 25,
  bottom: 28,
  outerwear: 8,
  shoes: 35,
  accessory: 20,
  watch: 30,
  dress: 22,
  skirt: 26,
};

const HORIZON_YEARS = 1;

/** §7.2's `0.5 + normalizedVersatility`, range 0.5–1.5. `normalizedVersatility` is already clamped to [0,1] by its caller. */
export function versatilityMultiplier(normalizedVersatility: number): number {
  return 0.5 + Math.min(1, Math.max(0, normalizedVersatility));
}

export interface ProjectedCostPerWearResult {
  /** `null` exactly per §7.2's edge case: no `price_paid` (here, no extracted price) means no honest number, never `$0.00`/`$∞`. */
  readonly value: number | null;
  readonly isProjected: true;
  /** Always `true` — see this file's header on why the real per-user cadence is never computed here. */
  readonly usedDefaultCadence: true;
  readonly degraded: readonly string[];
}

/**
 * §7.2's projected cost-per-wear for a not-yet-owned candidate.
 * `normalizedVersatility` is `outfits_unlocked` normalized against
 * `expectedVersatility(closetSize)` — see `products/evaluation.ts`'s
 * caller, which reuses `wardrobeScore.ts`'s own size-indexed curve rather
 * than inventing a second ceiling constant.
 */
export function projectedCostPerWear(
  price: number | null,
  category: ClothingCategory,
  normalizedVersatility: number,
): ProjectedCostPerWearResult {
  const degraded = ["your personal wear cadence (using the category-average default, per §7.2)"];

  if (price === null) {
    return {
      value: null,
      isProjected: true,
      usedDefaultCadence: true,
      degraded: [...degraded, "price (never extracted, so no cost-per-wear can be projected)"],
    };
  }

  const baseRate = CATEGORY_BASE_RATE[category];
  if (baseRate === undefined) {
    return {
      value: null,
      isProjected: true,
      usedDefaultCadence: true,
      degraded: [...degraded, `an annual-wear baseline for "${category}" (not modeled)`],
    };
  }

  const projectedAnnualWears = baseRate * versatilityMultiplier(normalizedVersatility);
  // §7.2: never divide by fewer than one projected wear a year, even for a
  // candidate with zero measured versatility — the floor keeps this from
  // producing `Infinity`, the same protection §7.2 requires for the
  // actual (wear_count-based) formula's zero-wear case.
  const value = price / Math.max(projectedAnnualWears * HORIZON_YEARS, 1);

  return { value, isProjected: true, usedDefaultCadence: true, degraded };
}
