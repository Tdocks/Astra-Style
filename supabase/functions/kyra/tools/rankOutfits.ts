// ============================================================================
// kyra/tools/rankOutfits.ts
// ============================================================================
// The `rank_outfits` tool (P5-KYRA-05, docs/06 §3.2). Read-only: scores and
// orders candidates, creates nothing. Scoring goes through the same
// `scoreOutfit` engine `/outfits/rank` uses (`_shared/scoring/compatibility.ts`)
// — one engine, not a Kyra-flavored reimplementation, which is P5-KYRA-05's
// entire acceptance criterion ("tool call output matches a direct call to
// /outfits/rank for equivalent input" — same items in, same score out).
//
// Same resolution contract as `handleRankOutfits`: an item id that does not
// resolve (not owned, archived, deleted, or a fragrance with no scoring
// role) makes that CANDIDATE un-scoreable as stated, and it is dropped —
// never silently scored as a different outfit than the one asked about.
// `occasion_id` resolves to the occasion's title so the §2.8 occasion
// subscore has a real target rather than a guessed one.
// ============================================================================

import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";
import {
  type ClosetItemMapperRow,
  mapClosetItemRowToScorableItem,
} from "../../_shared/scoring/closetItemMapper.ts";
import { scoreOutfit } from "../../_shared/scoring/compatibility.ts";
import { breakdownToWire } from "../../_shared/scoring/wire.ts";
import type { ScorableItem, ScoringContext } from "../../_shared/scoring/types.ts";
import { isUUID } from "../../_shared/validation.ts";

export interface RankOutfitsDeps {
  /** Full mapper rows for specific ids; RLS-scoped, absent when not owned. */
  listItemsByIds(ids: readonly string[]): Promise<ClosetItemMapperRow[]>;
  /** closet_item ids per outfit id, for candidates given as saved outfits. */
  listOutfitItemIds(outfitIds: readonly string[]): Promise<ReadonlyMap<string, string[]>>;
  /** Occasion title lookup for the §2.8 subscore target. Null when unknown. */
  getOccasionTitle(occasionId: string): Promise<string | null>;
}

export interface RankOutfitsArgs {
  readonly candidateOutfitIds: string[];
  readonly candidateItemCombinations: string[][];
  readonly occasionId?: string;
  readonly targetFormality?: number;
}

export const rankOutfitsDefinition: StylistToolDefinition = {
  name: "rank_outfits",
  description:
    "Score and rank candidate outfits (existing outfit IDs or ad-hoc item-ID combinations) " +
    "against an occasion/context. Read-only — does not create or save anything.",
  parametersSchema: {
    type: "object",
    properties: {
      candidate_outfit_ids: { type: "array", items: { type: "string", format: "uuid" } },
      candidate_item_combinations: {
        type: "array",
        items: {
          type: "array",
          items: { type: "string", format: "uuid" },
          description: "A set of closet_item IDs forming one ad-hoc outfit.",
        },
      },
      occasion_id: { type: "string", format: "uuid", nullable: true },
      target_formality: { type: "integer", minimum: 0, maximum: 100, nullable: true },
    },
    required: [],
  },
};

const MAX_CANDIDATES = 20;

export function parseRankOutfitsArgs(raw: Record<string, unknown>): RankOutfitsArgs {
  const outfitIds = Array.isArray(raw["candidate_outfit_ids"])
    ? raw["candidate_outfit_ids"].filter(isUUID)
    : [];
  const combinations: string[][] = [];
  if (Array.isArray(raw["candidate_item_combinations"])) {
    for (const entry of raw["candidate_item_combinations"]) {
      if (!Array.isArray(entry)) continue;
      const ids = entry.filter(isUUID);
      if (ids.length > 0) combinations.push(ids);
    }
  }
  const args: {
    candidateOutfitIds: string[];
    candidateItemCombinations: string[][];
    occasionId?: string;
    targetFormality?: number;
  } = {
    candidateOutfitIds: outfitIds.slice(0, MAX_CANDIDATES),
    candidateItemCombinations: combinations.slice(0, MAX_CANDIDATES),
  };
  if (isUUID(raw["occasion_id"])) args.occasionId = raw["occasion_id"];
  const formality = raw["target_formality"];
  if (typeof formality === "number" && Number.isInteger(formality)) {
    args.targetFormality = Math.min(100, Math.max(0, formality));
  }
  return args;
}

