/**
 * The inputs every compatibility sub-scorer reads, and the shape they return.
 *
 * `docs/05-wardrobe-graph.md` §2. Deliberately a projection of `closet_items`
 * rather than the row itself: the scorer takes what it needs, already parsed,
 * so that §2's formulas stay pure functions and a schema change surfaces at one
 * mapping boundary instead of eight.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * FOUR PLACES THE SHIPPED SCHEMA DISAGREES WITH THE DESIGN DOCUMENT, AND WHAT
 * THIS FILE DOES ABOUT IT. All four were found by reading
 * `20260728100100_core_enums.sql` and `20260728100300_closet.sql` against §2,
 * and all four are recorded here because the doc will be amended to match — the
 * database is the shipped reality and the prose is not.
 *
 * 1. WARMTH IS 0–100, NOT 0–10. §2.5's mapping table says "warmth 0 → 30°C,
 *    warmth 10 → −5°C". The column is `smallint check (between 0 and 100)`.
 *    Read on the doc's scale, a warm overcoat at 85 would map to an ideal
 *    temperature hundreds of degrees below zero and every winter garment would
 *    score 0 against every forecast. The scale here is the column's.
 *    `water_resistance_score` has the same 0–100 column and the same fix: §2.5's
 *    "< 3" rain threshold becomes "< 30".
 *
 * 2. `availability_state` HAS SEVEN VALUES, NOT TWO. §2.9 excludes items whose
 *    `laundry_state` is `laundry` or `unavailable` and says nothing about
 *    availability beyond that. The enum also carries `in_alteration`,
 *    `packed_for_travel`, `lent_out` and `lost`. Recommending a jacket that is
 *    at the tailor, in a suitcase in another city, on a friend's floor, or gone
 *    is the same product failure as recommending a dirty shirt — the user
 *    cannot put it on. `isWearable` excludes all of them.
 *
 * 3. THERE IS NO `pattern_scale` COLUMN. §1.5's pattern-mixing penalty needs a
 *    micro/small/medium/large scale to decide whether two patterns layer or
 *    compete, and nothing stores one. Rather than guess a scale — which would
 *    invent the precise fact the rule turns on — `patternScale` is nullable and
 *    the penalty degrades explicitly. See `subscores/color.ts`.
 *
 * 4. `closet_items` HAS NO `occasion_tags`. §2.8 reads them from "outfit/item";
 *    only `outfits` has the column. Item-level occasion relevance therefore has
 *    no input at all today and returns the doc's own unconstrained-request
 *    default rather than pretending to a match it cannot compute.
 * ─────────────────────────────────────────────────────────────────────────────
 */

import type { LCh } from "./colorSpace.ts";

/** `clothing_category` in `20260728100100_core_enums.sql`. */
export type ClothingCategory =
  | "top"
  | "bottom"
  | "outerwear"
  | "shoes"
  | "accessory"
  | "watch"
  | "fragrance";

/**
 * The five roles §2.1's pair-weight table actually knows about.
 *
 * `watch` folds into `accessory`, which is what it is for pairing purposes.
 * `fragrance` maps to nothing and is filtered out before scoring: it has no
 * colour, no silhouette and no formality that any of these formulas can read,
 * and a scent cannot clash with a pair of trousers. §2.1 does not mention it
 * because the table predates the category existing.
 */
export type GarmentRole = "top" | "bottom" | "outerwear" | "shoes" | "accessory";

/** `fit_preference` in the same migration. Matches §4.1's five ranks exactly. */
export type Fit = "slim" | "tailored" | "regular" | "relaxed" | "oversized";

/** `laundry_state`. Note `worn_once` — the doc writes it `wornOnce`. */
export type LaundryState = "clean" | "worn_once" | "laundry" | "unavailable";

/**
 * `condition` in `20260728100100_core_enums.sql`, extended by
 * `20260808120000_condition_damaged.sql`.
 *
 * §5.6 writes this scale as `excellent, good, fair, worn, damaged`. The shipped
 * enum is `new_with_tags, like_new, good, fair, worn, damaged` — six values,
 * and still not the doc's names: there is no `excellent`, and two values
 * (`new_with_tags`, `like_new`) sit above `good` where the doc has one.
 *
 * `damaged` was missing until 2026-08-08 and is not a cosmetic addition: it is
 * §5.6's 0.0 rung, and without it a garment with a hole in it could not score
 * below `worn` (0.25). The vision provider had been reading `damaged` correctly
 * and `closet/mapper.ts` had been mapping it down to `worn` on the way in.
 * See `wardrobeScore.ts` for the value mapping and `docs/05` §0 for the
 * amendment.
 */
export type Condition =
  | "new_with_tags"
  | "like_new"
  | "good"
  | "fair"
  | "worn"
  | "damaged";

export type AvailabilityState =
  | "available"
  | "in_laundry"
  | "in_alteration"
  | "packed_for_travel"
  | "lent_out"
  | "lost"
  | "unavailable";

export type Season = "spring" | "summer" | "fall" | "winter";

export type Pattern =
  | "solid"
  | "stripe"
  | "check"
  | "herringbone"
  | "print"
  | "texture-only";

/** §1.5's scale ranks. No column feeds this yet — see note 3 in the header. */
export type PatternScale = "micro" | "small" | "medium" | "large";

/**
 * One garment, already parsed into what §2's formulas read.
 *
 * Every field a provider might not have populated is nullable, and every
 * sub-scorer that meets a null says so in `degraded` rather than substituting a
 * number and calling it measured.
 */
