// ============================================================================
// _shared/supabaseClient.ts
// ============================================================================
// Spec §15 "Service role": service-role keys exist only in Edge Functions
// and must never reach the client — but that doesn't mean every Edge
// Function should reach for the service-role key by default. This helper
// builds a client scoped to the CALLER's own JWT (the `Authorization`
// header already on the incoming request), so every downstream Postgres
// query — via PostgREST, which is what `supabase-js`'s `.from()` talks to —
// runs AS that user and is constrained by that table's Row Level Security
// policy (`user_id = auth.uid()`, per every `..._select_own`/`..._insert_own`
// policy in `20260728100900_rls_policies.sql`). RLS is the security
// boundary; this client is just how we present the caller's own identity to
// it, instead of substituting the Edge Function's own elevated identity.
//
// A function should reach for the service-role key ONLY when RLS cannot
// express what it needs (e.g. `DELETE /account` touching another user's
// row is never true, but deleting the `auth.users` identity itself requires
// the Auth Admin API, which requires service-role; writing to
// `product_candidates`, a shared catalog table with no `authenticated`
// write policy at all, is another documented exception in
// `20260728100900_rls_policies.sql`). the `outfits` function needs neither: it
// only reads the caller's own `closet_items`, which RLS already allows for
// `authenticated`. See `supabase/functions/README.md` for the project-wide
// policy this comment summarizes.
// ============================================================================

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

export interface EdgeEnv {
  supabaseUrl: string;
  supabaseAnonKey: string;
}

/**
 * Reads the two env vars every Edge Function needs. Supabase automatically
 * injects `SUPABASE_URL` and `SUPABASE_ANON_KEY` for deployed functions and
 * for `supabase functions serve` against a locally running stack — neither
 * needs to be set manually via `supabase secrets set`. Throws (rather than
 * returning `undefined`s silently) so a misconfigured deploy fails loudly
 * at the first request instead of producing confusing downstream errors.
 */
export function readEdgeEnv(): EdgeEnv {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error(
      "SUPABASE_URL and SUPABASE_ANON_KEY must be set. Supabase provides both automatically for deployed Edge Functions and for `supabase functions serve` against a local stack; see supabase/functions/README.md.",
    );
  }
  return { supabaseUrl, supabaseAnonKey };
}

/**
 * Builds a Supabase client that authenticates every downstream request as
 * the caller identified by `authorizationHeader` (the incoming request's
 * own `Authorization` header, forwarded verbatim) — never the service-role
 * key. `persistSession`/`autoRefreshToken` are disabled because an Edge
 * Function instance is not a long-lived per-user session holder; each
 * invocation builds a fresh client for that one request's caller.
 */
export function createUserScopedClient(env: EdgeEnv, authorizationHeader: string): SupabaseClient {
  return createClient(env.supabaseUrl, env.supabaseAnonKey, {
    global: { headers: { Authorization: authorizationHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * Service-role client for the two documented exceptions RLS cannot express:
 * Auth Admin (`account`) and writes to `product_candidates` (no authenticated
 * insert/update policy — P6-SHOP-03 extract + P6-SHOP-08 ingest).
 *
 * `SUPABASE_SERVICE_ROLE_KEY` is injected for deployed functions; never ship
 * it in the iOS target.
 */
export function createServiceRoleClient(env: EdgeEnv): SupabaseClient {
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!key) {
    throw new Error(
      "SUPABASE_SERVICE_ROLE_KEY must be set. Supabase provides it automatically for deployed Edge Functions.",
    );
  }
  return createClient(env.supabaseUrl, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
