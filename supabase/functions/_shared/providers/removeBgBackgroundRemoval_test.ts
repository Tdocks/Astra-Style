import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { RemoveBgBackgroundRemovalProvider } from "./removeBgBackgroundRemoval.ts";
import { ProviderError } from "./types.ts";
const ctx = {
  userId: "test-owner",
  requestId: "test-request",
  timeoutMs: 1000,
  idempotencyKey: "test-reservation",
};
const png = Uint8Array.from(
  atob(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==",
  ),
  (c) => c.charCodeAt(0),
);
Deno.test("adapter sends bytes to fixed vendor host and requests transparent PNG without cropping", async () => {
  const fetcher: typeof fetch = (_url, init) => {
    assertEquals(_url, "https://api.remove.bg/v1.0/removebg");
    assertEquals(init?.redirect, "error");
    const form = init?.body as FormData;
    assertEquals(form.get("format"), "png");
    assertEquals(form.get("crop"), "false");
    assert(form.get("image_file") instanceof Blob);
    return Promise.resolve(new Response(png, { headers: { "Content-Type": "image/png" } }));
  };
  const result = await new RemoveBgBackgroundRemovalProvider("fixture-key", fetcher).remove(
    new Uint8Array([1, 2, 3]),
    ctx,
  );
  assertEquals(result, png);
});
Deno.test("unconfigured and unreserved requests never call vendor", async () => {
  let calls = 0;
  const fetcher: typeof fetch = () => {
    calls++;
    return Promise.resolve(new Response());
  };
  await assertRejects(
    () => new RemoveBgBackgroundRemovalProvider("", fetcher).remove(png, ctx),
    ProviderError,
  );
  await assertRejects(
    () =>
      new RemoveBgBackgroundRemovalProvider("fixture-key", fetcher).remove(png, {
        ...ctx,
        idempotencyKey: undefined,
      }),
    ProviderError,
  );
  assertEquals(calls, 0);
});
Deno.test("vendor errors stay bounded and classify billing/auth/rate failures", async () => {
  for (
    const [status, code] of [[401, "AUTH_FAILED"], [402, "PROVIDER_QUOTA_EXCEEDED"], [
      429,
      "RATE_LIMITED",
    ], [503, "PROVIDER_UNAVAILABLE"]] as const
  ) {
    const fetcher: typeof fetch = () =>
      Promise.resolve(new Response("vendor private detail", { status }));
    const error = await assertRejects(
      () => new RemoveBgBackgroundRemovalProvider("fixture-key", fetcher).remove(png, ctx),
      ProviderError,
    );
    assertEquals(error.code, code);
    assert(!error.message.includes("vendor private detail"));
  }
});
Deno.test("invalid response type or missing alpha format is rejected", async () => {
  const opaque = new Uint8Array(png);
  opaque[25] = 2;
  for (
    const response of [
      new Response("not an image", { headers: { "Content-Type": "text/plain" } }),
      new Response(opaque, { headers: { "Content-Type": "image/png" } }),
    ]
  ) {
    await assertRejects(
      () =>
        new RemoveBgBackgroundRemovalProvider("fixture-key", () => Promise.resolve(response))
          .remove(png, ctx),
      ProviderError,
    );
  }
});

Deno.test("truncated or oversized-dimension PNGs cannot be saved as cutouts", async () => {
  const huge = new Uint8Array(png);
  new DataView(huge.buffer).setUint32(16, 30_000_000);
  const empty = new Uint8Array(png);
  new DataView(empty.buffer).setUint32(20, 0);
  for (const bytes of [png.slice(0, 33), png.slice(0, png.length - 1), huge, empty]) {
    const fetcher: typeof fetch = () =>
      Promise.resolve(new Response(bytes, { headers: { "Content-Type": "image/png" } }));
    await assertRejects(
      () => new RemoveBgBackgroundRemovalProvider("fixture-key", fetcher).remove(png, ctx),
      ProviderError,
    );
  }
});
Deno.test("timeout aborts a pending provider request without exposing vendor data", async () => {
  const fetcher: typeof fetch = (_url, init) =>
    new Promise((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(new Error("private detail")), {
        once: true,
      });
    });
  const error = await assertRejects(
    () =>
      new RemoveBgBackgroundRemovalProvider("fixture-key", fetcher).remove(png, {
        ...ctx,
        timeoutMs: 5,
      }),
    ProviderError,
  );
  assertEquals(error.code, "TIMEOUT");
  assert(!error.message.includes("private detail"));
});
