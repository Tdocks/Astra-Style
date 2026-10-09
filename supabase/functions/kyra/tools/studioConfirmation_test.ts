import { assertEquals } from "@std/assert";
import { studioGenerationConfirmed } from "./studioConfirmation.ts";

Deno.test("direct preview instructions confirm generation but ordinary questions do not", () => {
  for (
    const text of ["Generate a preview", "Please create an outfit image", "Show me this on me"]
  ) {
    assertEquals(studioGenerationConfirmed(text, "selection-a", null), true);
  }
  for (
    const text of [
      "Can you generate a preview?",
      "Should I create an image?",
      "Don't generate a preview",
      "Generate a preview but don't spend credits",
      "No, generate a preview later",
      "Generate a preview, actually cancel",
      "Generate a preview is the button label",
    ]
  ) {
    assertEquals(studioGenerationConfirmed(text, "selection-a", null), false);
  }
});

Deno.test("affirmative replies require a matching server-owned cost confirmation", () => {
  const pending = { selectionKey: "selection-a", askedAboutGenerationCost: true };
  assertEquals(studioGenerationConfirmed("Yes!", "selection-a", pending), true);
  assertEquals(studioGenerationConfirmed("yes", "selection-b", pending), false);
  assertEquals(studioGenerationConfirmed("yes", "selection-a", null), false);
  assertEquals(
    studioGenerationConfirmed("yes", "selection-a", {
      ...pending,
      askedAboutGenerationCost: false,
    }),
    false,
  );
  assertEquals(studioGenerationConfirmed("no", "selection-a", pending), false);
});
