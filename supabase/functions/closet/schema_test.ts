import { assertEquals, assertThrows } from "@std/assert";
import { AppError } from "../_shared/errors.ts";
import {
  assertOwnsStoragePath,
  parseAnalyzeItemBody,
  parseBatchAnalyzeBody,
  parseEnvelope,
  parseIdempotencyKey,
} from "./schema.ts";

const USER_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const REQUEST_A = "11111111-1111-4111-8111-111111111111";
const REQUEST_B = "22222222-2222-4222-8222-222222222222";

Deno.test("parseEnvelope requires a JSON object with a body field", () => {
  assertThrows(() => parseEnvelope("not an object"), AppError);
  assertThrows(() => parseEnvelope({}), AppError);
});

Deno.test("parseAnalyzeItemBody parses a valid element", () => {
  const parsed = parseAnalyzeItemBody({
    request_id: REQUEST_A,
    storage_path: `users/${USER_A}/closet/capture.jpg`,
    image_type: "front",
    device_hints: {
      dominant_colors_rgb: ["#1B2A4A"],
      detected_text: ["SIZE M", "100% COTTON"],
      approximate_category: "top",
    },
  });
  assertEquals(parsed.requestId, REQUEST_A);
  assertEquals(parsed.deviceHints?.approximateCategory, "top");
  assertEquals(parsed.deviceHints?.detectedText.length, 2);
});

Deno.test("parseAnalyzeItemBody rejects a path traversal storage_path", () => {
  assertThrows(
    () =>
      parseAnalyzeItemBody({
        request_id: REQUEST_A,
        storage_path: "users/../etc/passwd",
        image_type: "front",
      }),
    AppError,
  );
});

Deno.test("parseBatchAnalyzeBody rejects an empty items array", () => {
  assertThrows(() => parseBatchAnalyzeBody({ items: [] }), AppError);
});

Deno.test("parseBatchAnalyzeBody rejects duplicate request ids", () => {
  assertThrows(
    () =>
      parseBatchAnalyzeBody({
        items: [
          {
            request_id: REQUEST_A,
            storage_path: `users/${USER_A}/closet/a.jpg`,
            image_type: "front",
          },
          {
            request_id: REQUEST_A,
            storage_path: `users/${USER_A}/closet/b.jpg`,
            image_type: "front",
          },
        ],
      }),
    AppError,
  );
});

Deno.test("parseBatchAnalyzeBody accepts a valid multi-item body", () => {
  const parsed = parseBatchAnalyzeBody({
    items: [
      {
        request_id: REQUEST_A,
        storage_path: `users/${USER_A}/closet/a.jpg`,
        image_type: "front",
      },
      {
        request_id: REQUEST_B,
        storage_path: `users/${USER_A}/closet/b.jpg`,
        image_type: "back",
      },
    ],
  });
  assertEquals(parsed.items.length, 2);
  assertEquals(parsed.items[1]?.imageType, "back");
});

Deno.test("assertOwnsStoragePath accepts the caller's folder, case-insensitively", () => {
  assertOwnsStoragePath(
    `users/${USER_A.toUpperCase()}/closet/x.jpg`,
    USER_A,
  );
});

Deno.test("assertOwnsStoragePath rejects another user's folder", () => {
  assertThrows(
    () => assertOwnsStoragePath("users/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/closet/x.jpg", USER_A),
    AppError,
  );
});

Deno.test("parseIdempotencyKey requires a non-empty header", () => {
  assertThrows(() => parseIdempotencyKey(null), AppError);
  assertThrows(() => parseIdempotencyKey("   "), AppError);
  assertEquals(parseIdempotencyKey("abc-123"), "abc-123");
});
