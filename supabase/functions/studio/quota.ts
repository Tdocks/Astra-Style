import type { SupabaseClient } from "@supabase/supabase-js";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import { CORS_HEADERS, handleCorsPreflight } from "../_shared/cors.ts";
import {
  AppError,
  errorResponse,
  jsonResponse,
  methodNotAllowed,
  serverError,
} from "../_shared/errors.ts";
import { resolveRequestId } from "../_shared/requestId.ts";

export function quotaPeriod(now: Date): { start: string; reset: string } {
  return {
    start: new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString(),
    reset: new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1)).toISOString(),
  };
}

export async function readQuota(client: SupabaseClient, userID: string, now: Date) {
  const { data: subscriptions, error: subscriptionError } = await client.from("subscriptions")
    .select("status,expires_at").eq("user_id", userID);
  if (subscriptionError) throw serverError("Couldn't load your preview allowance.");
  const premium = (subscriptions ?? []).some((s) =>
    ["trialing", "active", "in_grace_period", "in_billing_retry"].includes(s.status) &&
    (s.expires_at === null || Date.parse(s.expires_at) > now.getTime())
  );
  const period = quotaPeriod(now);
  let limit = 1;
  if (premium) {
    const { data, error } = await client.from("studio_quota_config")
      .select("premium_monthly_limit").eq("singleton", true).single();
    if (error || !data) throw serverError("Couldn't load your preview allowance.");
    limit = data.premium_monthly_limit;
  }
  let query = client.from("studio_allowances").select("id", { count: "exact", head: true })
    .eq("user_id", userID).is("released_at", null);
  if (premium) query = query.gte("created_at", period.start).lt("created_at", period.reset);
  const { count, error } = await query;
  if (error || count === null) throw serverError("Couldn't load your preview allowance.");
  return {
    premium,
    limit,
    used: count,
    remaining: Math.max(0, limit - count),
    resets_at: premium ? period.reset : null,
  };
}

export async function handleQuota(
  req: Request,
  authClient: AuthClient,
  read: (userID: string) => Promise<unknown>,
): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  const requestId = resolveRequestId(req);
  try {
    if (req.method !== "GET") throw methodNotAllowed();
    const userID = await authenticateRequest(req, authClient);
    return jsonResponse(await read(userID), {
      requestId,
      extraHeaders: { ...CORS_HEADERS, "Cache-Control": "no-store" },
    });
  } catch (error) {
    return errorResponse(
      error instanceof AppError ? error : serverError("Couldn't load your preview allowance."),
      requestId,
      CORS_HEADERS,
    );
  }
}
