import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { createClient } from "@supabase/supabase-js";
import { ProviderError } from "../_shared/providers/types.ts";
import { SupabaseRemovalReservations } from "./backgroundRemovalReservations.ts";
function fixture(payload: unknown, status = 200) {
  const calls: { path: string; body: unknown }[] = [];
  const fetcher: typeof fetch = async (input, init) => {
    const request = new Request(input, init);
    calls.push({ path: new URL(request.url).pathname, body: await request.json() });
    return new Response(JSON.stringify(payload), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  };
  const client = createClient("https://fixture.invalid", "fixture-key", {
    global: { fetch: fetcher },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return { reservations: new SupabaseRemovalReservations(client), calls };
}
Deno.test("claim maps durable state and preserves owner/source/key arguments", async () => {
  for (
    const payload of [{ state: "pending" }, { state: "complete", path: "output" }, {
      state: "reserved",
      token: "token",
    }] as const
  ) {
    const f = fixture(payload);
    assertEquals(await f.reservations.claim("owner", "source", "key"), payload);
    assertEquals(f.calls, [{
      path: "/rest/v1/rpc/claim_closet_cutout",
      body: { p_user: "owner", p_source: "source", p_key: "key" },
    }]);
  }
});
Deno.test("dispatch completion failure use durable RPC arguments", async () => {
  const f = fixture(null);
  await f.reservations.beginProvider("token");
  await f.reservations.complete("token", "output");
  await f.reservations.fail("token", true);
  assertEquals(f.calls.map((c) => c.body), [{ p_token: "token" }, {
    p_token: "token",
    p_path: "output",
  }, { p_token: "token", p_attempted: true }]);
});
Deno.test("malformed or failed responses cannot mint a reservation or expose private details", async () => {
  for (
    const payload of [null, { state: "reserved" }, { state: "complete", path: "" }, {
      state: "unknown",
    }]
  ) {
    const f = fixture(payload);
    await assertRejects(() => f.reservations.claim("owner", "source", "key"), ProviderError);
  }
  for (const message of ["cutout_quota_exhausted", "cutout_disabled", "private database detail"]) {
    const f = fixture({ message, code: "P0001" }, 400);
    const error = await assertRejects(() => f.reservations.beginProvider("token"), ProviderError);
    assertEquals(error.retryable, false);
    assertEquals(error.message.includes("private database detail"), false);
  }
});
