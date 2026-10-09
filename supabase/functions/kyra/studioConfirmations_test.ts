import { assertEquals } from "@std/assert";
import { activeStudioConfirmation } from "./studioConfirmations.ts";
import { type StudioPreviewSelection, studioSelectionKey } from "./tools/generateStudioPreview.ts";

const user = "11111111-1111-4111-8111-111111111111";
const thread = "22222222-2222-4222-8222-222222222222";
const prompt = "33333333-3333-4333-8333-333333333333";
const selection: StudioPreviewSelection = {
  outfitId: "44444444-4444-4444-8444-444444444444",
  itemIds: [],
  referenceImageId: "55555555-5555-4555-8555-555555555555",
  pose: "standing",
  background: "studio-neutral",
  resolution: "draft",
};
const now = Date.parse("2026-10-09T00:00:00Z");
const row = {
  id: "66666666-6666-4666-8666-666666666666",
  user_id: user,
  thread_id: thread,
  prompt_message_id: prompt,
  selection,
  selection_key: studioSelectionKey(selection),
  expires_at: "2026-10-09T00:30:00Z",
  closed_at: null,
};

Deno.test("confirmation hydrates only matching live owner/thread/prompt selection", () => {
  assertEquals(activeStudioConfirmation(row, user, thread, prompt, now)?.id, row.id);
  for (
    const changed of [
      { user_id: thread },
      { thread_id: user },
      { prompt_message_id: user },
      { closed_at: "2026-10-09T00:01:00Z" },
      { expires_at: "2026-10-09T00:00:00Z" },
      { expires_at: "invalid" },
      { selection_key: "different" },
      { selection: { ...selection, referenceImageId: "invalid" } },
    ]
  ) {
    assertEquals(activeStudioConfirmation({ ...row, ...changed }, user, thread, prompt, now), null);
  }
  assertEquals(activeStudioConfirmation(row, user, thread, null, now), null);
});
