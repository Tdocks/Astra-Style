// ============================================================================
// kyra/store.ts
// ============================================================================
// The Supabase-backed `KyraStore` — every Postgres touch the handler and the
// tools make, in one place, built per-request from the CALLER's own JWT
// (`_shared/supabaseClient.ts`). Row Level Security is the ownership
// boundary throughout: an id the caller does not own resolves to nothing,
// which the handler and tools treat as "not found" rather than substituting
// anything. No service-role client exists in this function; nothing here
// needs one (every table touched has owner policies from
// `20260728100900_rls_policies.sql`).
//
// Like `outfits/index.ts`'s repository, this file is wiring: it is verified
// by `deno check` and by a live `supabase functions serve` round trip, while
// `handler_test.ts` exercises all decision logic against a fake `KyraStore`.
// Query-shape mistakes here fail loudly (every branch throws a typed
// `AppError` on a database error) rather than degrading into fabricated
// rows.
//
// `user_id` params: inserts name the JWT-derived id explicitly (the columns
// are NOT NULL and the `..._insert_own` policies check it); selects rely on
// RLS alone, per the same convention `outfits/index.ts` documents.
// ============================================================================

import type { SupabaseClient } from "@supabase/supabase-js";
import { serverError } from "../_shared/errors.ts";
import type { ClosetItemMapperRow } from "../_shared/scoring/closetItemMapper.ts";
import type { HistoryMessageRow, InsertedMessage, KyraStore } from "./handler.ts";
import type {
  BodyProfileSourceRow,
  FeedbackSourceRow,
  LifestyleProfileSourceRow,
  MemorySourceRow,
  OccasionSourceRow,
  PacketClosetItemRow,
  StyleProfileSourceRow,
} from "./contextPacket.ts";
import type { KyraStructuredResponse, MemoryType } from "./schema.ts";
import type { SearchClosetRow } from "./tools/searchCloset.ts";
import type { NewOutfitRecord } from "./tools/createOutfit.ts";
import type { ExistingMemoryRow } from "./tools/savePreference.ts";

/** Every column `mapClosetItemRowToScorableItem` reads, plus `id` — kept in
 * lockstep with `outfits/index.ts`'s identical list. */
const SCORABLE_COLUMNS = [
  "id",
  "category",
  "primary_color",
  "secondary_colors",
  "pattern",
  "material",
  "fit",
  "seasonality",
  "formality_score",
  "warmth_score",
  "water_resistance_score",
  "laundry_state",
  "availability_state",
  "last_worn_at",
].join(", ");

const PACKET_COLUMNS =
  "id, category, subcategory, brand, primary_color, formality_score, fit, availability_state, " +
  "laundry_state, wear_count, last_worn_at";

/** Subscription states that count as entitled (StoreKit 2's active-ish set). */
const PREMIUM_STATUSES = new Set(["trialing", "active", "in_grace_period", "in_billing_retry"]);

