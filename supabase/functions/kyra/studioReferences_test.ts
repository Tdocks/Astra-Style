import { assertEquals } from "@std/assert";
import { resolveConsentedStudioReference } from "./studioReferences.ts";
const user = "11111111-1111-4111-8111-111111111111";
const reference = "22222222-2222-4222-8222-222222222222";
const path = `users/${user}/references/${reference}.jpg`;
Deno.test("a saved owned reference with a current server receipt can be resolved", async () => {
  const result = await resolveConsentedStudioReference(user, reference, "current", {
    savedPaths: () => Promise.resolve([path]),
    hasCurrentConsentReceipt: (received, terms) => {
      assertEquals(received, path);
      assertEquals(terms, "current");
      return Promise.resolve(true);
    },
  });
  assertEquals(result, { path, termsVersion: "current" });
});
Deno.test("removed or peer photos never reach consent lookup", async () => {
  for (
    const paths of [[], [`users/33333333-3333-4333-8333-333333333333/references/${reference}.jpg`]]
  ) {
    assertEquals(
      await resolveConsentedStudioReference(user, reference, "current", {
        savedPaths: () => Promise.resolve(paths),
        hasCurrentConsentReceipt: () => {
          throw new Error("Unexpected lookup");
        },
      }),
      null,
    );
  }
});
Deno.test("a photo without current acknowledged consent is unavailable to chat", async () => {
  assertEquals(
    await resolveConsentedStudioReference(user, reference, "current", {
      savedPaths: () => Promise.resolve([path]),
      hasCurrentConsentReceipt: () => Promise.resolve(false),
    }),
    null,
  );
});

Deno.test("chat reference context excludes peer paths and stale consent and returns only IDs", async () => {
  const { listConsentedStudioReferenceIDs } = await import("./studioReferences.ts");
  const stale = "44444444-4444-4444-8444-444444444444";
  const checked: string[] = [];
  const ids = await listConsentedStudioReferenceIDs(user, "current", {
    savedPaths: () =>
      Promise.resolve([
        path,
        path,
        `users/${user}/references/${stale}.jpg`,
        `users/${stale}/references/${reference}.jpg`,
        `users/${user}/references/not-a-uuid.jpg`,
      ]),
    hasCurrentConsentReceipt: (candidate, terms) => {
      assertEquals(terms, "current");
      checked.push(candidate);
      return Promise.resolve(candidate === path);
    },
  });
  assertEquals(ids, [reference]);
  assertEquals(checked.length, 2);
});
