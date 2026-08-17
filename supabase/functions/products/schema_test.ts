import { assertEquals, assertThrows } from "@std/assert";
import { AppError } from "../_shared/errors.ts";
import { parseEnvelope, parseEvaluateProductBody, parseExtractProductBody } from "./schema.ts";

Deno.test("parseEnvelope: requires a body field", () => {
  assertThrows(() => parseEnvelope({}), AppError);
  assertThrows(() => parseEnvelope("not an object"), AppError);
});

Deno.test("parseEnvelope: extracts request_id and body", () => {
  const result = parseEnvelope({ request_id: "abc", body: { url: "x" } });
  assertEquals(result.requestId, "abc");
  assertEquals(result.body, { url: "x" });
});

Deno.test("parseExtractProductBody: accepts a well-formed public https url", () => {
  const result = parseExtractProductBody({ url: "https://example.com/products/navy-blazer" });
  assertEquals(result.url, "https://example.com/products/navy-blazer");
});

Deno.test("parseExtractProductBody: rejects a missing url", () => {
  assertThrows(() => parseExtractProductBody({}), AppError);
});

Deno.test("parseExtractProductBody: rejects a non-string url", () => {
  assertThrows(() => parseExtractProductBody({ url: 12345 }), AppError);
});

Deno.test("parseExtractProductBody: rejects an SSRF-shaped url (delegates to urlValidation)", () => {
  assertThrows(() => parseExtractProductBody({ url: "http://169.254.169.254/" }), AppError);
});

Deno.test("parseEvaluateProductBody: accepts a well-formed uuid", () => {
  const id = "123e4567-e89b-12d3-a456-426614174000";
  const result = parseEvaluateProductBody({ product_candidate_id: id });
  assertEquals(result.productCandidateId, id);
});

Deno.test("parseEvaluateProductBody: rejects a non-uuid product_candidate_id", () => {
  assertThrows(() => parseEvaluateProductBody({ product_candidate_id: "not-a-uuid" }), AppError);
});

Deno.test("parseEvaluateProductBody: rejects a missing product_candidate_id", () => {
  assertThrows(() => parseEvaluateProductBody({}), AppError);
});
