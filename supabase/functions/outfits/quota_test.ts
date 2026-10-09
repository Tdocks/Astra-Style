import { assertEquals } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { isPremiumSubscriptionEntitled } from "../_shared/subscriptionEntitlement.ts";
import { readGenerationPremium, requestFingerprint, requestUuid } from "./quota.ts";

function premiumClient(status: string, expiresAt: string | null, fail = false) {
  const filters: Array<[string, unknown]> = [];
  const client = {
    from(table: string) {
      assertEquals(table, "subscriptions");
      const builder = {
        select() {
          return builder;
        },
        eq(key: string, value: unknown) {
          filters.push([key, value]);
          return builder;
        },
        then(resolve: (result: unknown) => unknown) {
          return Promise.resolve({
            data: fail ? null : [{ status, expires_at: expiresAt }],
            error: fail ? new Error("offline") : null,
          }).then(resolve);
        },
      };
      return builder;
    },
  };
  return { client: client as unknown as SupabaseClient, filters };
}

Deno.test("premium generation entitlement is owner-scoped and expires at the server clock", async () => {
  const now = new Date("2026-10-09T12:00:00Z");
  const active = premiumClient("active", "2026-10-09T12:00:01Z");
  assertEquals(await readGenerationPremium(active.client, "verified-owner", now), true);
  assertEquals(active.filters, [["user_id", "verified-owner"]]);
  for (
    const [status, expiry] of [["active", "2026-10-09T12:00:00Z"], ["expired", null], [
      "revoked",
      null,
    ]] as const
  ) {
    const client = premiumClient(status, expiry);
    assertEquals(await readGenerationPremium(client.client, "owner", now), false);
  }
});

Deno.test("trial, active and grace statuses bypass the free limit but billing retry does not", async () => {
  for (const status of ["trialing", "active", "in_grace_period"]) {
    const client = premiumClient(status, null);
    assertEquals(
      await readGenerationPremium(client.client, "owner", new Date("2026-10-09T12:00:00Z")),
      true,
    );
  }
  const billingRetry = premiumClient("in_billing_retry", null);
  assertEquals(
    await readGenerationPremium(billingRetry.client, "owner", new Date("2026-10-09T12:00:00Z")),
    false,
  );
});

Deno.test("shared entitlement policy parses expiry timestamps and rejects malformed or expired rows", () => {
  const now = "2026-10-09T12:00:00.000Z";
  assertEquals(isPremiumSubscriptionEntitled("active", "2026-10-09T14:00:00+02:00", now), false);
  assertEquals(isPremiumSubscriptionEntitled("active", "2026-10-09T12:00:00Z", now), false);
  assertEquals(isPremiumSubscriptionEntitled("active", "not-a-date", now), false);
  assertEquals(isPremiumSubscriptionEntitled("active", null, now), true);
  assertEquals(isPremiumSubscriptionEntitled("cancelled", null, now), false);
  assertEquals(isPremiumSubscriptionEntitled("in_billing_retry", null, now), false);
});

Deno.test("subscription lookup errors fail closed instead of granting unlimited generation", async () => {
  const client = premiumClient("active", null, true);
  let threw = false;
  try {
    await readGenerationPremium(client.client, "owner", new Date());
  } catch {
    threw = true;
  }
  assertEquals(threw, true);
});

Deno.test("request fingerprint and retry UUID are stable for replay but invalid IDs are replaced", async () => {
  assertEquals(
    await requestFingerprint({ a: 1, b: "x" }),
    await requestFingerprint({ a: 1, b: "x" }),
  );
  const uuid = "11111111-1111-4111-8111-111111111111";
  assertEquals(requestUuid(uuid), uuid);
  assertEquals(requestUuid("attacker supplied arbitrary key").length, 36);
});
