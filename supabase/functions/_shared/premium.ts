// ============================================================================
// _shared/premium.ts
// ============================================================================
// Entitlement reads used by Kyra / Studio / morning-loop paywalls (ADR 0009:
// the subscriptions row is truth). Fail closed on read errors.
// ============================================================================

import type { SupabaseClient } from "@supabase/supabase-js";
import { AppError } from "./errors.ts";

const PREMIUM_STATUSES = new Set([
  "trialing",
  "active",
  "in_grace_period",
  "in_billing_retry",
]);

export async function hasActivePremiumSubscription(
  supabase: SupabaseClient,
  nowIso: string,
): Promise<boolean> {
  const { data, error } = await supabase
    .from("subscriptions")
    .select("status, expires_at");
  if (error) return false;
  const rows = (data ?? []) as Array<{ status: string; expires_at: string | null }>;
  return rows.some((row) =>
    PREMIUM_STATUSES.has(row.status) &&
    (row.expires_at === null || row.expires_at > nowIso)
  );
}

export const FREE_WEAR_THIS_COUNT = 7;
export const FREE_DAILY_BRIEF_COUNT = 3;
export const FREE_PASTE_EVALUATE_COUNT = 1;

export function morningLoopQuotaError(message: string): AppError {
  return new AppError("rate_limited", 429, message);
}
