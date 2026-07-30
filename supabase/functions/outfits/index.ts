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
//   POST /generate  -> handleGenerateOutfits (handler.ts)
//   POST /rank      -> not built yet (Phase 4, P4-OUTFIT-08); until it is,
//                      the router's own 404 answers it like any unknown
//                      path, in the standard error envelope.
//
// This file is intentionally thin: it wires real Supabase-backed
// implementations into `handleGenerateOutfits`'s `HandlerDeps` and starts
// the Deno HTTP server. All actual request logic lives in `handler.ts`,
// which is what `handler_test.ts` exercises directly with mocked
// dependencies — this file is verified by `deno check` (types), by
// `_shared/routing_test.ts` (the dispatch behavior it delegates to), and by
// running `supabase functions serve` + the curl invocation in
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
import { type ClosetRepository, handleGenerateOutfits } from "./handler.ts";
import { type ClosetItemRow, LeastRecentlyWornScorer } from "./scorer.ts";
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

// Stateless; safe to share across requests within this isolate.
const scorer = new LeastRecentlyWornScorer();

const CANDIDATE_ROLES = ["top", "bottom", "shoes"] as const;
const WEARABLE_LAUNDRY_STATES = ["clean", "worn_once"] as const;

function generateOutfitsRoute(req: Request): Promise<Response> {
  // Build a Supabase client scoped to THIS request's caller — never the
  // service-role key. If the Authorization header is missing/malformed,
  // this client simply won't authenticate as anyone; `handleGenerateOutfits`
  // catches that via `authenticateRequest()` and returns 401, it does not
  // fall back to any elevated identity.
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  const supabase = createUserScopedClient(env, authorizationHeader);

  const closetRepository: ClosetRepository = {
    async listCandidateItems(userId: string): Promise<ClosetItemRow[]> {
      // `userId` is accepted for interface symmetry with `ClosetRepository`
      // and so a future implementation could use it in an RPC argument, but
      // it is deliberately NOT used to filter this query — Row Level
      // Security (`closet_items_select_own`, `user_id = auth.uid()`) is
      // what scopes this to the caller's own rows, driven by the JWT
      // already attached to `supabase` above, not by anything in
      // application code. Passing a *different* `userId` here would change
      // nothing, which is the point.
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
  };

  return handleGenerateOutfits(req, {
    authClient: supabase,
    closetRepository,
    scorer,
    rateLimiter,
    now: () => new Date(),
  });
}

Deno.serve(createRouter("outfits", [
  { method: "POST", pattern: "/generate", handler: generateOutfitsRoute },
]));
