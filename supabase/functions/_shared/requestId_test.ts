import { assertEquals, assertMatch } from "@std/assert";
import { resolveRequestId } from "./requestId.ts";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.test("prefers the X-Request-Id header when present", () => {
  const req = new Request("https://example.com", { headers: { "X-Request-Id": "from-header" } });
  assertEquals(resolveRequestId(req, "from-body"), "from-header");
});

Deno.test("falls back to the body-supplied request id when no header is present", () => {
  const req = new Request("https://example.com");
  assertEquals(resolveRequestId(req, "from-body"), "from-body");
});

Deno.test("generates a fresh id when neither header nor body value is present", () => {
  const req = new Request("https://example.com");
  const id = resolveRequestId(req, undefined);
  assertMatch(id, UUID_PATTERN);
});

Deno.test("treats a blank header as absent and falls through to the body value", () => {
  const req = new Request("https://example.com", { headers: { "X-Request-Id": "   " } });
  assertEquals(resolveRequestId(req, "from-body"), "from-body");
});
