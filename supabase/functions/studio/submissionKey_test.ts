import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import { parseSubmissionKey, submissionFingerprint } from "./submissionKey.ts";
Deno.test("submission keys accept UUIDs only", () => {
  assertEquals(parseSubmissionKey(null), null);
  assertThrows(() => parseSubmissionKey("not-a-key"));
  assertEquals(
    parseSubmissionKey("AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"),
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
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
