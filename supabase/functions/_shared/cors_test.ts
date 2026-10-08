import { assertEquals, assertStrictEquals } from "@std/assert";
import { CORS_HEADERS, handleCorsPreflight } from "./cors.ts";

Deno.test("handleCorsPreflight returns a 204 for OPTIONS requests", () => {
  const req = new Request("https://example.com/outfits/generate", { method: "OPTIONS" });
  const response = handleCorsPreflight(req);
  assertEquals(response?.status, 204);
  assertEquals(
    response?.headers.get("Access-Control-Allow-Origin"),
    CORS_HEADERS["Access-Control-Allow-Origin"],
  );
});

Deno.test("preflight permits the deployed read and deletion routes", () => {
  const response = handleCorsPreflight(
    new Request("https://example.com/profile/reference-photos", { method: "OPTIONS" }),
  );
  assertEquals(response?.headers.get("Access-Control-Allow-Methods"), "GET, POST, DELETE, OPTIONS");
});

Deno.test("handleCorsPreflight returns null for non-OPTIONS requests", () => {
  const req = new Request("https://example.com/outfits/generate", { method: "POST" });
  assertStrictEquals(handleCorsPreflight(req), null);
});
