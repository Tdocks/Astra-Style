import { assertEquals } from "@std/assert";
import { handleQuota, quotaPeriod } from "./quota.ts";
Deno.test("quota periods use UTC and cross December", () => {
  assertEquals(quotaPeriod(new Date("2026-12-31T23:59:59Z")), {
    start: "2026-12-01T00:00:00.000Z",
    reset: "2027-01-01T00:00:00.000Z",
  });
  assertEquals(
    quotaPeriod(new Date("2026-03-01T00:30:00+02:00")).start,
    "2026-02-01T00:00:00.000Z",
  );
});
Deno.test("quota ignores requested owner and uses verified identity", async () => {
  const auth = {
    auth: {
      getUser: () => Promise.resolve({ data: { user: { id: "verified-owner" } }, error: null }),
    },
  };
  const response = await handleQuota(
    new Request("https://fixture/studio/quota?user_id=peer", {
      headers: { authorization: "Bearer fixture.token.signature" },
    }),
    auth,
    (id) => {
      assertEquals(id, "verified-owner");
      return Promise.resolve({ remaining: 2 });
    },
  );
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("cache-control"), "no-store");
});
Deno.test("quota missing session never reads privileged data", async () => {
  const auth = { auth: { getUser: () => Promise.resolve({ data: { user: null }, error: null }) } };
  const response = await handleQuota(new Request("https://fixture/studio/quota"), auth, () => {
    throw new Error("unexpected read");
  });
  assertEquals(response.status, 401);
});

import type { SupabaseClient } from "@supabase/supabase-js";
import { readQuota } from "./quota.ts";

function quotaClient(status: string, expires: string | null, used: number) {
  const filters: Array<[string, string, unknown]> = [];
  const client = {
    from(table: string) {
      const result = table === "subscriptions"
        ? { data: [{ status, expires_at: expires }], error: null }
        : table === "studio_quota_config"
        ? { data: { premium_monthly_limit: 20 }, error: null }
        : { count: used, error: null };
      const builder = {
        select() {
          return builder;
        },
        eq(key: string, value: unknown) {
          filters.push([table, key, value]);
          return builder;
        },
        is(key: string, value: unknown) {
          filters.push([table, key, value]);
          return builder;
        },
        gte(key: string, value: unknown) {
          filters.push([table, "gte:" + key, value]);
          return builder;
        },
        lt(key: string, value: unknown) {
          filters.push([table, "lt:" + key, value]);
          return builder;
        },
        single() {
          return Promise.resolve(result);
        },
        then(resolve: (value: unknown) => unknown) {
          return Promise.resolve(result).then(resolve);
        },
      };
      return builder;
    },
  };
  return { client: client as unknown as SupabaseClient, filters };
}

Deno.test("premium summary applies owner, active-only and month filters and clamps remaining", async () => {
  const { client, filters } = quotaClient("active", "2027-01-01T00:00:00Z", 25);
  assertEquals(await readQuota(client, "owner", new Date("2026-10-08T10:00:00Z")), {
    premium: true,
    limit: 20,
    used: 25,
    remaining: 0,
    resets_at: "2026-11-01T00:00:00.000Z",
  });
  assertEquals(filters, [
    ["subscriptions", "user_id", "owner"],
    ["studio_quota_config", "singleton", true],
    ["studio_allowances", "user_id", "owner"],
    ["studio_allowances", "released_at", null],
    ["studio_allowances", "gte:created_at", "2026-10-01T00:00:00.000Z"],
    ["studio_allowances", "lt:created_at", "2026-11-01T00:00:00.000Z"],
  ]);
});
Deno.test("expired or revoked subscription uses lifetime free allowance with no reset", async () => {
  for (const [status, expiry] of [["active", "2026-10-08T10:00:00Z"], ["revoked", null]] as const) {
    const { client, filters } = quotaClient(status, expiry, 1);
    assertEquals(await readQuota(client, "owner", new Date("2026-10-08T10:00:00Z")), {
      premium: false,
      limit: 1,
      used: 1,
      remaining: 0,
      resets_at: null,
    });
    assertEquals(filters.length, 3);
  }
});
