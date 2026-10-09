import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { fallbackBackgroundRemoval, type RemovalClaim } from "./backgroundRemoval.ts";
const userId = "11111111-1111-4111-8111-111111111111";
const source = `users/${userId}/closet/22222222-2222-4222-8222-222222222222.jpg`;
const output = source.replace(/\.jpg$/, "-cutout.png");
const ctx = { userId, requestId: "fixture", timeoutMs: 1000, idempotencyKey: "fixture" };
function fixture(claim: RemovalClaim = { state: "reserved", token: "reservation" }) {
  const events: string[] = [];
  const deps = {
    storage: {
      loadOwned: (_owner: string, _path: string) => {
        events.push("load");
        return Promise.resolve(new Uint8Array([1]));
      },
      saveOwned: (_owner: string, path: string, _bytes: Uint8Array) => {
        events.push(`save:${path}`);
        return Promise.resolve();
      },
      existsOwned: (_owner: string, _path: string) => {
        events.push("exists");
        return Promise.resolve(true);
      },
    },
    reservations: {
      claim: (_owner: string, _source: string, _key: string) => {
        events.push("claim");
        return Promise.resolve(claim);
      },
      beginProvider: (_token: string) => {
        events.push("begin");
        return Promise.resolve();
      },
      complete: (_token: string, _path: string) => {
        events.push("complete");
        return Promise.resolve();
      },
      fail: (_token: string, attempted: boolean) => {
        events.push(`fail:${attempted}`);
        return Promise.resolve();
      },
    },
    provider: {
      remove: () => {
        events.push("provider");
        return Promise.resolve(new Uint8Array([2]));
      },
    },
  };
  return { deps, events };
}
Deno.test("adequate device cutout skips all fallback work", async () => {
  const f = fixture();
  assertEquals(await fallbackBackgroundRemoval(source, true, ctx, f.deps), null);
  assertEquals(f.events, []);
});
Deno.test("foreign and malformed captures fail before storage or vendor access", async () => {
  for (
    const path of [
      source.replace(userId, "33333333-3333-4333-8333-333333333333"),
      source + "/../other.jpg",
      source.replace(".jpg", ".png"),
    ]
  ) {
    const f = fixture();
    await assertRejects(() => fallbackBackgroundRemoval(path, false, ctx, f.deps));
    assertEquals(f.events, []);
  }
});
Deno.test("completed and pending claims never call the provider", async () => {
  for (
    const claim of [{ state: "complete", path: output }, { state: "pending" }] as RemovalClaim[]
  ) {
    const f = fixture(claim);
    assertEquals(
      await fallbackBackgroundRemoval(source, false, ctx, f.deps),
      claim.state === "complete" ? output : null,
    );
    assertEquals(f.events.includes("provider"), false);
  }
});
Deno.test("reservation dispatch precedes vendor and owned output completion", async () => {
  const f = fixture();
  assertEquals(await fallbackBackgroundRemoval(source, false, ctx, f.deps), output);
  assertEquals(f.events, ["load", "claim", "begin", "provider", `save:${output}`, "complete"]);
});
Deno.test("lost dispatch-marker response cannot release a chargeable retry", async () => {
  const f = fixture();
  f.deps.reservations.beginProvider = () => Promise.reject(new Error("response lost"));
  await assertRejects(() => fallbackBackgroundRemoval(source, false, ctx, f.deps));
  assertEquals(f.events, ["load", "claim", "fail:true"]);
});
Deno.test("missing and empty captures consume no reservation", async () => {
  for (const missing of [true, false]) {
    const f = fixture();
    f.deps.storage.loadOwned = () =>
      missing ? Promise.reject(new Error("missing")) : Promise.resolve(new Uint8Array());
    await assertRejects(() => fallbackBackgroundRemoval(source, false, ctx, f.deps));
    assertEquals(f.events, []);
  }
});