export function buildKyraStore(supabase: SupabaseClient): KyraStore {
  return {
    // -- Threads + messages -------------------------------------------------

    async createThread(userId: string, title: string): Promise<string> {
      const { data, error } = await supabase
        .from("kyra_threads")
        .insert({ user_id: userId, title })
        .select("id")
        .single();
      if (error || data === null) {
        throw serverError("Couldn't start a new conversation.");
      }
      return (data as { id: string }).id;
    },

    async threadExists(threadId: string): Promise<boolean> {
      const { data, error } = await supabase
        .from("kyra_threads")
        .select("id")
        .eq("id", threadId)
        .maybeSingle();
      if (error) {
        throw serverError("Couldn't load that conversation.");
      }
      return data !== null;
    },

    async countThreadsCreatedSince(userId: string, sinceIso: string): Promise<number> {
      // RLS already scopes to the caller; the explicit eq is defense in
      // depth for the one query that gates billing-relevant access.
      const { count, error } = await supabase
        .from("kyra_threads")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .gte("created_at", sinceIso);
      if (error || count === null) {
        throw serverError("Couldn't check today's conversation count.");
      }
      return count;
    },

    async insertUserMessage(
      userId: string,
      threadId: string,
      content: string,
    ): Promise<InsertedMessage> {
      const { data, error } = await supabase
        .from("kyra_messages")
        .insert({ thread_id: threadId, user_id: userId, role: "user", content })
        .select("id, created_at")
        .single();
      if (error || data === null) {
        throw serverError("Couldn't record your message.");
      }
      const row = data as { id: string; created_at: string };
      return { id: row.id, createdAt: row.created_at };
    },

    async insertAssistantMessage(
      userId: string,
      threadId: string,
      content: string,
      structuredPayload: KyraStructuredResponse,
      modelMetadata: Record<string, unknown>,
    ): Promise<InsertedMessage> {
      const { data, error } = await supabase
        .from("kyra_messages")
        .insert({
          thread_id: threadId,
          user_id: userId,
          role: "assistant",
          content,
          structured_payload: structuredPayload,
          model_metadata: modelMetadata,
        })
        .select("id, created_at")
        .single();
      if (error || data === null) {
        throw serverError("Couldn't save Kyra's reply.");
      }
      const row = data as { id: string; created_at: string };
      return { id: row.id, createdAt: row.created_at };
    },

    async listRecentMessages(threadId: string, limit: number): Promise<HistoryMessageRow[]> {
      const { data, error } = await supabase
        .from("kyra_messages")
        .select("role, content, structured_payload, created_at")
        .eq("thread_id", threadId)
        .order("created_at", { ascending: false })
        .limit(limit);
      if (error) {
        throw serverError("Couldn't load the conversation history.");
      }
      // Fetched newest-first for the LIMIT, replayed oldest-first.
      return ((data ?? []) as unknown as HistoryMessageRow[]).reverse();
    },

    // -- Subscription tier (P5-KYRA-19) -------------------------------------

    async hasActivePremiumSubscription(nowIso: string): Promise<boolean> {
      const { data, error } = await supabase
        .from("subscriptions")
        .select("status, expires_at");
      if (error) {
        // Failing OPEN would hand out unlimited conversations on every
        // subscriptions-table blip; failing CLOSED (treat as free) keeps the
        // documented free allowance working. Free tier still gets its three.
        return false;
      }
      const rows = (data ?? []) as Array<{ status: string; expires_at: string | null }>;
      return rows.some((row) =>
        PREMIUM_STATUSES.has(row.status) &&
        (row.expires_at === null || row.expires_at > nowIso)
      );
    },

    // -- Context-packet sources ---------------------------------------------

    async loadStyleProfile(): Promise<StyleProfileSourceRow | null> {
      const { data, error } = await supabase
        .from("style_profiles")
        .select(
          "primary_identity, secondary_identities, preferred_colors, avoided_colors, " +
            "preferred_fit, formality_preference, logo_tolerance, trend_tolerance",
        )
        .maybeSingle();
      if (error) {
        throw serverError("Couldn't load the style profile.");
      }
      return data as unknown as StyleProfileSourceRow | null;
    },

    async loadBodyProfile(): Promise<BodyProfileSourceRow | null> {
      const { data, error } = await supabase
        .from("body_profiles")
        .select("fit_notes, shirt_size, trouser_size, shoe_size")
        .maybeSingle();
      if (error) {
        throw serverError("Couldn't load the body profile.");
      }
      return data as unknown as BodyProfileSourceRow | null;
    },

    async loadLifestyleProfile(): Promise<LifestyleProfileSourceRow | null> {
      const { data, error } = await supabase
        .from("lifestyle_profiles")
        .select("monthly_budget, currency, sustainability_preference")
        .maybeSingle();
      if (error) {
        throw serverError("Couldn't load the lifestyle profile.");
      }
      return data as unknown as LifestyleProfileSourceRow | null;
    },

    async listUpcomingOccasions(fromIso: string, toIso: string): Promise<OccasionSourceRow[]> {
      const { data, error } = await supabase
        .from("occasions")
        .select("id, title, starts_at, dress_code, location")
        .gte("starts_at", fromIso)
        .lte("starts_at", toIso)
        .order("starts_at", { ascending: true });
      if (error) {
        throw serverError("Couldn't load upcoming occasions.");
      }
      return (data ?? []) as unknown as OccasionSourceRow[];
    },

    async listPacketClosetItems(): Promise<PacketClosetItemRow[]> {
      const { data, error } = await supabase
        .from("closet_items")
        .select(PACKET_COLUMNS)
        .is("archived_at", null);
      if (error) {
        throw serverError("Couldn't load the closet.");
      }
      return (data ?? []) as unknown as PacketClosetItemRow[];
    },

    async listRecentFeedback(limit: number): Promise<FeedbackSourceRow[]> {
      const { data, error } = await supabase
        .from("style_feedback")
        .select("target_type, target_id, signal, reason_tags, created_at")
        .order("created_at", { ascending: false })
        .limit(limit);
      if (error) {
        throw serverError("Couldn't load recent feedback.");
      }
      return (data ?? []) as unknown as FeedbackSourceRow[];
    },

    async listVisibleMemories(minConfidence: number): Promise<MemorySourceRow[]> {
      const { data, error } = await supabase
        .from("style_memories")
        .select("id, memory_type, content, confidence")
        .eq("is_user_visible", true)
        .gte("confidence", minConfidence);
      if (error) {
        throw serverError("Couldn't load style memories.");
      }
      return (data ?? []) as unknown as MemorySourceRow[];
    },

    // -- Tool backends -------------------------------------------------------

    async listClosetItems(): Promise<SearchClosetRow[]> {
      const { data, error } = await supabase
        .from("closet_items")
        .select(PACKET_COLUMNS)
        .is("archived_at", null);
      if (error) {
        throw serverError("Couldn't search the closet.");
      }
      return (data ?? []) as unknown as SearchClosetRow[];
    },

    async listItemsByIds(ids: readonly string[]): Promise<ClosetItemMapperRow[]> {
      if (ids.length === 0) return [];
      const { data, error } = await supabase
        .from("closet_items")
        .select(SCORABLE_COLUMNS)
        .is("archived_at", null)
        .in("id", ids);
      if (error) {
        throw serverError("Couldn't load those closet items.");
      }
      return (data ?? []) as unknown as ClosetItemMapperRow[];
    },

    async listOutfitItemIds(
      outfitIds: readonly string[],
    ): Promise<ReadonlyMap<string, string[]>> {
      if (outfitIds.length === 0) return new Map();
      const { data, error } = await supabase
        .from("outfit_items")
        .select("outfit_id, closet_item_id")
        .in("outfit_id", outfitIds)
        .not("closet_item_id", "is", null)
        .order("sort_order", { ascending: true });
      if (error) {
        throw serverError("Couldn't load those outfits.");
      }
      const map = new Map<string, string[]>();
      for (const row of (data ?? []) as Array<{ outfit_id: string; closet_item_id: string }>) {
        const existing = map.get(row.outfit_id) ?? [];
        existing.push(row.closet_item_id);
        map.set(row.outfit_id, existing);
      }
      return map;
    },

    async getOccasionTitle(occasionId: string): Promise<string | null> {
      const { data, error } = await supabase
        .from("occasions")
        .select("title")
        .eq("id", occasionId)
        .maybeSingle();
      if (error || data === null) {
        return null;
      }
      return (data as { title: string }).title;
    },

    async insertOutfit(userId: string, record: NewOutfitRecord): Promise<string> {
      const { data, error } = await supabase
        .from("outfits")
        .insert({
          user_id: userId,
          name: record.name,
          description: record.description,
          occasion_tags: record.occasionTags,
          compatibility_score: record.compatibilityScore,
          source: record.source,
        })
        .select("id")
        .single();
      if (error || data === null) {
        throw serverError("Couldn't save the outfit.");
      }
      const outfitId = (data as { id: string }).id;

      const { error: itemsError } = await supabase
        .from("outfit_items")
        .insert(record.items.map((item) => ({
          outfit_id: outfitId,
          user_id: userId,
          closet_item_id: item.closetItemId,
          product_candidate_id: item.productCandidateId,
          role: item.role,
          sort_order: item.sortOrder,
        })));
      if (itemsError) {
        // A headless outfit row is a lie waiting to be ranked; best-effort
        // cleanup, then fail the tool call honestly.
        await supabase.from("outfits").delete().eq("id", outfitId);
        throw serverError("Couldn't save the outfit's items.");
      }
      return outfitId;
    },

    async listOwnedItemIds(ids: readonly string[]): Promise<string[]> {
      if (ids.length === 0) return [];
      const { data, error } = await supabase
        .from("closet_items")
        .select("id")
        .is("archived_at", null)
        .in("id", ids);
      if (error) {
        throw serverError("Couldn't verify those closet items.");
      }
      return ((data ?? []) as Array<{ id: string }>).map((row) => row.id);
    },

    async getOutfitItemIds(outfitId: string): Promise<string[] | null> {
      const { data, error } = await supabase
        .from("outfits")
        .select("id")
        .eq("id", outfitId)
        .maybeSingle();
      if (error) {
        throw serverError("Couldn't load that outfit.");
      }
      if (data === null) return null;
      const { data: items, error: itemsError } = await supabase
        .from("outfit_items")
        .select("closet_item_id")
        .eq("outfit_id", outfitId)
        .not("closet_item_id", "is", null);
      if (itemsError) {
        throw serverError("Couldn't load that outfit's items.");
      }
      return ((items ?? []) as Array<{ closet_item_id: string }>).map(
        (row) => row.closet_item_id,
      );
    },

    async insertWornOutfit(
      userId: string,
      itemIds: readonly string[],
      wornDate: string,
    ): Promise<string> {
      // Roles come from the items' real categories; `outfit_items.role` is
      // NOT NULL and guessing would misfile the slot.
      const { data: rows, error: rowsError } = await supabase
        .from("closet_items")
        .select("id, category")
        .in("id", itemIds);
      if (rowsError) {
        throw serverError("Couldn't load those closet items.");
      }
      const categoryById = new Map(
        ((rows ?? []) as Array<{ id: string; category: string }>).map(
          (row) => [row.id, row.category],
        ),
      );

      const { data, error } = await supabase
        .from("outfits")
        .insert({
          user_id: userId,
          name: `Worn ${wornDate}`,
          // The user asserting what they wore is user-authored fact.
          source: "user_created",
        })
        .select("id")
        .single();
      if (error || data === null) {
        throw serverError("Couldn't record what you wore.");
      }
      const outfitId = (data as { id: string }).id;

      const { error: itemsError } = await supabase
        .from("outfit_items")
        .insert(itemIds.map((itemId, index) => ({
          outfit_id: outfitId,
          user_id: userId,
          closet_item_id: itemId,
          role: categoryById.get(itemId) ?? "accessory",
          sort_order: index,
        })));
      if (itemsError) {
        await supabase.from("outfits").delete().eq("id", outfitId);
        throw serverError("Couldn't record what you wore.");
      }
      return outfitId;
    },

    async findWearOnDate(
      outfitId: string,
      wornDate: string,
    ): Promise<{ id: string } | null> {
      const dayStart = `${wornDate}T00:00:00Z`;
      const dayEnd = `${wornDate}T23:59:59.999Z`;
      const { data, error } = await supabase
        .from("outfit_wears")
        .select("id")
        .eq("outfit_id", outfitId)
        .gte("worn_at", dayStart)
        .lte("worn_at", dayEnd)
        .limit(1)
        .maybeSingle();
      if (error) {
        throw serverError("Couldn't check the wear history.");
      }
      return data as { id: string } | null;
    },

    async insertWear(
      userId: string,
      record: { outfitId: string; wornAtIso: string; occasion: string | null },
    ): Promise<string> {
      const { data, error } = await supabase
        .from("outfit_wears")
        .insert({
          outfit_id: record.outfitId,
          user_id: userId,
          worn_at: record.wornAtIso,
          occasion: record.occasion,
        })
        .select("id")
        .single();
      if (error || data === null) {
        throw serverError("Couldn't record the wear.");
      }
      return (data as { id: string }).id;
    },

    async readWearCounts(itemIds: readonly string[]): Promise<ReadonlyMap<string, number>> {
      if (itemIds.length === 0) return new Map();
      const { data, error } = await supabase
        .from("closet_items")
        .select("id, wear_count")
        .in("id", itemIds);
      if (error) {
        throw serverError("Couldn't read wear counts.");
      }
      return new Map(
        ((data ?? []) as Array<{ id: string; wear_count: number }>).map(
          (row) => [row.id, row.wear_count],
        ),
      );
    },

    async listMemoriesByType(memoryType: MemoryType): Promise<ExistingMemoryRow[]> {
      const { data, error } = await supabase
        .from("style_memories")
        .select("id, memory_type, content, confidence")
        .eq("memory_type", memoryType);
      if (error) {
        throw serverError("Couldn't load existing memories.");
      }
      return (data ?? []) as unknown as ExistingMemoryRow[];
    },

    async insertMemory(
      userId: string,
      record: {
        memoryType: MemoryType;
        content: string;
        confidence: number;
        sourceMessageId: string;
      },
    ): Promise<string> {
      const { data, error } = await supabase
        .from("style_memories")
        .insert({
          user_id: userId,
          memory_type: record.memoryType,
          content: record.content,
          confidence: record.confidence,
          source_message_id: record.sourceMessageId,
          // §5.4: no hidden memory tier — visible by construction.
          is_user_visible: true,
        })
        .select("id")
        .single();
      if (error || data === null) {
        throw serverError("Couldn't save that preference.");
      }
      return (data as { id: string }).id;
    },

    async updateMemoryConfidence(memoryId: string, confidence: number): Promise<void> {
      const { error } = await supabase
        .from("style_memories")
        .update({ confidence })
        .eq("id", memoryId);
      if (error) {
        throw serverError("Couldn't update that preference.");
      }
    },

    async deleteMemory(memoryId: string): Promise<void> {
      const { error } = await supabase
        .from("style_memories")
        .delete()
        .eq("id", memoryId);
      if (error) {
        throw serverError("Couldn't replace that preference.");
      }
    },
  };
}
