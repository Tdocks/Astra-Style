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
