// ============================================================================
// _shared/jwt.ts
// ============================================================================
// Spec §14 "Validate JWT" + the task's explicit security requirement: JWT
// validation must verify the token against Supabase Auth and derive the
// user id from *that*, never from anything the client sent in the request
// body. This module is the only place a user id is allowed to originate
// from in this codebase.
//
// How verification works: the caller passes an `AuthClient` — in
// production, a `supabase-js` client constructed with the caller's own
// bearer token already attached as the `Authorization` header (see
// `_shared/supabaseClient.ts`). Calling `auth.getUser()` on that client
// makes a real network call to Supabase Auth (GoTrue)'s `/auth/v1/user`
// endpoint, which verifies the JWT's signature and expiry server-side and
// returns the identity Supabase itself associates with that token. This
// project deliberately does NOT hand-roll JWT signature verification
// (parsing the JWT secret, checking `exp`/`nbf` locally, etc.) — Supabase
// Auth is the source of truth for whether a token is valid, and asking it
// directly avoids an entire class of "our local verification logic drifted
// from GoTrue's" bugs.
//
// `AuthClient` is intentionally a minimal structural interface (not the
// full `SupabaseClient` type) so tests can inject a plain object mock with
// no network access and no real Supabase project, per the task's
// "mock the Supabase client at the boundary" requirement.
// ============================================================================

import { unauthorized } from "./errors.ts";

export interface AuthUser {
  id: string;
}

export interface AuthClient {
  auth: {
    getUser(
      jwt?: string,
    ): Promise<{ data: { user: AuthUser | null }; error: { message: string } | null }>;
  };
}

const BEARER_RE = /^Bearer\s+(.+)$/i;

/** Cheap structural check so obviously-malformed tokens never reach a network call. */
function looksLikeJwt(token: string): boolean {
  const segments = token.split(".");
  return segments.length === 3 && segments.every((segment) => segment.length > 0);
}

/**
 * Validates the request's `Authorization: Bearer <jwt>` header against
 * Supabase Auth and returns the verified user id.
 *
 * Throws an `AppError` (category "auth", HTTP 401) for:
 *   - a missing Authorization header,
 *   - a header that isn't `Bearer <token>`,
 *   - a token that isn't structurally a JWT (not three dot-separated,
 *     non-empty segments) — rejected without a network round trip,
 *   - a structurally-valid-looking token that Supabase Auth itself rejects
 *     (expired, wrong signature, revoked, malformed claims, etc).
 */
export async function authenticateRequest(req: Request, authClient: AuthClient): Promise<string> {
  const header = req.headers.get("authorization") ?? req.headers.get("Authorization");
  if (!header) {
    throw unauthorized("Missing Authorization header.");
  }

  const match = BEARER_RE.exec(header.trim());
  if (!match) {
    throw unauthorized("Authorization header must be a Bearer token.");
  }

  const token = match[1]?.trim() ?? "";
  if (token.length === 0 || !looksLikeJwt(token)) {
    throw unauthorized("Malformed access token.");
  }

  const { data, error } = await authClient.auth.getUser(token);
  if (error || !data.user) {
    throw unauthorized("Invalid or expired access token.");
  }

  return data.user.id;
}
