import { assertEquals } from "@std/assert";
import { createRouter, resolveRoutePath, type Route, type RouteParams } from "./routing.ts";

// ---------------------------------------------------------------------------
// resolveRoutePath — the environment-prefix stripping documented in
// routing.ts's header (deployed/served runtimes pass `/{slug}/{rest}`, a
// forwarding gateway would pass `/functions/v1/{slug}/{rest}`, a
// slug-stripping runtime just `/{rest}`).
// ---------------------------------------------------------------------------

Deno.test("resolveRoutePath strips the slug prefix (deployed/served shape)", () => {
  assertEquals(resolveRoutePath("/outfits/generate", "outfits"), "/generate");
});

Deno.test("resolveRoutePath strips a full /functions/v1/{slug} prefix (gateway shape)", () => {
  assertEquals(resolveRoutePath("/functions/v1/outfits/generate", "outfits"), "/generate");
});

Deno.test("resolveRoutePath leaves an already-stripped path alone", () => {
  assertEquals(resolveRoutePath("/generate", "outfits"), "/generate");
});

Deno.test("resolveRoutePath maps the bare slug to the root path", () => {
  assertEquals(resolveRoutePath("/account", "account"), "/");
  assertEquals(resolveRoutePath("/functions/v1/account", "account"), "/");
  assertEquals(resolveRoutePath("/", "account"), "/");
});

Deno.test("resolveRoutePath tolerates a trailing slash", () => {
  assertEquals(resolveRoutePath("/outfits/generate/", "outfits"), "/generate");
});

Deno.test("resolveRoutePath keeps a multi-segment remainder intact", () => {
  assertEquals(
    resolveRoutePath("/studio/status/550e8400-e29b-41d4-a716-446655440000", "studio"),
    "/status/550e8400-e29b-41d4-a716-446655440000",
  );
});

// A slug that happens to reappear deeper in the path must only be stripped
// once, from the front — `/outfits/outfits` is the route `/outfits` inside
// the `outfits` function, not the root.
Deno.test("resolveRoutePath strips the slug only once, from the front", () => {
  assertEquals(resolveRoutePath("/outfits/outfits", "outfits"), "/outfits");
});

// ---------------------------------------------------------------------------
// createRouter — dispatch, params, and the 404/405/preflight fallthroughs.
// ---------------------------------------------------------------------------

function makeRouter(routes: readonly Route[]): (req: Request) => Promise<Response> {
  return createRouter("outfits", routes);
}

function okRoute(method: string, pattern: string, marker: string): Route {
  return {
    method,
    pattern,
    handler: (_req: Request, params: RouteParams) =>
      new Response(JSON.stringify({ marker, params }), { status: 200 }),
  };
}

async function markerOf(res: Response): Promise<{ marker: string; params: RouteParams }> {
  return await res.json() as { marker: string; params: RouteParams };
}

Deno.test("dispatches to the route matching path and method", async () => {
  const router = makeRouter([
    okRoute("POST", "/generate", "generate"),
    okRoute("POST", "/rank", "rank"),
  ]);
  const res = await router(
    new Request("https://example.supabase.co/outfits/rank", { method: "POST" }),
  );
  assertEquals(res.status, 200);
  assertEquals((await markerOf(res)).marker, "rank");
});

Deno.test("captures and URL-decodes :param segments", async () => {
  const router = createRouter("studio", [okRoute("GET", "/status/:id", "status")]);
  const res = await router(
    new Request("https://example.supabase.co/studio/status/abc%20def", { method: "GET" }),
  );
  assertEquals(res.status, 200);
  assertEquals((await markerOf(res)).params, { id: "abc def" });
});

Deno.test("routes a root pattern for an endpoint at the bare slug", async () => {
  const router = createRouter("account", [okRoute("DELETE", "/", "delete-account")]);
  const res = await router(
    new Request("https://example.supabase.co/account", { method: "DELETE" }),
  );
  assertEquals(res.status, 200);
  assertEquals((await markerOf(res)).marker, "delete-account");
});

Deno.test("returns 404 in the standard envelope for an unknown path", async () => {
  const router = makeRouter([okRoute("POST", "/generate", "generate")]);
  const res = await router(
    new Request("https://example.supabase.co/outfits/nope", {
      method: "POST",
      headers: { "X-Request-Id": "req-404" },
    }),
  );
  assertEquals(res.status, 404);
  const body = await res.json();
  assertEquals(body.data, null);
  assertEquals(body.error.category, "validation");
  assertEquals(body.request_id, "req-404");
});

Deno.test("returns 405, not 404, for a known path with the wrong method", async () => {
  const router = makeRouter([okRoute("POST", "/generate", "generate")]);
  const res = await router(
    new Request("https://example.supabase.co/outfits/generate", { method: "GET" }),
  );
  assertEquals(res.status, 405);
  const body = await res.json();
  assertEquals(body.error.category, "validation");
});

Deno.test("answers CORS preflight 204 for any path, known or not", async () => {
  const router = makeRouter([okRoute("POST", "/generate", "generate")]);
  for (const path of ["/outfits/generate", "/outfits/unknown"]) {
    const res = await router(
      new Request(`https://example.supabase.co${path}`, { method: "OPTIONS" }),
    );
    assertEquals(res.status, 204);
  }
});

Deno.test("does not match a pattern against a path with extra segments", async () => {
  const router = makeRouter([okRoute("POST", "/generate", "generate")]);
  const res = await router(
    new Request("https://example.supabase.co/outfits/generate/extra", { method: "POST" }),
  );
  assertEquals(res.status, 404);
});

Deno.test("wraps a handler that throws into the standard 500 envelope", async () => {
  const router = makeRouter([
    {
      method: "POST",
      pattern: "/generate",
      handler: () => {
        throw new Error("boom with secrets in it");
      },
    },
  ]);
  const res = await router(
    new Request("https://example.supabase.co/outfits/generate", { method: "POST" }),
  );
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error.category, "server");
  // The raw error message must never reach the wire.
  assertEquals(body.error.message, "Internal server error.");
});
