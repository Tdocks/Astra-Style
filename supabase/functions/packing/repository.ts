// ============================================================================
// packing/repository.ts
// ============================================================================
// JWT-scoped packing store. Used by `packing/index.ts` and Kyra's store so
// the Edge Function and the tool share one query shape. RLS only — no
// service role.
// ============================================================================

import type { SupabaseClient } from "@supabase/supabase-js";
import { serverError } from "../_shared/errors.ts";
import type { CompatibilityScorerRow } from "../_shared/scoring/compatibilityScorer.ts";
import {
  parseWardrobeGraph,
  type WardrobeGraphId,
} from "../_shared/scoring/wardrobeGraph.ts";
import type { BriefRow, OccasionRow, OutfitDraft, PackingRepository } from "./plan.ts";

const CANDIDATE_ROLES = [
  "top",
  "bottom",
  "shoes",
  "outerwear",
  "accessory",
  "watch",
  "dress",
  "skirt",
] as const;
const WEARABLE_LAUNDRY_STATES = ["clean", "worn_once"] as const;
const BRIEF_COLUMNS =
  "id, user_id, brief_date, primary_outfit_id, alternative_outfit_ids, schedule_snapshot";

export function createPackingRepository(supabase: SupabaseClient): PackingRepository {
  return {
    async listCandidateItems(userId) {
      void userId;
      const { data, error } = await supabase
        .from("closet_items")
        .select(
          "id, category, subcategory, primary_color, secondary_colors, pattern, material, " +
            "fit, seasonality, formality_score, warmth_score, water_resistance_score, " +
            "laundry_state, availability_state, last_worn_at",
        )
        .is("archived_at", null)
        .eq("availability_state", "available")
        .in("laundry_state", WEARABLE_LAUNDRY_STATES)
        .in("category", CANDIDATE_ROLES);
      if (error) {
        throw serverError("Couldn't load your closet.");
      }
      return (data ?? []) as unknown as CompatibilityScorerRow[];
    },

    async readWardrobeGraph(userId): Promise<WardrobeGraphId> {
      void userId;
      const { data, error } = await supabase
        .from("profiles")
        .select("wardrobe_graph")
        .maybeSingle();
      if (error) return "menswear_3_role";
      const value = data && typeof data === "object"
        ? (data as { wardrobe_graph?: unknown }).wardrobe_graph
        : undefined;
      return parseWardrobeGraph(value);
    },

    async listOccasions(userId, fromDate, toExclusive) {
      void userId;
      const { data, error } = await supabase
        .from("occasions")
        .select("starts_at, title, dress_code")
        .gte("starts_at", `${fromDate}T00:00:00Z`)
        .lt("starts_at", `${toExclusive}T00:00:00Z`)
        .order("starts_at", { ascending: true });
      if (error) {
        throw serverError("Couldn't read your schedule.");
      }
      return (data ?? []) as OccasionRow[];
    },

    async findBriefs(userId, dates) {
      void userId;
      if (dates.length === 0) return [];
      const { data, error } = await supabase
        .from("daily_briefs")
        .select(BRIEF_COLUMNS)
        .in("brief_date", [...dates]);
      if (error) {
        throw serverError("Couldn't read this week's looks.");
      }
      return (data ?? []) as BriefRow[];
    },

    async createOutfits(userId, drafts: readonly OutfitDraft[]) {
      if (drafts.length === 0) return [];
      const { data, error } = await supabase
        .from("outfits")
        .insert(drafts.map((draft) => ({
          user_id: userId,
          name: draft.name,
          description: draft.reason,
          compatibility_score: draft.compatibilityScore,
          source: "ai_generated",
        })))
        .select("id");
      if (error || !data) {
        throw serverError("Couldn't save those looks.");
      }
      const outfitIds = (data as { id: string }[]).map((row) => row.id);
      const itemRows = drafts.flatMap((draft, draftIndex) =>
        draft.itemIds.map((closetItemId, sortOrder) => ({
          outfit_id: outfitIds[draftIndex],
          user_id: userId,
          closet_item_id: closetItemId,
          role: draft.rolesByItemId.get(closetItemId) ?? "top",
          sort_order: sortOrder,
          is_required: true,
        }))
      );
      const { error: itemsError } = await supabase.from("outfit_items").insert(itemRows);
      if (itemsError) {
        throw serverError("Couldn't save those looks.");
      }
      return outfitIds;
    },

    async upsertBrief(input) {
      const { data, error } = await supabase
        .from("daily_briefs")
        .upsert({
          user_id: input.userId,
          brief_date: input.briefDate,
          primary_outfit_id: input.primaryOutfitId,
          alternative_outfit_ids: input.alternativeOutfitIds,
          schedule_snapshot: input.scheduleSnapshot,
        }, { onConflict: "user_id,brief_date" })
        .select(BRIEF_COLUMNS)
        .single();
      if (error || !data) {
        throw serverError("Couldn't save this week's looks.");
      }
      return data as BriefRow;
    },

    async listOutfitItemIds(outfitIds) {
      if (outfitIds.length === 0) return [];
      const { data, error } = await supabase
        .from("outfit_items")
        .select("closet_item_id")
        .in("outfit_id", [...outfitIds]);
      if (error) {
        throw serverError("Couldn't load the packing list.");
      }
      const ids = (data ?? [])
        .map((row) => (row as { closet_item_id: string | null }).closet_item_id)
        .filter((id): id is string => typeof id === "string");
      return [...new Set(ids)];
    },
  };
}