export interface ScorableItem {
  readonly id: string;
  readonly category: ClothingCategory;
  readonly role: GarmentRole;
  /** Resolved from the row's `primary_color` TEXT via the colour vocabulary. */
  readonly primaryColor: LCh | null;
  /** Precomputed with `primaryColor` so §1.3 runs once per item, not per pair. */
  readonly isNeutral: boolean;
  readonly secondaryColors: readonly LCh[];
  readonly pattern: Pattern | null;
  readonly patternScale: PatternScale | null;
  /**
   * The row's `material jsonb` array, lowercased by the mapper.
   *
   * Read only by §4.3's fit dampeners, which exempt a stretch fabric from the
   * slim-cut penalty — a slim stretch trouser does not pull across the thigh
   * the way a slim rigid one does.
   */
  readonly materials: readonly string[];
  /** 0–100. Null until the classifier has seen the garment. */
  readonly formalityScore: number | null;
  readonly fit: Fit | null;
  readonly seasonality: readonly Season[];
  /** 0–100 per the column, NOT §2.5's 0–10. See note 1. */
  readonly warmthScore: number | null;
  /** 0–100 per the column. See note 1. */
  readonly waterResistanceScore: number | null;
  readonly laundryState: LaundryState;
  readonly availabilityState: AvailabilityState;
  /**
   * When this garment was last worn, if ever.
   *
   * Optional so existing `garment()` test helpers and product-candidate
   * projections (which have never been worn) stay valid. Absent is the same
   * fact as null: never worn, so rotation has nothing to exclude.
   */
  readonly lastWornAt?: Date | null;
  /**
   * The closet row's colour WORD (`primary_color` text), not the resolved LCh.
   *
   * Copy names what he photographed ("navy", "stone"). Scoring still uses
   * `primaryColor`. Optional so helpers that never had a word stay valid.
   */
  readonly colorName?: string | null;
}

/**
 * Can the user actually put this on today?
 *
 * §2.9's rule, widened to the enum that shipped (note 2). This is a filter
 * before it is a score: an unwearable item is removed from candidate
 * generation, not down-weighted, because an outfit built around a garment at
 * the dry cleaner is not a low-quality suggestion — it is a wrong one.
 */
export function isWearable(item: ScorableItem): boolean {
  if (item.laundryState === "laundry" || item.laundryState === "unavailable") {
    return false;
  }
  return item.availabilityState === "available";
}

/** Categories that carry no signal any §2 formula can read. See `GarmentRole`. */
export function roleFor(category: ClothingCategory): GarmentRole | null {
  switch (category) {
    case "top":
    case "bottom":
    case "outerwear":
    case "shoes":
      return category;
    case "accessory":
    case "watch":
      return "accessory";
    case "fragrance":
      return null;
  }
}

/** Weather for §2.5. Absent entirely when the provider had nothing. */
export interface WeatherContext {
  readonly temperatureC: number;
  /** 0–1. */
  readonly precipitationProbability: number;
}

/** The user's stated preferences, for §2.6. */
export interface PreferenceContext {
  readonly preferredColors: readonly string[];
  readonly avoidedColors: readonly string[];
  readonly preferredFit: Fit | null;
  /** 0–100 centre of the band the user says they dress in. */
  readonly formalityPreferenceCenter: number | null;
}

/** One prior co-wear of a specific pair, for §2.7. */
export interface CoWearStat {
  readonly totalCoWears: number;
  /** Co-wears the user rated ≥ 3. */
  readonly positiveCoWears: number;
}

/**
 * Everything outside the garments themselves that the eight components read.
 *
 * All optional. A new user with no weather permission, no stated preferences
 * and no wear history still gets a score — every component has a documented
 * cold-start prior, and each one reports itself degraded so nothing downstream
 * describes a default as a measurement.
 */
export interface ScoringContext {
  readonly weather?: WeatherContext;
  readonly preferences?: PreferenceContext;
  /** Keyed `"<itemIdA>|<itemIdB>"` with ids sorted, so lookup is order-free. */
  readonly coWear?: ReadonlyMap<string, CoWearStat>;
  /** Same shape, keyed by sorted role pair, for §2.7's category fallback. */
  readonly coWearByRole?: ReadonlyMap<string, CoWearStat>;
  /** The occasion the user asked about, if any. §2.8. */
  readonly targetOccasion?: string;
}

/**
 * A sub-score, plus what it could not measure.
 *
 * `degraded` is the part that matters and the reason this is not a bare number.
 * CLAUDE.md's governing rule is that absent is honest and a confounded reading
 * is not, and the place that rule gets broken is a default silently becoming a
 * claim: a 0.75 weather prior for a user with no location, read downstream as
 * "this outfit suits today's weather". Every component that falls back to a
 * documented prior names the input it lacked, `CompatibilityScore` collects
 * them, and Kyra's copy layer is required to drop any sentence resting on one.
 */
export interface Subscore {
  /** Normalised to [0,1]. */
  readonly value: number;
  /** Human-readable inputs this score is missing. Empty when fully measured. */
  readonly degraded: readonly string[];
}

export function measured(value: number): Subscore {
  return { value, degraded: [] };
}

export function degradedScore(value: number, ...reasons: string[]): Subscore {
  return { value, degraded: reasons };
}

/** Clamp into [0,1]; NaN becomes the caller's floor rather than propagating. */
export function unitClamp(value: number, fallback = 0): number {
  if (!Number.isFinite(value)) return fallback;
  return Math.min(1, Math.max(0, value));
}
