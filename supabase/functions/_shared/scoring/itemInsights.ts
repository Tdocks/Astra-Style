import { scoreOutfit } from "./compatibility.ts";
import { labFromLCh, redundancyScore, seasonalityOverlaps, similarity } from "./redundancy.ts";
import type { RedundancyItem } from "./redundancy.ts";
import { isWearable } from "./types.ts";
import type { ScorableItem, ScoringContext } from "./types.ts";

function redundancyItem(item: ScorableItem): RedundancyItem {
  return {
    id: item.id,
    category: item.category,
    role: item.role,
    primaryColorLab: item.primaryColor ? labFromLCh(item.primaryColor) : null,
    formalityScore: item.formalityScore,
    fit: item.fit,
    materials: item.materials,
    seasonality: item.seasonality,
  };
}
export interface InsightItem extends ScorableItem {
  readonly archivedAt: Date | null;
  readonly condition: string | null;
}
export interface InsightOutfit {
  readonly id: string;
  readonly itemIds: readonly string[];
  readonly archivedAt: Date | null;
}
/** Caller supplies its own rows. Pair scores rank two pieces, not complete outfits. */
export function computeItemInsights(
  target: InsightItem,
  closet: readonly InsightItem[],
  outfits: readonly InsightOutfit[],
  context: ScoringContext = {},
) {
  const active = closet.filter((item) => item.archivedAt === null);
  const comparison = redundancyItem(target);
  const similarItems = active.filter((item) =>
    item.id !== target.id && item.category === target.category &&
    seasonalityOverlaps(item.seasonality, target.seasonality)
  )
    .map((item) => ({
      itemId: item.id,
      similarity: Math.round(similarity(comparison, redundancyItem(item)) * 100),
    }))
    .sort((a, b) => b.similarity - a.similarity || a.itemId.localeCompare(b.itemId));
  const pairings = target.archivedAt === null && isWearable(target)
    ? active.filter((item) =>
      item.id !== target.id && item.role !== target.role && isWearable(item) &&
      !([item.role, target.role].includes("dress") &&
        [item.role, target.role].some((role) => role === "top" || role === "bottom"))
    )
      .map((item) => {
        const score = scoreOutfit([target, item], context);
        return { itemId: item.id, score: score.score, missingInputs: score.degraded };
      })
      .sort((a, b) => b.score - a.score || a.itemId.localeCompare(b.itemId)).slice(0, 6)
    : [];
  const savedOutfitIds = outfits.filter((outfit) =>
    outfit.archivedAt === null && outfit.itemIds.includes(target.id)
  )
    .map((outfit) => outfit.id).sort();
  return {
    redundancyScore: Math.round(redundancyScore(comparison, active.map(redundancyItem)) * 100),
    similarItems: similarItems.slice(0, 3),
    pairings,
    savedOutfitIds: [...new Set(savedOutfitIds)],
    replacementReason: target.condition === "damaged"
      ? "recorded_damage"
      : target.condition === "worn"
      ? "recorded_wear"
      : null,
    missingRedundancyInputs: [
      ...(target.primaryColor === null ? ["color"] : []),
      ...(target.fit === null ? ["fit"] : []),
      ...(target.materials.length === 0 ? ["material"] : []),
      ...(target.formalityScore === null ? ["formality"] : []),
    ],
  };
}
