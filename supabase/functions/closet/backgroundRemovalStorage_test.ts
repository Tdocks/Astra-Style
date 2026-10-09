import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { createClient } from "@supabase/supabase-js";
import { ProviderError } from "../_shared/providers/types.ts";
import { SupabaseRemovalStorage } from "./backgroundRemovalStorage.ts";
const owner = "11111111-1111-4111-8111-111111111111";
const source = `users/${owner}/closet/22222222-2222-4222-8222-222222222222.jpg`;
const output = source.replace(/\.jpg$/, "-cutout.png");
function fixture(status = 200) {
  const calls: Request[] = [];
  const fetcher: typeof fetch = (input, init) => {
    const request = new Request(input, init);
    calls.push(request);
    if (status !== 200) {
      return Promise.resolve(
        new Response(
          JSON.stringify({
            statusCode: String(status),
            error: "fixture",
            message: "private details",
          }),
          { status, headers: { "Content-Type": "application/json" } },
        ),
      );
    }
    return Promise.resolve(
      request.method === "POST"
        ? new Response('{"Key":"fixture"}', { headers: { "Content-Type": "application/json" } })
        : new Response(new Uint8Array([1, 2]), { headers: { "Content-Type": "image/png" } }),
    );
  };
  const client = createClient("https://fixture.invalid", "fixture-key", {
    global: { fetch: fetcher },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return { storage: new SupabaseRemovalStorage(client, owner), calls };
}
Deno.test("storage rejects foreign paths and malformed input before network", async () => {
  const f = fixture();
  for (
    const path of [
      source.replace(owner, "33333333-3333-4333-8333-333333333333"),
      source + "/../other.jpg",
      "https://other.invalid/photo.jpg",
    ]
  ) {
    await assertRejects(() => f.storage.loadOwned(owner, path), ProviderError);
  }
  await assertRejects(() => f.storage.saveOwned(owner, source, new Uint8Array([1])), ProviderError);
  await assertRejects(() => f.storage.saveOwned(owner, output, new Uint8Array()), ProviderError);
  await assertRejects(() => f.storage.loadOwned("another-owner", source), ProviderError);
  assertEquals(f.calls.length, 0);
});
Deno.test("owned source download and PNG upload use private bucket without overwrite", async () => {
  const f = fixture();
  assertEquals(await f.storage.loadOwned(owner, source), new Uint8Array([1, 2]));
  await f.storage.saveOwned(owner, output, new Uint8Array([1, 2]));
  assertEquals(new URL(f.calls[0]!.url).pathname, `/storage/v1/object/user-content/${source}`);
  assertEquals(f.calls[1]!.headers.get("content-type"), "image/png");
  assertEquals(f.calls[1]!.headers.get("x-upsert"), "false");
});
Deno.test("missing cutout is absent; other storage failures stay bounded", async () => {
  assertEquals(await fixture(404).storage.existsOwned(owner, output), false);
  const error = await assertRejects(
    () => fixture(500).storage.existsOwned(owner, output),
    ProviderError,
  );
  assertEquals(error.message.includes("private details"), false);
});
