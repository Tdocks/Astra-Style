// ============================================================================
// account/schema_test.ts
// ============================================================================
// Covers `tryExtractRequestId`'s deliberately-non-throwing contract — see
// its header comment in schema.ts for why a parse failure here degrades
// rather than errors.
// ============================================================================

import { assertEquals } from "@std/assert";
import { tryExtractRequestId } from "./schema.ts";

Deno.test("extracts request_id from a well-formed envelope", () => {
  const raw = JSON.stringify({ request_id: "abc-123", client_version: "ios/1.0.0", body: {} });
  assertEquals(tryExtractRequestId(raw), "abc-123");
});

Deno.test("returns undefined for an empty body", () => {
  assertEquals(tryExtractRequestId(""), undefined);
  assertEquals(tryExtractRequestId("   "), undefined);
});

Deno.test("returns undefined for unparsable JSON, rather than throwing", () => {
  assertEquals(tryExtractRequestId("{ not json"), undefined);
});

Deno.test("returns undefined for valid JSON that isn't an object", () => {
  assertEquals(tryExtractRequestId("[1,2,3]"), undefined);
  assertEquals(tryExtractRequestId('"just a string"'), undefined);
  assertEquals(tryExtractRequestId("42"), undefined);
});

Deno.test("returns undefined when request_id is missing", () => {
  assertEquals(
    tryExtractRequestId(JSON.stringify({ client_version: "ios/1.0.0", body: {} })),
    undefined,
  );
});

Deno.test("returns undefined when request_id is present but not a string", () => {
  assertEquals(tryExtractRequestId(JSON.stringify({ request_id: 12345, body: {} })), undefined);
  assertEquals(tryExtractRequestId(JSON.stringify({ request_id: null, body: {} })), undefined);
});
