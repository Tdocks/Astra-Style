// ============================================================================
// subscriptions/index.ts
// ============================================================================
// POST /subscriptions/sync (spec §14, P7-SUB-03 stub). ADR 0013: slug is
// the first path segment. Writes need the service role — RLS allows SELECT
// only for the owner.
//
// Apple Server Notifications V2 are a different slug (`app-store`) and
// are not deployed in this slice.
// ============================================================================

import { createClient } from "@supabase/supabase-js";
import { createUserScopedClient, readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { authenticateRequest } from "../_shared/jwt.ts";
import {
  type AppError,
  errorResponse,
  jsonResponse,
  rateLimited,
  serverError,
} from "../_shared/errors.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { handleSync, mapStoredRow, type SubscriptionStore } from "./handler.ts";
import { parseEnvelope } from "./schema.ts";

const env = readEdgeEnv();

function readServiceRoleKey(): string {
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!key) {
    throw new Error(
      "SUPABASE_SERVICE_ROLE_KEY must be set. Supabase provides it automatically for deployed Edge Functions.",
    );
  }
  return key;
}

const serviceRoleClient = createClient(env.supabaseUrl, readServiceRoleKey(), {
  auth: { persistSession: false, autoRefreshToken: false },
});

const rateLimiter = createRateLimiter({ limit: 20, windowMs: 60_000 });

function serviceStore(): SubscriptionStore {
  return {
    async upsertForUser(row) {
      const { data: existing, error: readError } = await serviceRoleClient
        .from("subscriptions")
        .select("*")
        .eq("user_id", row.userId)
        .maybeSingle();
      if (readError) {
        throw serverError("Couldn't read the subscription row.");
      }
      const payload = {
        user_id: row.userId,
        app_store_original_transaction_id: row.originalTransactionId,
        product_id: row.productId,
        status: row.status,
        expires_at: row.expiresAt,
        environment: row.environment,
        updated_at: new Date().toISOString(),
      };
      if (existing) {
        const { data, error } = await serviceRoleClient
          .from("subscriptions")
          .update(payload)
          .eq("user_id", row.userId)
          .select("*")
          .single();
        if (error || !data) {
          throw serverError("Couldn't update the subscription row.");
        }
        return mapStoredRow(data as Record<string, unknown>);
      }
      const { data, error } = await serviceRoleClient
        .from("subscriptions")
        .insert(payload)
        .select("*")
        .single();
      if (error || !data) {
        throw serverError("Couldn't store the subscription row.");
      }
      return mapStoredRow(data as Record<string, unknown>);
    },
    async fetchForUser(userId) {
      const { data, error } = await serviceRoleClient
        .from("subscriptions")
        .select("*")
        .eq("user_id", userId)
        .maybeSingle();
      if (error) {
        throw serverError("Couldn't load the subscription row.");
      }
      return data ? mapStoredRow(data as Record<string, unknown>) : null;
    },
  };
}

function isAppError(value: unknown): value is AppError {
  return typeof value === "object" && value !== null && "status" in value && "category" in value;
}

async function syncRoute(req: Request): Promise<Response> {
  let requestID = resolveRequestId(req, null);
  try {
    const raw = await req.json().catch(() => ({}));
    const { requestId: bodyRequestID, body } = parseEnvelope(raw);
    requestID = resolveRequestId(req, bodyRequestID ?? null);

    const authorizationHeader = req.headers.get("Authorization") ??
      req.headers.get("authorization") ?? "";
    const userID = await authenticateRequest(
      req,
      createUserScopedClient(env, authorizationHeader),
    );

    const limit = rateLimiter.check(userID, Date.now());
    if (!limit.allowed) {
      return errorResponse(rateLimited(), requestID, {
        "Retry-After": String(limit.retryAfterSeconds),
      });
    }

    const dto = await handleSync(body, userID, {
      store: serviceStore(),
      now: () => new Date(),
    });
    return jsonResponse(dto, { requestId: requestID });
  } catch (error) {
    if (isAppError(error)) return errorResponse(error, requestID);
    return errorResponse(serverError(), requestID);
  }
}

Deno.serve(createRouter("subscriptions", [
  { method: "POST", pattern: "/sync", handler: syncRoute },
]));
