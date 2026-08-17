// ============================================================================
// studio/schema_test.ts
// ============================================================================
// The consent gate's wire half, ownership of the reference path, the
// generate/retry body split, and the timestamp format Swift's `.iso8601`
// decoder can actually parse.
// ============================================================================

import { assert, assertEquals, assertStringIncludes, assertThrows } from "@std/assert";
import { AppError } from "../_shared/errors.ts";
import {
  assertConsentCurrent,
  assertOwnedReferencePath,
  CURRENT_STUDIO_CONSENT_TERMS_VERSION,
  parseGenerateBody,
  toWireTimestamp,
} from "./schema.ts";

const USER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const OTHER_USER_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const OUTFIT_ID = "12121212-1212-4121-8121-121212121212";

function validBody(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    reference_image_path: `users/${USER_ID}/references/selfie.jpg`,
    outfit_id: OUTFIT_ID,
    consent: {
      acknowledged: true,
      terms_version: CURRENT_STUDIO_CONSENT_TERMS_VERSION,
    },
    ...overrides,
  };
}

Deno.test("a valid generate body parses with defaulted controls", () => {
  const parsed = parseGenerateBody(validBody());
  assert(parsed.kind === "generate");
  assertEquals(parsed.outfitId, OUTFIT_ID);
  assertEquals(parsed.background, "studio");
  assertEquals(parsed.pose, "standing_front");
  assertEquals(parsed.preserveFace, true);
  assertEquals(parsed.preserveBodyProportions, true);
  assertEquals(parsed.preserveHair, true);
  assertEquals(parsed.colorPalette, []);
});

Deno.test("retry_of parses as a retry, ignoring everything else", () => {
  const parsed = parseGenerateBody({ retry_of: OUTFIT_ID });
  assert(parsed.kind === "retry");
  assertEquals(parsed.retryOf, OUTFIT_ID);
});

Deno.test("neither an outfit nor items is a validation error, not an empty render", () => {
  const err = assertThrows(
    () => parseGenerateBody(validBody({ outfit_id: null })),
    AppError,
  );
  assertStringIncludes(err.message, "Select an outfit");
});

Deno.test("unknown enum values are rejected rather than silently defaulted", () => {
  assertThrows(() => parseGenerateBody(validBody({ background: "beach" })), AppError);
  assertThrows(() => parseGenerateBody(validBody({ pose: "handstand" })), AppError);
  assertThrows(() => parseGenerateBody(validBody({ preset: "cyberpunk" })), AppError);
  assertThrows(() => parseGenerateBody(validBody({ formality: "extremely_formal" })), AppError);
  assertThrows(() => parseGenerateBody(validBody({ season: "monsoon" })), AppError);
});

Deno.test("consent gate: missing block and unacknowledged both fail with the same message", () => {
  const missing = parseGenerateBody(validBody({ consent: undefined }));
  assert(missing.kind === "generate");
  const errMissing = assertThrows(() => assertConsentCurrent(missing.consent), AppError);
  assertStringIncludes(errMissing.message, "hasn't been confirmed");

  const unacknowledged = parseGenerateBody(
    validBody({
      consent: { acknowledged: false, terms_version: CURRENT_STUDIO_CONSENT_TERMS_VERSION },
    }),
  );
  assert(unacknowledged.kind === "generate");
  const errUnack = assertThrows(() => assertConsentCurrent(unacknowledged.consent), AppError);
  assertEquals(errUnack.message, errMissing.message);
});

Deno.test("consent gate: an attestation against old terms is stale, not carried forward", () => {
  const err = assertThrows(
    () =>
      assertConsentCurrent({
        acknowledged: true,
        termsVersion: "2020-01-01",
      }),
    AppError,
  );
  assertStringIncludes(err.message, "terms have changed");
});

Deno.test("reference path must be inside the caller's own references folder", () => {
  // The happy path, including the uppercase-UUID client quirk.
  assertOwnedReferencePath(`users/${USER_ID}/references/selfie.jpg`, USER_ID);
  assertOwnedReferencePath(
    `users/${USER_ID.toUpperCase()}/references/selfie.jpg`,
    USER_ID,
  );
  // Another user's folder.
  assertThrows(
    () => assertOwnedReferencePath(`users/${OTHER_USER_ID}/references/selfie.jpg`, USER_ID),
    AppError,
  );
  // The caller's own folder, but not a reference image — a closet photo is
  // not a consented reference and must not become one via path choice.
  assertThrows(
    () => assertOwnedReferencePath(`users/${USER_ID}/closet/item.jpg`, USER_ID),
    AppError,
  );
  // Traversal and absolute paths.
  assertThrows(
    () => assertOwnedReferencePath(`users/${USER_ID}/references/../closet/item.jpg`, USER_ID),
    AppError,
  );
  assertThrows(
    () => assertOwnedReferencePath(`/users/${USER_ID}/references/selfie.jpg`, USER_ID),
    AppError,
  );
});

Deno.test("wire timestamps carry no fractional seconds (Swift .iso8601 rejects them)", () => {
  assertEquals(toWireTimestamp("2026-08-17T12:34:56.789+00:00"), "2026-08-17T12:34:56Z");
  assertEquals(toWireTimestamp(new Date("2026-08-17T12:34:56.123Z")), "2026-08-17T12:34:56Z");
  assertThrows(() => toWireTimestamp("not a date"), AppError);
});
