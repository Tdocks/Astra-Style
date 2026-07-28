// ============================================================================
// _shared/cors.ts
// ============================================================================
// The native iOS client never sends an `Origin` header, so CORS is not load
// bearing for it. This exists for two real, non-hypothetical callers:
//   1. `supabase functions serve` invoked from a browser (Supabase Studio's
//      "Invoke" button, or manual local testing) — Studio runs on its own
//      origin.
//   2. Any future internal web tooling (admin dashboard, etc.) hitting the
//      same Edge Functions.
//
// `*` is used for the vertical slice because there is no web app origin to
// pin to yet and every request still requires a valid Supabase JWT (CORS is
// not a substitute for authentication). Before a real web client is
// introduced, replace `*` with an explicit allow-list read from an env var.
// ============================================================================

export const CORS_HEADERS: Readonly<Record<string, string>> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info, x-request-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * Returns a 204 preflight response if `req` is a CORS preflight `OPTIONS`
 * request, or `null` if the caller should continue handling `req` normally.
 */
export function handleCorsPreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  return null;
}
