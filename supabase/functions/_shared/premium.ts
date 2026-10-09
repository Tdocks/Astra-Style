// ============================================================================
// _shared/premium.ts
// ============================================================================
// Entitlement reads used by Kyra / Studio / morning-loop paywalls (ADR 0009:
// the subscriptions row is truth). Fail closed on read errors.
// ============================================================================

import type { SupabaseClient } from "@supabase/supabase-js";
import { AppError } from "./errors.ts";
import { isPremiumSubscriptionEntitled } from "./subscriptionEntitlement.ts";

export async function hasActivePremiumSubscription(
  supabase: SupabaseClient,
  userID: string,
  nowIso: string,
): Promise<boolean> {
  const { data, error } = await supabase
    .from("subscriptions")
    .select("status, expires_at")
    .eq("user_id", userID);
  if (error) return false;
  const rows = (data ?? []) as Array<{ status: string; expires_at: string | null }>;
  return rows.some((row) => isPremiumSubscriptionEntitled(row.status, row.expires_at, nowIso));
}

// These are lifetime trials from the existing server contract, not daily
// traffic limits. Subscription-limit responses therefore carry resets_at:null.
export const FREE_DAILY_BRIEF_COUNT = 3;
export const FREE_PASTE_EVALUATE_COUNT = 1;

export type MorningLoopQuotaLimit =
  | "daily_brief_trial_generation"
  | "paste_product_evaluation_trial";

export function morningLoopQuotaError(
  limit: MorningLoopQuotaLimit,
  limitCount: number,
  remaining: number,
  message: string,
): AppError {
  return new AppError("subscription_limit_reached", 429, message, undefined, {
    limit,
    limit_count: limitCount,
    remaining,
    resets_at: null,
  });
}
