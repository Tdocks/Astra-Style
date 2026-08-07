// ============================================================================
// daily-brief/index.ts
// ============================================================================
// Deployment entrypoint for the `daily-brief` Edge Function — spec §14's
// `POST /daily-brief/generate` (P4-HOME-02). Supabase routes
// `/functions/v1/{slug}/...` by the FIRST path segment only, so the slug is
// `daily-brief` and the router dispatches on the remainder (ADR 0013,
// `_shared/routing.ts`).
//
// Routes:
//   POST /generate -> generateRoute
//
// Thin by design: all request logic is in `handler.ts`, which
// `handler_test.ts` drives with injected doubles and no network. What lives
// here is the Supabase wiring that genuinely needs a live Auth + Postgres
// to exercise.
//
// NOTE ON SERVICE-ROLE: this function never constructs a service-role
// client. Every table it touches — `closet_items`, `occasions`, `outfits`,
// `outfit_items`, `daily_briefs` — has an owner-scoped RLS policy in
// `20260728100900_rls_policies.sql`, so the caller's own JWT is both
// sufficient and the thing that scopes every statement below. Passing a
// different user id in application code would change nothing.
// ============================================================================

import { createUserScopedClient, readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { serverError } from "../_shared/errors.ts";
import {
  type BriefRepository,
  handleGenerateDailyBrief,
  type OutfitDraft,
  type UpsertBriefInput,
} from "./handler.ts";
import type { DailyBriefRow } from "./schema.ts";
import {
  type ClosetItemRow,
  LeastRecentlyWornScorer,
} from "../_shared/scoring/leastRecentlyWorn.ts";

const env = readEdgeEnv();

// Lower than `outfits`' 20/min on purpose: one brief per user per day is
// the entire point of the endpoint, so anything past a handful a minute is
// a retry loop or a bug, and each call can write five rows.
const rateLimiter = createRateLimiter({ limit: 10, windowMs: 60_000 });

const scorer = new LeastRecentlyWornScorer();

const CANDIDATE_ROLES = ["top", "bottom", "shoes"] as const;
const WEARABLE_LAUNDRY_STATES = ["clean", "worn_once"] as const;

const BRIEF_COLUMNS =
  "id, user_id, brief_date, primary_outfit_id, alternative_outfit_ids, weather_snapshot, schedule_snapshot, kyra_message";

function generateRoute(req: Request): Promise<Response> {
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  const supabase = createUserScopedClient(env, authorizationHeader);

  const repository: BriefRepository = {
    async findBrief(userId: string, briefDate: string): Promise<DailyBriefRow | null> {
      void userId; // RLS scopes this, not application code. See header.
      const { data, error } = await supabase
        .from("daily_briefs")
        .select(BRIEF_COLUMNS)
        .eq("brief_date", briefDate)
        .maybeSingle();
      if (error) {
        throw serverError("Couldn't read today's brief.");
      }
      return (data as DailyBriefRow | null) ?? null;
    },

    async listCandidateItems(userId: string): Promise<ClosetItemRow[]> {
      void userId;
      const { data, error } = await supabase
        .from("closet_items")
        .select("id, category, last_worn_at")
        .is("archived_at", null)
        .eq("availability_state", "available")
        .in("laundry_state", WEARABLE_LAUNDRY_STATES)
        .in("category", CANDIDATE_ROLES);
      if (error) {
        throw serverError("Couldn't load your closet.");
      }
      return (data ?? []) as ClosetItemRow[];
    },

    async countOccasions(userId: string, briefDate: string): Promise<number> {
      void userId;
      // Half-open on purpose: `starts_at < next day` rather than `<=`, so an
      // event at midnight belongs to one day only and never to both.
      const { count, error } = await supabase
        .from("occasions")
        .select("id", { count: "exact", head: true })
        .gte("starts_at", `${briefDate}T00:00:00Z`)
        .lt("starts_at", `${nextDay(briefDate)}T00:00:00Z`);
      if (error) {
        throw serverError("Couldn't read your schedule.");
      }
      return count ?? 0;
    },

    async createOutfits(userId: string, drafts: readonly OutfitDraft[]): Promise<string[]> {
      if (drafts.length === 0) {
        return [];
      }
      const { data, error } = await supabase
        .from("outfits")
        .insert(drafts.map((draft) => ({
          user_id: userId,
          name: "Today's Outfit",
          description: draft.reason,
          compatibility_score: draft.compatibilityScore,
          source: "ai_generated",
        })))
        .select("id");
      if (error || !data) {
        throw serverError("Couldn't save today's outfits.");
      }
      const outfitIds = (data as { id: string }[]).map((row) => row.id);

      // `outfit_items` rows are what make an outfit more than a name. A
      // failure here would leave outfits with no garments in them — which
      // reads on Home as a card with nothing on it — so it is surfaced
      // rather than swallowed, and the brief is never written.
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
        throw serverError("Couldn't save today's outfits.");
      }
      return outfitIds;
    },

    async upsertBrief(input: UpsertBriefInput): Promise<DailyBriefRow> {
      // Idempotency, half two. `onConflict` targets the table's own
      // `daily_briefs_one_per_user_per_day` unique constraint, so two
      // requests that both miss the read in `handler.ts` converge on one
      // row rather than one of them failing on the constraint.
      const { data, error } = await supabase
        .from("daily_briefs")
        .upsert({
          user_id: input.userId,
          brief_date: input.briefDate,
          primary_outfit_id: input.primaryOutfitId,
          alternative_outfit_ids: input.alternativeOutfitIds,
          // `?? {}` matches the column's own default (P4-HOME-05): no
          // weather reading is the ordinary case, not an error, and `{}`
          // is what `mapBriefRowToWire` already knows how to turn back
          // into `null` for the client.
          weather_snapshot: input.weatherSnapshot ?? {},
          schedule_snapshot: input.scheduleSnapshot,
        }, { onConflict: "user_id,brief_date" })
        .select(BRIEF_COLUMNS)
        .single();
      if (error || !data) {
        throw serverError("Couldn't save today's brief.");
      }
      return data as DailyBriefRow;
    },
  };

  return handleGenerateDailyBrief(req, {
    authClient: supabase,
    repository,
    scorer,
    rateLimiter,
    now: () => new Date(),
  });
}

/** `YYYY-MM-DD` one day later, in UTC. */
function nextDay(briefDate: string): string {
  const date = new Date(`${briefDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + 1);
  return date.toISOString().slice(0, 10);
}

Deno.serve(createRouter("daily-brief", [
  { method: "POST", pattern: "/generate", handler: generateRoute },
]));
