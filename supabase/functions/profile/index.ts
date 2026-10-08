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
// Onboarding/export use caller-scoped RLS. Reference-photo erasure is the
// documented service exception: authenticate first, then atomically hide the
// owned photo's entire derivation graph and queue Storage removal (ADR 0026).
//
// NOTE ON GUESTS (ADR 0018): anonymous JWTs are `authenticated`, so this
// endpoint is reachable. Photos still must not hit `user-content` until
// Apple/email link. The old ADR 0011 guest-with-no-JWT path is gone.
// ============================================================================

import {
  createServiceRoleClient,
  createUserScopedClient,
  readEdgeEnv,
} from "../_shared/supabaseClient.ts";
import { handleReferenceDelete, referenceDeletionDeps } from "./referenceDeletion.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { serverError } from "../_shared/errors.ts";
import { handlePersonalDataExport } from "./exportHandler.ts";
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
const exportRateLimiter = createRateLimiter({ limit: 2, windowMs: 60 * 60_000 });

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
    avatar_storage_path: asString("avatar_storage_path"),
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
    wardrobe_graph: asString("wardrobe_graph") ?? "menswear_3_role",
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
        p_wardrobe_graph: write.wardrobeGraph,
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

/**
 * Exports user-owned app data. Every table is read through the incoming
 * caller JWT, then explicitly filtered to the user ID verified by Auth.
 * Page by stable keys so a large wardrobe or conversation history is not
 * silently cut off at PostgREST's row limit. Shared catalog rows are omitted:
 * they are not the user's data and can be fetched again by reference.
 */
function personalDataExportRoute(req: Request): Promise<Response> {
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  const supabase = createUserScopedClient(env, authorizationHeader);

  const tables = [
    { name: "profiles", ownerColumn: "id", orderColumn: "id" },
    { name: "style_profiles", ownerColumn: "user_id", orderColumn: "id" },
    { name: "body_profiles", ownerColumn: "user_id", orderColumn: "id" },
    { name: "lifestyle_profiles", ownerColumn: "user_id", orderColumn: "id" },
    { name: "closet_items", ownerColumn: "user_id", orderColumn: "id" },
    { name: "closet_item_images", ownerColumn: "user_id", orderColumn: "id" },
    { name: "outfits", ownerColumn: "user_id", orderColumn: "id" },
    { name: "outfit_items", ownerColumn: "user_id", orderColumn: "id" },
    { name: "outfit_wears", ownerColumn: "user_id", orderColumn: "id" },
    { name: "kyra_threads", ownerColumn: "user_id", orderColumn: "id" },
    { name: "kyra_messages", ownerColumn: "user_id", orderColumn: "id" },
    { name: "style_feedback", ownerColumn: "user_id", orderColumn: "id" },
    { name: "style_memories", ownerColumn: "user_id", orderColumn: "id" },
    { name: "user_product_evaluations", ownerColumn: "user_id", orderColumn: "id" },
    { name: "occasions", ownerColumn: "user_id", orderColumn: "id" },
    { name: "daily_briefs", ownerColumn: "user_id", orderColumn: "id" },
    { name: "studio_generations", ownerColumn: "user_id", orderColumn: "id" },
    { name: "studio_allowances", ownerColumn: "user_id", orderColumn: "id" },
    { name: "studio_lookbooks", ownerColumn: "user_id", orderColumn: "id" },
    { name: "studio_lookbook_entries", ownerColumn: "user_id", orderColumn: "id" },
    { name: "studio_retention_jobs", ownerColumn: "user_id", orderColumn: "id" },
    { name: "subscriptions", ownerColumn: "user_id", orderColumn: "id" },
    { name: "closet_analysis_jobs", ownerColumn: "user_id", orderColumn: "id" },
    { name: "analytics_events", ownerColumn: "user_id", orderColumn: "id" },
    { name: "lookbook_reports", ownerColumn: "reporter_id", orderColumn: "id" },
    { name: "wear_days", ownerColumn: "user_id", orderColumn: "worn_on" },
    { name: "wishlist_items", ownerColumn: "user_id", orderColumn: "id" },
    {
      name: "wardrobe_score_monthly_snapshots",
      ownerColumn: "user_id",
      orderColumn: "month_start",
    },
  ] as const;

  return handlePersonalDataExport(req, {
    authClient: supabase,
    rateLimiter: exportRateLimiter,
    now: () => new Date(),
    repository: {
      async fetchForUser(userId) {
        const result: Record<string, unknown[]> = {};
        const pageSize = 500;

        for (const table of tables) {
          const rows: unknown[] = [];
          let offset = 0;
          while (true) {
            const { data, error } = await supabase
              .from(table.name)
              .select(
                table.name === "studio_generations"
                  ? "id,user_id,reference_image_path,outfit_id,prompt_payload,status,result_image_path,provider,error_message,deleted_at,created_at,updated_at,allowance_id,retry_of,retention_expires_at"
                  : table.name === "studio_retention_jobs"
                  ? "id,user_id,generation_id,kind,status,attempts,error_message,created_at,completed_at"
                  : "*",
              )
              .eq(table.ownerColumn, userId)
              .order(table.orderColumn, { ascending: true })
              .range(offset, offset + pageSize - 1);
            if (error) {
              throw serverError("Couldn't prepare your data export.");
            }

            const page = data ?? [];
            rows.push(...page);
            if (page.length < pageSize) break;
            offset += page.length;
          }
          result[table.name] = rows;
        }
        return result;
      },
    },
  });
}

Deno.serve(createRouter("profile", [
  { method: "POST", pattern: "/complete-onboarding", handler: completeOnboardingRoute },
  { method: "GET", pattern: "/export-data", handler: personalDataExportRoute },
  {
    method: "DELETE",
    pattern: "/reference-photos",
    handler: (req) => {
      const user = createUserScopedClient(env, req.headers.get("authorization") ?? "");
      return handleReferenceDelete(req, referenceDeletionDeps(user, createServiceRoleClient(env)));
    },
  },
]));
