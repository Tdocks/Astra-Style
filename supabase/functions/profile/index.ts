// ============================================================================
// profile/index.ts
// ============================================================================
// Deployment entrypoint for the `profile` Edge Function — the grouped
// function serving every spec §14 endpoint whose path starts with
// `profile/`. Supabase routes `/functions/v1/{slug}/...` by the FIRST path
// segment only, so the client's `POST /profile/complete-onboarding` reaches
// a function whose slug is `profile`, which dispatches on the remainder
// itself — see docs/adr/0013-edge-function-routing.md and
// `_shared/routing.ts`.
//
// Routes:
//   POST /complete-onboarding -> handleCompleteOnboarding (handler.ts)
//
// `profile` is the only §14 path segment with exactly one endpoint under it
// today. It is still a grouped function built the same way as `outfits`,
// because ADR 0013's table assigns segments to functions, not endpoints —
// and because a future `GET /profile` or `PATCH /profile` is a route in this
// table rather than a new deploy target.
//
// NOTE ON SERVICE-ROLE: this function never constructs a service-role
// client. Every write it performs is one `authenticated` may already make on
// its own rows (`style_profiles_insert_own`/`_update_own` and siblings,
// `profiles_update_own`), so the caller's own JWT is sufficient and Row
// Level Security stays the boundary. See `_shared/supabaseClient.ts` and
// the `SECURITY INVOKER` rationale in
// supabase/migrations/20260730190000_complete_onboarding_rpc.sql.
//
// NOTE ON GUESTS (ADR 0011): a guest has no `auth.users` row, no profile,
// and no JWT, so this endpoint is unreachable for one — `authenticateRequest`
// rejects the request before any write is attempted. The client never even
// tries: `OnboardingViewModel.submit()` branches on `sessionStore
// .currentIsGuest()` and saves the draft locally instead. That is two
// independent guarantees, which is the right number for a rule that has
// already caused three bugs.
// ============================================================================

import { createUserScopedClient, readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { serverError } from "../_shared/errors.ts";
import { requireIso8601Seconds, toIso8601Seconds } from "../_shared/time.ts";
import { handleCompleteOnboarding, type OnboardingRepository } from "./handler.ts";
import type { ProfileDTO } from "./schema.ts";

// Read once at cold start (per isolate), not per request: a misconfigured
// deploy should fail immediately and visibly.
const env = readEdgeEnv();

// Deliberately tighter than `outfits`' 20/min. Completing onboarding is a
// once-per-account act; the legitimate repeat cases are a retry after a
// dropped connection and a user editing answers and resubmitting, which fit
// comfortably inside this. The write touches four tables, so the cost of
// letting a runaway client loop through is higher than for a read endpoint.
// Same honest caveat as everywhere else: this limiter is per-isolate and
// in-memory, not a security boundary — see `_shared/rateLimit.ts`.
const rateLimiter = createRateLimiter({ limit: 6, windowMs: 60_000 });

/**
 * Maps the `profiles` row the RPC returns onto the wire shape
 * `Domain/Models/Profile.swift` decodes.
 *
 * Written out field by field rather than spread, so a column added to
 * `profiles` later is not silently published to the client, and so every
 * non-Optional Swift property is visibly accounted for. The three timestamps
 * go through `_shared/time.ts` — see that file for why passing Postgres's
 * microsecond precision straight through would break the client's decoder.
 */
function toProfileDTO(row: Record<string, unknown>, now: Date): ProfileDTO {
  const id = row["id"];
  if (typeof id !== "string") {
    throw serverError("Couldn't finish setting up your profile.");
  }
  const asString = (key: string): string | null => {
    const value = row[key];
    return typeof value === "string" ? value : null;
  };
  return {
    id,
    display_name: asString("display_name"),
    avatar_url: asString("avatar_url"),
    location_name: asString("location_name"),
    timezone: asString("timezone"),
    // NOT NULL columns with defaults. Falling back rather than emitting null
    // because these are non-Optional on the Swift side: a null would fail the
    // client's decode outright, which is a worse outcome than a default that
    // matches the column's own.
    units: asString("units") ?? "imperial",
    theme: asString("theme") ?? "system",
    onboarding_completed_at: toIso8601Seconds(row["onboarding_completed_at"]),
    subscription_tier: asString("subscription_tier") ?? "free",
    created_at: requireIso8601Seconds(row["created_at"], now),
    updated_at: requireIso8601Seconds(row["updated_at"], now),
  };
}

function completeOnboardingRoute(req: Request): Promise<Response> {
  // A client scoped to THIS request's caller — never the service-role key.
  // The RPC below is SECURITY INVOKER and reads auth.uid() from this
  // connection's JWT, so the identity that owns the write comes from the
  // token, not from anything in application code.
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  const supabase = createUserScopedClient(env, authorizationHeader);

  const onboardingRepository: OnboardingRepository = {
    async complete(userId, write) {
      // `userId` is accepted for interface symmetry and so the handler test
      // can assert the handler passes the JWT-derived id here. It is
      // deliberately NOT sent to the RPC: `complete_onboarding()` has no
      // user-id parameter, and adding one would create the exact hole this
      // endpoint's ownership requirement is about.
      void userId;

      const { data, error } = await supabase.rpc("complete_onboarding", {
        p_style_profile: write.styleProfile,
        p_body_profile: write.bodyProfile,
        p_lifestyle_profile: write.lifestyleProfile,
      });

      if (error) {
        // The Postgres error text is not forwarded to the client: it can name
        // constraints, columns and values. It is not logged here either —
        // handler.ts logs the category and latency, and Supabase's own
        // Postgres logs hold the detail for anyone debugging with access.
        throw serverError("Couldn't save your answers. Please try again.");
      }

      // A `returns public.profiles` function comes back as a single object
      // through PostgREST's RPC path, but a defensive unwrap costs one line
      // and turns an unexpected array into a clean 500 rather than a
      // confusing partial DTO.
      const row = Array.isArray(data) ? data[0] : data;
      if (row === null || typeof row !== "object") {
        throw serverError("Couldn't finish setting up your profile.");
      }
      return toProfileDTO(row as Record<string, unknown>, new Date());
    },
  };

  return handleCompleteOnboarding(req, {
    authClient: supabase,
    onboardingRepository,
    rateLimiter,
    now: () => new Date(),
  });
}

Deno.serve(createRouter("profile", [
  { method: "POST", pattern: "/complete-onboarding", handler: completeOnboardingRoute },
]));
