/** Server interpretation shared by paid-feature gates (ADR 0009). */
const PREMIUM_STATUSES = new Set(["trialing", "active", "in_grace_period"]);

export function isPremiumSubscriptionEntitled(
  status: string,
  expiresAt: string | null,
  now: Date | string,
): boolean {
  if (!PREMIUM_STATUSES.has(status)) return false;
  const instant = typeof now === "string" ? Date.parse(now) : now.getTime();
  if (!Number.isFinite(instant)) return false;
  if (expiresAt === null) return true;

  const expiration = Date.parse(expiresAt);
  return Number.isFinite(expiration) && expiration > instant;
}
