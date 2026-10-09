import { assertEquals } from "@std/assert";
import { isPremiumSubscriptionEntitled } from "./subscriptionEntitlement.ts";

Deno.test("only trial, active and grace rows without or with future expiry are Premium", () => {
  const now = new Date("2026-10-09T12:00:00.000Z");
  for (const status of ["trialing", "active", "in_grace_period"]) {
    assertEquals(isPremiumSubscriptionEntitled(status, null, now), true, status);
    assertEquals(
      isPremiumSubscriptionEntitled(status, "2026-10-09T12:00:01Z", now),
      true,
      `${status} with a future expiration`,
    );
  }
  for (const status of ["cancelled", "expired", "revoked", "in_billing_retry"]) {
    assertEquals(isPremiumSubscriptionEntitled(status, null, now), false, status);
    assertEquals(
      isPremiumSubscriptionEntitled(status, "2027-01-01T00:00:00Z", now),
      false,
      `${status} cannot be revived by a future expiration`,
    );
  }
});

Deno.test("expiration must parse and be strictly later than the supplied instant", () => {
  const now = "2026-10-09T12:00:00.000Z";
  assertEquals(isPremiumSubscriptionEntitled("active", "not-a-date", now), false);
  assertEquals(isPremiumSubscriptionEntitled("active", "2026-10-09T12:00:00Z", now), false);
  assertEquals(isPremiumSubscriptionEntitled("active", "2026-10-09T13:00:00+02:00", now), false);
  assertEquals(isPremiumSubscriptionEntitled("active", "2026-10-09T15:00:00+02:00", now), true);
  assertEquals(isPremiumSubscriptionEntitled("active", null, "invalid-now"), false);
});
