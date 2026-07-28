import { assertEquals, assertThrows } from "@std/assert";
import { AppError } from "../_shared/errors.ts";
import { parseEnvelope, parseGenerateOutfitsBody } from "./schema.ts";

const VALID_UUID = "550e8400-e29b-41d4-a716-446655440000";
const OTHER_UUID = "11111111-2222-4333-8444-555555555555";

Deno.test("parseEnvelope requires a JSON object with a body field", () => {
  assertThrows(() => parseEnvelope("not an object"), AppError);
  assertThrows(() => parseEnvelope({}), AppError);
  assertThrows(() => parseEnvelope(null), AppError);
});

Deno.test("parseEnvelope extracts request_id and body", () => {
  const result = parseEnvelope({
    request_id: "abc",
    client_version: "ios/1.0.0",
    body: { desired_count: 2 },
  });
  assertEquals(result.requestId, "abc");
  assertEquals(result.body, { desired_count: 2 });
});

Deno.test("parseGenerateOutfitsBody applies defaults for an empty body", () => {
  const parsed = parseGenerateOutfitsBody({});
  assertEquals(parsed, {
    occasionId: undefined,
    naturalLanguageRequest: undefined,
    lockedClosetItemIds: [],
    excludedClosetItemIds: [],
    desiredCount: 3,
  });
});

Deno.test("parseGenerateOutfitsBody parses a fully populated valid body", () => {
  const parsed = parseGenerateOutfitsBody({
    occasion_id: VALID_UUID,
    natural_language_request: "something for a rainy dinner",
    locked_closet_item_ids: [VALID_UUID],
    excluded_closet_item_ids: [OTHER_UUID],
    desired_count: 5,
  });
  assertEquals(parsed.occasionId, VALID_UUID);
  assertEquals(parsed.naturalLanguageRequest, "something for a rainy dinner");
  assertEquals(parsed.lockedClosetItemIds, [VALID_UUID]);
  assertEquals(parsed.excludedClosetItemIds, [OTHER_UUID]);
  assertEquals(parsed.desiredCount, 5);
});

Deno.test("parseGenerateOutfitsBody rejects a non-object body", () => {
  const err = assertThrows(() => parseGenerateOutfitsBody("nope"), AppError);
  assertEquals(err.category, "validation");
});

Deno.test("parseGenerateOutfitsBody rejects an out-of-range desired_count", () => {
  assertThrows(() => parseGenerateOutfitsBody({ desired_count: 0 }), AppError);
  assertThrows(() => parseGenerateOutfitsBody({ desired_count: 99 }), AppError);
});

Deno.test("parseGenerateOutfitsBody rejects a malformed UUID in locked_closet_item_ids", () => {
  assertThrows(
    () => parseGenerateOutfitsBody({ locked_closet_item_ids: ["not-a-uuid"] }),
    AppError,
  );
});

Deno.test("parseGenerateOutfitsBody ignores an unexpected user_id field entirely", () => {
  // This is the core security property under test: a client cannot smuggle
  // a different user's id into the request in a way this parser reads.
  const parsed = parseGenerateOutfitsBody({
    user_id: "11111111-1111-4111-8111-111111111111",
    desired_count: 2,
  }) as unknown as Record<string, unknown>;
  assertEquals("userId" in parsed, false);
  assertEquals("user_id" in parsed, false);
});
