// ============================================================================
// outfits-generate/index.ts
// ============================================================================
// Deployment entrypoint for `POST /outfits/generate`. This file is
// intentionally thin: it wires real Supabase-backed implementations into
// `handleGenerateOutfits`'s `HandlerDeps` and starts the Deno HTTP server.
// All actual request logic lives in `handler.ts`, which is what
// `handler_test.ts` exercises directly with mocked dependencies — this file
// is verified by `deno check` (types) and by running `supabase functions
// serve` + the curl invocation in `supabase/functions/README.md` (a real
// HTTP round trip against a local Supabase stack), not by a Deno unit test,
// since it has no logic of its own beyond wiring and genuinely requires a
// live Supabase Auth + Postgres to exercise meaningfully.
//
// NOTE ON SERVICE-ROLE: this function never constructs a service-role
// client. See `_shared/supabaseClient.ts`'s header comment for why RLS with
// the caller's own JWT is sufficient here (a plain `select` against the
// caller's own `closet_items`, already allowed by
// `closet_items_select_own` in `20260728100900_rls_policies.sql`).
// ============================================================================

import { createUserScopedClient, readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { type ClosetRepository, handleGenerateOutfits } from "./handler.ts";
import { type ClosetItemRow, LeastRecentlyWornScorer } from "./scorer.ts";
import { serverError } from "../_shared/errors.ts";

// Read once at cold start (per isolate), not per request: a misconfigured
// deploy should fail immediately and visibly rather than on the first
// request only.
const env = readEdgeEnv();

// A single limiter instance per isolate — see _shared/rateLimit.ts for why
// this is a best-effort, non-durable limit, not a security boundary.
const rateLimiter = createRateLimiter({ limit: 20, windowMs: 60_000 });

// Stateless; safe to share across requests within this isolate.
const scorer = new LeastRecentlyWornScorer();

const CANDIDATE_ROLES = ["top", "bottom", "shoes"] as const;
const WEARABLE_LAUNDRY_STATES = ["clean", "worn_once"] as const;

Deno.serve(async (req: Request) => {
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

  return await handleGenerateOutfits(req, {
    authClient: supabase,
    closetRepository,
    scorer,
    rateLimiter,
    now: () => new Date(),
  });
});
