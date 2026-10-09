import { assertEquals, assertThrows } from "@std/assert";
import { studioRequestBody } from "./studioRequest.ts";
import { CURRENT_STUDIO_CONSENT_TERMS_VERSION, parseGenerateBody } from "../studio/schema.ts";
import type { StudioPreviewSelection } from "./tools/generateStudioPreview.ts";
const selection: StudioPreviewSelection = {
  outfitId: null,
  itemIds: ["22222222-2222-4222-8222-222222222222"],
  referenceImageId: "33333333-3333-4333-8333-333333333333",
  pose: "three-quarter",
  background: "studio-neutral",
  resolution: "draft",
};
const reference = {
  path:
    "users/11111111-1111-4111-8111-111111111111/references/33333333-3333-4333-8333-333333333333.jpg",
  termsVersion: CURRENT_STUDIO_CONSENT_TERMS_VERSION,
};
Deno.test("Kyra selection translates to a request accepted by the real Studio parser", () => {
  const body = studioRequestBody(selection, reference);
  const parsed = parseGenerateBody(body);
  assertEquals(parsed.kind, "generate");
  assertEquals(body.pose, "standing_three_quarter");
  assertEquals(body.background, "studio");
  assertEquals(body.preserve_body_proportions, true);
});
Deno.test("unsupported resolution, invalid background and outdated consent are not silently changed", () => {
  assertThrows(() => studioRequestBody({ ...selection, resolution: "hi_res" }, reference));
  assertThrows(() => studioRequestBody({ ...selection, background: "unbuilt-scene" }, reference));
  assertThrows(() => studioRequestBody(selection, { ...reference, termsVersion: "old" }));
});

Deno.test("background lookup does not accept inherited object properties", () => {
  assertThrows(() => studioRequestBody({ ...selection, background: "toString" }, reference));
});
