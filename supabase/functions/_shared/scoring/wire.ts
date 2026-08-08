/**
 * The wire shape a scored outfit crosses the network in.
 *
 * ONE CONTRACT, FIXED BEFORE ANYTHING IS BUILT ON EITHER SIDE OF IT. This file
 * and its Swift counterpart (`OutfitRecommendation` +
 * `CompatibilityBreakdown`) are the only agreement `/outfits/generate`,
 * `/outfits/rank`, `daily-brief` and every iOS screen have with each other.
 * Fixing it first is what lets the endpoints and the screens be built at the
 * same time instead of one waiting on the other.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * `unmeasured` IS THE FIELD THAT DOES NOT LOOK IMPORTANT AND IS.
 *
 * The scorer returns every component's `degraded` list — the inputs it fell
 * back to a documented prior for. Colour it never analysed. Weather it could
 * not fetch. A wardrobe with no wear history. Those priors are chosen so the
 * ranking stays sensible, and they work: a brand-new user gets a usable
 * recommendation on his first morning.
 *
 * The danger is entirely downstream. A 0.6 colour prior is a defensible
 * ranking input and an indefensible *claim*: the moment it reaches an outfit
 * card as "these colours work well together", the app has told a man something
 * nobody measured, about a garment nobody looked at. That is precisely the
 * confounded reading CLAUDE.md's governing rule forbids — absent is honest.
 *
 * Dropping `unmeasured` at the network boundary would make that rule
 * unenforceable past the server, because a bare 74 is indistinguishable from a
 * measured 74. So it crosses the wire, and the copy layer is required to drop
 * any sentence that rests on one of its entries.
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * WHY THIS EXTENDS `OutfitRecommendation` RATHER THAN REPLACING IT. That type
 * is specified in master spec §26 verbatim, and it already ships. Both new
 * fields are therefore additive and optional: an older client decodes the
 * response unchanged and simply shows no breakdown, and the §26 shape stays
 * the shape §26 describes.
 */

import type { CompatibilityScore } from "./compatibility.ts";

/**
 * The eight §10 components, keyed to match Swift's `CompatibilityBreakdown`
 * `CodingKeys` exactly.
 *
 * `frame_harmony` is deliberately absent from anything this server produces.
 * Swift splits §10's single 0.15 silhouette weight into garment-versus-garment
 * (`silhouette_internal`) and garment-versus-wearer (`frame_harmony`,
 * `docs/14-frame-fit.md`), and only the first has a server implementation. The
 * Swift field is already optional and collapses to `silhouetteInternal` when
 * nil, so omitting it here is the correct and honest wire, not a gap: the
 * server genuinely has not judged the wearer.
 */
export interface CompatibilityBreakdownWire {
  readonly color_compatibility: number;
  readonly formality_alignment: number;
  readonly silhouette_internal: number;
  readonly season_weather_suitability: number;
  readonly user_preference: number;
  readonly historical_co_wear: number;
  readonly occasion_relevance: number;
  readonly availability_laundry: number;
}

/** §26's `OutfitRecommendation`, plus the two additive fields. */
export interface ScoredOutfitWire {
  readonly id: string;
  readonly name: string;
  readonly reason: string;
  readonly compatibility_score: number;
  readonly item_ids: readonly string[];
  readonly missing_product_ids: readonly string[];
  /** Additive. Absent when a caller asked for the score without the parts. */
  readonly breakdown?: CompatibilityBreakdownWire;
  /**
   * Additive. Every input the score fell back to a prior for, in words a
   * person could read. Empty when the score is fully measured — and it CAN be
   * empty, which is what makes it worth trusting.
   */
  readonly unmeasured: readonly string[];
}

/** The §3.1 register, carried alongside so a card can name what it is. */
export interface ScoredOutfitEnvelope extends ScoredOutfitWire {
  readonly formality_register: number | null;
}

export function breakdownToWire(score: CompatibilityScore): CompatibilityBreakdownWire {
  const c = score.components;
  return {
    color_compatibility: c.color.value,
    formality_alignment: c.formality.value,
    silhouette_internal: c.silhouette.value,
    season_weather_suitability: c.seasonWeather.value,
    user_preference: c.userPreference.value,
    historical_co_wear: c.coWear.value,
    occasion_relevance: c.occasion.value,
    availability_laundry: c.availability.value,
  };
}

export interface ScoredOutfitInput {
  readonly id: string;
  readonly name: string;
  readonly reason: string;
  readonly itemIds: readonly string[];
  readonly missingProductIds?: readonly string[];
  readonly includeBreakdown?: boolean;
}

/**
 * The single place a `CompatibilityScore` becomes something a client sees.
 *
 * Everything that ranks outfits goes through here, so `unmeasured` cannot be
 * forgotten by one endpoint and remembered by another — which is exactly how a
 * rule like this decays.
 */
export function toScoredOutfit(
  input: ScoredOutfitInput,
  score: CompatibilityScore,
): ScoredOutfitEnvelope {
  return {
    id: input.id,
    name: input.name,
    reason: input.reason,
    compatibility_score: score.score,
    item_ids: [...input.itemIds],
    missing_product_ids: [...(input.missingProductIds ?? [])],
    ...(input.includeBreakdown === false ? {} : { breakdown: breakdownToWire(score) }),
    unmeasured: [...score.degraded],
    formality_register: score.formalityRegister,
  };
}
