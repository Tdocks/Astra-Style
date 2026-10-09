import { assertEquals } from "jsr:@std/assert@1";
import { handleBackgroundRemoval } from "./backgroundRemovalHandler.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import type { ProviderRequestContext } from "../_shared/providers/types.ts";
const owner = "11111111-1111-4111-8111-111111111111";
const source = `users/${owner}/closet/22222222-2222-4222-8222-222222222222.jpg`;
function fixture(anonymous = false, enabled = true) {
  const calls: ProviderRequestContext[] = [];
  const deps = {
    authClient: {
      auth: {
        getUser: () =>
          Promise.resolve({ data: { user: { id: owner, is_anonymous: anonymous } }, error: null }),
      },
    },
    rateLimiter: createRateLimiter({ limit: 30, windowMs: 60_000 }),
    enabled,
    run: (_source: string, _adequate: boolean, ctx: ProviderRequestContext) => {
      calls.push(ctx);
      return Promise.resolve(source.replace(/\.jpg$/, "-cutout.png"));
    },
  };
  return { calls, deps };
}
function request(
  body: unknown = { storage_path: source, device_adequate: false },
  headers: Record<string, string> = {},
) {
  return new Request("https://fixture.invalid/closet/remove-background", {
    method: "POST",
    headers: {
      Authorization: "Bearer fixture.valid.token",
      "Idempotency-Key": "fixture",
      ...headers,
    },
    body: JSON.stringify({ body }),
  });
}
Deno.test("cutout endpoint derives owner from verified auth and returns no-store path", async () => {
  const f = fixture();
  const response = await handleBackgroundRemoval(
    request({ storage_path: source, device_adequate: false, user_id: "spoof" }),
    f.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  assertEquals(f.calls[0]?.userId, owner);
  assertEquals(f.calls[0]?.idempotencyKey, "fixture");
  assertEquals(
    (await response.json()).data.background_removed_path,
    source.replace(/\.jpg$/, "-cutout.png"),
  );
});
Deno.test("guest and unauthenticated calls never invoke processing", async () => {
  const guest = fixture(true);
  assertEquals((await handleBackgroundRemoval(request(), guest.deps)).status, 403);
  assertEquals(guest.calls.length, 0);
  const f = fixture();
  assertEquals(
    (await handleBackgroundRemoval(request(undefined, { Authorization: "" }), f.deps)).status,
    401,
  );
  assertEquals(f.calls.length, 0);
});
Deno.test("foreign paths malformed bodies and missing keys never invoke processing", async () => {
  for (
    const body of [null, [], { storage_path: source, device_adequate: "false" }, {
      storage_path: source.replace(owner, "33333333-3333-4333-8333-333333333333"),
      device_adequate: false,
    }]
  ) {
    const f = fixture();
    assertEquals((await handleBackgroundRemoval(request(body), f.deps)).status, 400);
    assertEquals(f.calls.length, 0);
  }
  const f = fixture();
  assertEquals(
    (await handleBackgroundRemoval(request(undefined, { "Idempotency-Key": "" }), f.deps)).status,
    400,
  );
  assertEquals(f.calls.length, 0);
});
Deno.test("adequate device cutouts and disabled fallback invoke no processing", async () => {
  const f = fixture(false, false);
  assertEquals(
    (await handleBackgroundRemoval(
      request({ storage_path: source, device_adequate: true }),
      f.deps,
    )).status,
    200,
  );
  assertEquals((await handleBackgroundRemoval(request(), f.deps)).status, 503);
  assertEquals(f.calls.length, 0);
});
Deno.test("oversized requests are rejected before processing", async () => {
  const f = fixture();
  assertEquals(
    (await handleBackgroundRemoval(
      request({ storage_path: source, device_adequate: false, extra: "x".repeat(20_000) }),
      f.deps,
    )).status,
    400,
  );
  assertEquals(f.calls.length, 0);
});

Deno.test("rate-limited cutout requests return the exact Retry-After reset", async () => {
  const f = fixture();
  f.deps.rateLimiter = { check: () => ({ allowed: false, remaining: 0, retryAfterSeconds: 23 }) };
  const response = await handleBackgroundRemoval(request(), f.deps);
  assertEquals(response.status, 429);
  assertEquals(response.headers.get("Retry-After"), "23");
  assertEquals(f.calls.length, 0);
});
