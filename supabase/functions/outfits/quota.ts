import type { SupabaseClient } from "@supabase/supabase-js";
import { AppError, serverError } from "../_shared/errors.ts";
import { isPremiumSubscriptionEntitled } from "../_shared/subscriptionEntitlement.ts";
export type OutfitQuotaDetails = {
  limit: "outfit_generation_daily";
  limit_count: number;
  remaining: number;
  resets_at: string;
};
export class OutfitQuotaExceededError extends AppError {
  constructor(details: OutfitQuotaDetails) {
    super(
      "subscription_limit_reached",
      429,
      "Your free outfit generations for today are used.",
      undefined,
      details,
    );
  }
}
export class OutfitGenerationInFlightError extends AppError {
  constructor() {
    super("server", 409, "This outfit request is still being processed. Try again shortly.");
  }
}

export async function requestFingerprint(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
export function requestUuid(value: string): string {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    ? value
    : crypto.randomUUID();
}

export async function readGenerationPremium(
  client: SupabaseClient,
  userID: string,
  now: Date,
): Promise<boolean> {
  const { data, error } = await client.from("subscriptions").select("status,expires_at").eq(
    "user_id",
    userID,
  );
  if (error) throw serverError("Couldn't check your subscription.");
  return ((data ?? []) as Array<{ status: string; expires_at: string | null }>).some((row) =>
    isPremiumSubscriptionEntitled(row.status, row.expires_at, now)
  );
}

export async function reserveGeneration(
  client: SupabaseClient,
  userID: string,
  requestID: string,
  fingerprint: string,
  now: Date,
) {
  const { data, error } = await client.rpc("reserve_outfit_generation", {
    p_user_id: userID,
    p_request_id: requestID,
    p_fingerprint: fingerprint,
    p_now: now.toISOString(),
  }).single();
  if (error || !data) throw serverError("Couldn't check your generation allowance.");
  const row = data as {
    allowed: boolean;
    remaining: number;
    resets_at: string;
    limit_count: number;
    reservation_id: string | null;
    replay_payload: unknown;
    in_flight: boolean;
  };
  return { ...row, resetsAt: row.resets_at, limitCount: row.limit_count };
}

export async function finishGeneration(
  client: SupabaseClient,
  userID: string,
  reservationID: string,
  succeeded: boolean,
  resultPayload: unknown,
  now: Date,
) {
  const { error } = await client.rpc("finish_outfit_generation", {
    p_user_id: userID,
    p_reservation_id: reservationID,
    p_succeeded: succeeded,
    p_result_payload: resultPayload ?? null,
    p_now: now.toISOString(),
  });
  if (error) throw serverError("Couldn't save the generation allowance result.");
}
