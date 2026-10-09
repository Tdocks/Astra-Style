import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import {
  generationCacheFingerprint,
  parseSubmissionKey,
  submissionFingerprint,
} from "./submissionKey.ts";
Deno.test("submission keys accept UUIDs only", () => {
  assertEquals(parseSubmissionKey(null), null);
  assertThrows(() => parseSubmissionKey("not-a-key"));
  assertEquals(
    parseSubmissionKey("AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"),
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  );
});

Deno.test("semantic cache identity changes for rerolls, provider versions, context and resolved garments", async () => {
  const base = {
    userId: "owner",
    referenceImagePath: "users/owner/references/photo.jpg",
    outfitId: "outfit-a",
    provider: "openai:gpt-image-1.5:studio-prompt-v1",
    resolution: "draft",
    prompt: "navy sweater in rainy weather",
    garments: [{ role: "top", normalizedTitle: "sweater", colorDescription: "navy" }],
    mode: "closet_inspiration",
    context: "Rain today",
    instructions: "",
    itemIds: ["item-a"],
    controls: { pose: "standing_front", background: "studio", resolution: "draft" },
  };
  const first = await generationCacheFingerprint(base);
  assertEquals(first.length, 64);
  assertEquals(await generationCacheFingerprint({ ...base }), first);
  assertNotEquals(
    await generationCacheFingerprint({
      ...base,
      variationNonce: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    }),
    first,
  );
  assertNotEquals(await generationCacheFingerprint({ ...base, context: "Sunny today" }), first);
  assertNotEquals(
    await generationCacheFingerprint({ ...base, provider: "openai:gpt-image-2:studio-prompt-v1" }),
    first,
  );
  assertNotEquals(
    await generationCacheFingerprint({
      ...base,
      garments: [{ ...base.garments[0], colorDescription: "cream" }],
    }),
    first,
  );
});
Deno.test("fingerprints ignore object field order but distinguish selection changes", async () => {
  const first = await submissionFingerprint({
    outfit: "one",
    settings: { pose: "standing", background: "studio" },
  });
  assertEquals(
    first,
    await submissionFingerprint({
      settings: { background: "studio", pose: "standing" },
      outfit: "one",
    }),
  );
  assertNotEquals(
    first,
    await submissionFingerprint({
      outfit: "two",
      settings: { pose: "standing", background: "studio" },
    }),
  );
  assertEquals(first.length, 64);
});
