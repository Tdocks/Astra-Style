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

import {
  createServiceRoleClient,
  createUserScopedClient,
  readEdgeEnv,
} from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { AppError, serverError } from "../_shared/errors.ts";
import { FREE_DAILY_BRIEF_COUNT, morningLoopQuotaError } from "../_shared/premium.ts";
import { hasActivePremiumSubscription } from "../_shared/premium.ts";
import { type BriefRepository, handleGenerateDailyBrief } from "./handler.ts";
import type { DailyBriefRow } from "./schema.ts";
import {
  CompatibilityOutfitScorer,
  type CompatibilityScorerRow,
} from "../_shared/scoring/compatibilityScorer.ts";
import { parseWardrobeGraph, type WardrobeGraphId } from "../_shared/scoring/wardrobeGraph.ts";

const env = readEdgeEnv();

// Lower than `outfits`' 20/min on purpose: one brief per user per day is
// the entire point of the endpoint, so anything past a handful a minute is
// a retry loop or a bug, and each call can write five rows.
const rateLimiter = createRateLimiter({ limit: 10, windowMs: 60_000 });

// The real §10 engine as of `P4-OUTFIT-07`. `LeastRecentlyWornScorer` was
// `P4-HOME-02`'s deliberate placeholder — least-recently-worn per role, one
// fixed score, one hardcoded sentence — and it is retired here rather than
// deleted, because its tests still document what a scorer must not do.
//
// Constructed without global context because this Edge isolate serves many
// users. The handler converts each request's client-supplied WeatherKit
// snapshot and passes it through `OutfitScorerOptions.context`; requests with
// no measured weather retain §2.5's documented prior. Per-request injection
// also prevents one user's forecast from leaking into the next invocation.
const scorer = new CompatibilityOutfitScorer();

// Widened past the placeholder's three. That scorer could only fill one slot
// per required role, so fetching outerwear was pointless; the real engine
// scores outerwear and accessories through §2.1's pair weights and will use
// them when they help. `roleFor` folds `watch` into `accessory` and drops
// `fragrance`, which has nothing any formula here can read.
// Matches outfits `SCORABLE_CATEGORIES`: dress/skirt feed the women's graph
// beams; menswear simply never selects them into a top+bottom+shoes set.
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
  "id, user_id, brief_date, primary_outfit_id, alternative_outfit_ids, weather_snapshot, schedule_snapshot, kyra_message";

function generateRoute(req: Request): Promise<Response> {
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  const supabase = createUserScopedClient(env, authorizationHeader);
  const service = createServiceRoleClient(env);

  const repository: BriefRepository = {
    async findOperation(userId, requestId, fingerprint): Promise<DailyBriefRow | null> {
      const { data, error } = await service.rpc("get_morning_loop_trial_operation", {
        p_user_id: userId,
        p_feature: "daily_brief",
        p_request_id: requestId,
        p_request_fingerprint: fingerprint,
      });
      if (error) {
        if (error.message.includes("morning_loop_result_deleted")) {
          throw new AppError(
            "validation",
            404,
            "The saved brief was deleted and cannot be restored.",
          );
        }
        if (error.message.includes("morning_loop_request_id_reused")) {
          throw new AppError(
            "validation",
            409,
            "This request ID was already used for a different request.",
          );
        }
        throw serverError("Couldn't recover the saved brief request.");
      }
      if (typeof data !== "object" || data === null) return null;
      const result = data as { status?: unknown; brief?: unknown };
      return typeof result.brief === "object" && result.brief !== null
        ? result.brief as DailyBriefRow
        : null;
    },
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

    async listCandidateItems(userId: string): Promise<CompatibilityScorerRow[]> {
      void userId;
      const { data, error } = await supabase
        .from("closet_items")
        // The whole row, not three fields of it. The placeholder needed `id`,
        // `category` and `last_worn_at` because it looked at a calendar rather
        // than at a garment; the real engine reads colour, formality, fit,
        // materials, seasonality, warmth, water resistance and pattern,
        // because that is what "do these go together" turns out to mean.
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

    async readWardrobeGraph(userId: string): Promise<WardrobeGraphId> {
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

    async finalizeBrief(input, drafts, admission): Promise<DailyBriefRow> {
      const { data, error } = await service.rpc("finalize_daily_brief", {
        p_user_id: input.userId,
        p_request_id: admission.requestId,
        p_request_fingerprint: admission.requestFingerprint,
        p_brief_date: input.briefDate,
        p_regenerate: admission.regenerate,
        p_weather_snapshot: input.weatherSnapshot ?? {},
        p_schedule_snapshot: input.scheduleSnapshot,
        p_requested_weather_snapshot: admission.requestedWeatherSnapshot,
        p_requested_schedule_snapshot: admission.requestedScheduleSnapshot,
        p_drafts: drafts.map((draft) => ({
          reason: draft.reason,
          compatibility_score: draft.compatibilityScore,
          items: draft.itemIds.map((closetItemId, sortOrder) => ({
            closet_item_id: closetItemId,
            role: draft.rolesByItemId.get(closetItemId) ?? "top",
            sort_order: sortOrder,
          })),
        })),
      });
      if (error) {
        if (error.message.includes("morning_loop_result_deleted")) {
          throw new AppError(
            "validation",
            404,
            "The saved brief was deleted and cannot be restored.",
          );
        }
        if (error.message.includes("morning_loop_request_id_reused")) {
          throw new AppError(
            "validation",
            409,
            "This request ID was already used for a different request.",
          );
        }
        throw serverError("Couldn't save today's brief.");
      }
      if (typeof data !== "object" || data === null) {
        throw serverError("Couldn't save today's brief.");
      }
      const result = data as { status?: unknown; brief?: unknown };
      if (result.status === "limit") {
        throw morningLoopQuotaError(
          "daily_brief_trial_generation",
          FREE_DAILY_BRIEF_COUNT,
          0,
          "You've used your free Daily Briefs. Upgrade to Astra Style Premium for a full brief every morning.",
        );
      }
      if (typeof result.brief !== "object" || result.brief === null) {
        throw serverError("Couldn't save today's brief.");
      }
      return result.brief as DailyBriefRow;
    },
  };

  return handleGenerateDailyBrief(req, {
    authClient: supabase,
    repository,
    scorer,
    rateLimiter,
    now: () => new Date(),
    hasActivePremiumSubscription: (userID, nowIso) =>
      hasActivePremiumSubscription(supabase, userID, nowIso),
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
