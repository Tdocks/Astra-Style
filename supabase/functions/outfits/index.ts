// ============================================================================
// outfits/index.ts
// ============================================================================
// Deployment entrypoint for the `outfits` Edge Function — the grouped
// function serving every spec §14 endpoint whose path starts with
// `outfits/`. Supabase routes `/functions/v1/{slug}/...` by the FIRST path
// segment only, so `POST /outfits/generate` and `POST /outfits/rank` must
// be one deployed function (slug `outfits`) that dispatches on the path
// remainder itself — see docs/adr/0013-edge-function-routing.md and
// `_shared/routing.ts` for the full rationale.
//
// Routes:
//   POST /generate  -> handleGenerateOutfits (handler.ts), backed by the
//                      real §2 CompatibilityScorer via candidateGeneration.ts
//   POST /rank      -> handleRankOutfits (handler.ts)
//
// This file is intentionally thin: it wires real Supabase-backed
// implementations into `HandlerDeps` and starts the Deno HTTP server. All
// actual request logic lives in `handler.ts`, which is what
// `handler_test.ts` exercises directly with mocked dependencies — this file
// is verified by `deno check` (types), by `_shared/routing_test.ts` (the
// dispatch behavior it delegates to), and by running
// `supabase functions serve` + the curl invocation in
// `supabase/functions/README.md` (a real HTTP round trip against a local
// Supabase stack), since its remaining logic is wiring that genuinely
// requires a live Supabase Auth + Postgres to exercise meaningfully.
//
// NOTE ON SERVICE-ROLE: this function never constructs a service-role
// client. See `_shared/supabaseClient.ts`'s header comment for why RLS with
// the caller's own JWT is sufficient here (a plain `select` against the
// caller's own `closet_items`, already allowed by
// `closet_items_select_own` in `20260728100900_rls_policies.sql`).
// ============================================================================

import { createUserScopedClient, readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { type ClosetRepository, handleGenerateOutfits, handleRankOutfits } from "./handler.ts";
import type { ClosetItemMapperRow } from "../_shared/scoring/closetItemMapper.ts";
import { serverError } from "../_shared/errors.ts";

// Read once at cold start (per isolate), not per request: a misconfigured
// deploy should fail immediately and visibly rather than on the first
// request only.
const env = readEdgeEnv();

// A single limiter instance per isolate — see _shared/rateLimit.ts for why
// this is a best-effort, non-durable limit, not a security boundary. Shared
// across every route in this function on purpose: the limit protects the
// isolate (and the user's provider budget), not any one endpoint.
const rateLimiter = createRateLimiter({ limit: 20, windowMs: 60_000 });

/**
 * Every category §2's formulas can read something from — everything except
 * `fragrance` (`roleFor`'s header: no colour, silhouette or formality
 * signal exists for it). Filtering it out here, at the query, means the
 * mapper's own fragrance -> null behavior (`closetItemMapper.ts`) never
 * has to run for rows that could never survive it anyway.
 */
const SCORABLE_CATEGORIES = [
  "top",
  "bottom",
  "outerwear",
  "shoes",
  "accessory",
  "watch",
] as const;
const WEARABLE_LAUNDRY_STATES = ["clean", "worn_once"] as const;

/** Every `closet_items` column `mapClosetItemRowToScorableItem` reads, plus `id`. */
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
].join(", ");

function buildClosetRepository(authorizationHeader: string): ClosetRepository {
  const supabase = createUserScopedClient(env, authorizationHeader);

  return {
    async listCandidateItems(userId: string): Promise<ClosetItemMapperRow[]> {
      // `userId` is accepted for interface symmetry and so a future RPC
      // could use it, but it is deliberately NOT used to filter this query
      // — Row Level Security (`closet_items_select_own`,
      // `user_id = auth.uid()`) is what scopes this to the caller's own
      // rows, driven by the JWT already attached to `supabase` above.
      void userId;

      // Pre-filtered here for query efficiency (no point transferring a
      // dirty shirt across the wire), AND `generateCandidateOutfits` still
      // calls `wearableItems()` explicitly on whatever it receives — see
      // that module's header on why the filter belongs in code, not just
      // in a query a future caller could forget to add.
      const { data, error } = await supabase
        .from("closet_items")
        .select(SCORABLE_COLUMNS)
        .is("archived_at", null)
        .eq("availability_state", "available")
        .in("laundry_state", WEARABLE_LAUNDRY_STATES)
        .in("category", SCORABLE_CATEGORIES);

      if (error) {
        throw serverError("Couldn't load your closet.");
      }
      // `SCORABLE_COLUMNS` is a dynamic string, so the untyped Supabase
      // client (no generated schema types in this project — see
      // `_shared/supabaseClient.ts`) cannot statically shape-check the
      // result; the runtime shape is exactly `ClosetItemMapperRow` because
      // that column list IS this file's `select()`, kept in one place
      // rather than duplicated as a literal for the type-checker's benefit.
      return (data ?? []) as unknown as ClosetItemMapperRow[];
    },

    async listItemsByIds(userId: string, ids: readonly string[]): Promise<ClosetItemMapperRow[]> {
      void userId; // RLS scopes this, not application code — see above.
      if (ids.length === 0) {
        return [];
      }
      // Deliberately NOT filtered by availability/laundry state — see
      // `handleRankOutfits`'s header on why `/rank` scores exactly the
      // items a candidate names, wearable or not. An archived (soft-deleted)
      // item is excluded, the same as everywhere else in this codebase.
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
  };
}

function generateOutfitsRoute(req: Request): Promise<Response> {
  // Build a Supabase client scoped to THIS request's caller — never the
  // service-role key. If the Authorization header is missing/malformed,
  // this client simply won't authenticate as anyone; `handleGenerateOutfits`
  // catches that via `authenticateRequest()` and returns 401, it does not
  // fall back to any elevated identity.
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";

  return handleGenerateOutfits(req, {
    authClient: createUserScopedClient(env, authorizationHeader),
    closetRepository: buildClosetRepository(authorizationHeader),
    rateLimiter,
    now: () => new Date(),
  });
}

function rankOutfitsRoute(req: Request): Promise<Response> {
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";

  return handleRankOutfits(req, {
    authClient: createUserScopedClient(env, authorizationHeader),
    closetRepository: buildClosetRepository(authorizationHeader),
    rateLimiter,
    now: () => new Date(),
  });
}

Deno.serve(createRouter("outfits", [
  { method: "POST", pattern: "/generate", handler: generateOutfitsRoute },
  { method: "POST", pattern: "/rank", handler: rankOutfitsRoute },
]));
