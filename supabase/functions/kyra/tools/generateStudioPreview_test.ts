import { assertEquals } from "@std/assert";
import {
  executeGenerateStudioPreview,
  type GenerateStudioPreviewDeps,
  parseStudioPreview,
  studioSelectionKey,
} from "./generateStudioPreview.ts";

const args = {
  reference_image_id: "11111111-1111-4111-8111-111111111111",
  item_ids: ["22222222-2222-4222-8222-222222222222"],
};
const fail = () => {
  throw new Error("Must not enqueue");
};
const deps: GenerateStudioPreviewDeps = {
  userText: "yes",
  pending: null,
  currentConsentTermsVersion: "current",
  resolveOwnedConsentedReference: fail,
  enqueue: fail,
};
Deno.test("unconfirmed requests never resolve photos or spend credits", async () => {
  assertEquals((await executeGenerateStudioPreview(args, deps)).error, "CONFIRMATION_REQUIRED");
});
Deno.test("missing or outdated consent cannot enqueue a generation", async () => {
  for (const reference of [null, { path: "private-photo", termsVersion: "old" }]) {
    const result = await executeGenerateStudioPreview(args, {
      ...deps,
      userText: "Generate a preview",
      resolveOwnedConsentedReference: () => Promise.resolve(reference),
    });
    assertEquals(result.error, "NO_CONSENTED_REFERENCE_IMAGE");
  }
});
Deno.test("confirmed selections and current consent reach the owned generation service", async () => {
  const selection = parseStudioPreview(args);
  if (!selection) throw new Error("Invalid fixture");
  let calls = 0;
  const result = await executeGenerateStudioPreview(args, {
    ...deps,
    pending: { selectionKey: studioSelectionKey(selection), askedAboutGenerationCost: true },
    resolveOwnedConsentedReference: () =>
      Promise.resolve({ path: "private-photo", termsVersion: "current" }),
    enqueue: (received, reference) => {
      calls++;
      assertEquals(received, selection);
      assertEquals(reference.termsVersion, "current");
      return Promise.resolve({
        generationId: "fixture-job",
        status: "queued",
        estimatedSeconds: 30,
      });
    },
  });
  assertEquals(calls, 1);
  assertEquals(result.status, "queued");
});

Deno.test("preview parser rejects malformed options and competing selections", () => {
  for (
    const extra of [{ pose: ["walking"] }, { resolution: ["draft"] }, {
      outfit_id: "33333333-3333-4333-8333-333333333333",
    }, { reference_image_id: "private/path" }]
  ) {
    assertEquals(parseStudioPreview({ ...args, ...extra }), null);
  }
});