export async function executeRankOutfits(
  args: RankOutfitsArgs,
  deps: RankOutfitsDeps,
): Promise<Record<string, unknown>> {
  if (args.candidateOutfitIds.length === 0 && args.candidateItemCombinations.length === 0) {
    return { error: "NO_CANDIDATES_PROVIDED" };
  }

  // Resolve saved-outfit candidates to item-id groups first, so both
  // candidate kinds flow through one scoring path.
  const outfitItemIds = args.candidateOutfitIds.length > 0
    ? await deps.listOutfitItemIds(args.candidateOutfitIds)
    : new Map<string, string[]>();

  const candidates: Array<{ ref: string; itemIds: string[] }> = [];
  for (const outfitId of args.candidateOutfitIds) {
    const ids = outfitItemIds.get(outfitId);
    if (ids !== undefined && ids.length > 0) {
      candidates.push({ ref: outfitId, itemIds: ids });
    }
  }
  args.candidateItemCombinations.forEach((ids, index) => {
    candidates.push({ ref: `combination_${index + 1}`, itemIds: ids });
  });
  if (candidates.length === 0) {
    return { error: "ITEM_NOT_FOUND", detail: "No candidate resolved to any owned items." };
  }

  const allItemIds = [...new Set(candidates.flatMap((candidate) => candidate.itemIds))];
  const rows = await deps.listItemsByIds(allItemIds);
  const itemsById = new Map<string, ScorableItem>();
  for (const row of rows) {
    const item = mapClosetItemRowToScorableItem(row);
    if (item !== null) itemsById.set(item.id, item);
  }

  const occasionTitle = args.occasionId !== undefined
    ? await deps.getOccasionTitle(args.occasionId)
    : null;
  const context: ScoringContext = occasionTitle === null ? {} : { targetOccasion: occasionTitle };

  const dropped: string[] = [];
  const ranked: Array<Record<string, unknown>> = [];
  for (const candidate of candidates) {
    const resolved: ScorableItem[] = [];
    let unresolved = false;
    for (const id of candidate.itemIds) {
      const item = itemsById.get(id);
      if (item === undefined) {
        unresolved = true;
        break;
      }
      resolved.push(item);
    }
    if (unresolved) {
      dropped.push(candidate.ref);
      continue;
    }
    const score = scoreOutfit(resolved, context);
    const entry: Record<string, unknown> = {
      outfit_ref: candidate.ref,
      compatibility_score: score.score,
      component_breakdown: breakdownToWire(score),
      unmeasured: [...score.degraded],
    };
    // `target_formality` has no seat in the shared engine (its formality
    // subscore is internal coherence, §2.2), so it is answered as its own
    // measured figure — mean |item formality − target| over the items that
    // carry a score — rather than silently ignored or blended into a score
    // whose formula documents no such term. Omitted (not defaulted) when no
    // item has a measured formality.
    if (args.targetFormality !== undefined) {
      const scored = resolved.filter((item) => item.formalityScore !== null);
      if (scored.length > 0) {
        const distance = scored.reduce(
          (sum, item) => sum + Math.abs((item.formalityScore as number) - args.targetFormality!),
          0,
        ) / scored.length;
        entry["target_formality_distance"] = Math.round(distance);
      }
    }
    ranked.push(entry);
  }

  if (ranked.length === 0) {
    return {
      error: "ITEM_NOT_FOUND",
      detail: "Every candidate referenced at least one item that could not be resolved.",
      dropped_candidates: dropped,
    };
  }

  ranked.sort(
    (a, b) => (b["compatibility_score"] as number) - (a["compatibility_score"] as number),
  );
  return dropped.length > 0 ? { ranked, dropped_candidates: dropped } : { ranked };
}
