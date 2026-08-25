/**
 * The real §10 engine, wearing the `OutfitScorer` interface `daily-brief`
 * already depends on.
 *
 * `P4-HOME-02` shipped `daily-brief` against `LeastRecentlyWornScorer`: a
 * deliberate placeholder that picks the least-recently-worn garment per role
 * and returns a fixed score with one hardcoded sentence. It was the honest
 * thing to ship at the time — Home needed an endpoint that existed more than
 * it needed a good one, and the placeholder's own header says so at length.
 *
 * It is no longer the honest thing, because the engine exists. This class is
 * the swap, and it is deliberately an ADAPTER rather than a rewrite of
 * `buildBrief`: the handler already takes its scorer through an interface, so
 * the whole change is one line in `index.ts` and the handler's tests keep
 * working against a stub. A rewrite would have touched the transaction
 * ordering (`outfits` before `daily_briefs`) that `handler_test.ts` pins, for
 * no gain.
 *
 * WHY THE ROW TYPE HAD TO WIDEN, AND WHY THAT IS THE WHOLE COST OF THIS SWAP.
 * The placeholder needed three columns: `id`, `category`, `last_worn_at`. It
 * could not need more — it does not look at a garment, only at a calendar. The
 * real engine reads colour, formality, fit, materials, seasonality, warmth,
 * water resistance, pattern, laundry and availability, because that is what
 * "do these go together" turns out to mean. So `listCandidateItems` selects
 * the row rather than three fields of it, and this file maps it.
 *
 * ONE PLACE, NOT TWO. Generation goes through `generateCandidateOutfits` — the
 * same function `/outfits/generate` calls, with the same §6.3 deduplication
 * and the same beam search. A separate implementation here would drift from
 * the endpoint within a release, and the two would disagree about the same
 * closet on the same morning: the brief on Home, and the outfits behind the
 * "see alternatives" tap beside it.
 */

import type { ScorableItem } from "./types.ts";
import { mapClosetItemRowToScorableItem } from "./closetItemMapper.ts";
import {
  generateCandidateOutfits,
  type GenerateCandidateOutfitsOptions,
} from "../../outfits/candidateGeneration.ts";
import type { ScoringContext } from "./types.ts";
import type {
  OutfitScorer,
  OutfitScorerOptions,
  OutfitScorerRow,
  ScoredOutfit,
} from "./outfitScorer.ts";

/**
 * A closet row as `daily-brief` now selects it — the mapper's shape, which is
 * the real table's shape.
 */
export type CompatibilityScorerRow = OutfitScorerRow;

export class CompatibilityOutfitScorer implements OutfitScorer {
  /**
   * Constructor context is the caller's stable baseline (for example its
   * wardrobe graph). `OutfitScorerOptions.context` overlays facts that vary
   * per request, such as today's WeatherKit reading. Keeping both lets packing
   * and tests retain a fixed context while Daily Brief cannot accidentally
   * reuse one user's forecast for the next request.
   *
   * Today `daily-brief` has weather to give (the client sends it) and nothing
   * else — no stated preferences, no co-wear history. Those subscores fall to
   * their documented priors and say so in `unmeasured`, which is exactly the
   * behaviour the scorer was built to have. It is not a gap being hidden; it
   * is a gap being reported.
   */
  constructor(private readonly context: ScoringContext = {}) {}

  generate(
    items: readonly CompatibilityScorerRow[],
    options: OutfitScorerOptions,
  ): ScoredOutfit[] {
    const context: ScoringContext = {
      ...this.context,
      ...options.context,
    };
    const scorable: ScorableItem[] = [];
    for (const row of items) {
      // Null for a row the engine cannot read at all — a fragrance, which has
      // no colour or silhouette to judge. Dropped rather than defaulted.
      const mapped = mapClosetItemRowToScorableItem(row);
      if (mapped !== null) scorable.push(mapped);
    }

    const generationOptions: GenerateCandidateOutfitsOptions = {
      desiredCount: options.desiredCount,
      lockedItemIds: options.lockedItemIds,
      excludedItemIds: options.excludedItemIds,
      context,
    };

    return generateCandidateOutfits(scorable, generationOptions).map((outfit) => ({
      itemIds: outfit.items.map((item) => item.id),
      compatibilityScore: outfit.score.score,
      reason: outfit.reason,
    }));
  }
}
