import { assertEquals } from "@std/assert";
import {
  type CompletedInspirationRow,
  resolveCompletedStudioInspiration,
  resolveConsentedStudioReference,
} from "./studioReferences.ts";
const user = "11111111-1111-4111-8111-111111111111";
const reference = "22222222-2222-4222-8222-222222222222";
const path = `users/${user}/references/${reference}.jpg`;
const generation = "33333333-3333-4333-8333-333333333333";
const resultPath = `users/${user}/studio/${generation}/result.png`;
const storageOrigin = "https://project.supabase.co";
const signedURL =
  `${storageOrigin}/storage/v1/object/sign/user-content/${resultPath}?token=short-lived`;

function completedInspiration(
  overrides: Partial<CompletedInspirationRow> = {},
): CompletedInspirationRow {
  return {
    id: generation,
    user_id: user,
    status: "complete",
    deleted_at: null,
    result_image_path: resultPath,
    prompt_payload: { mode: "inspiration" },
    ...overrides,
  };
}

Deno.test("completed owned inspiration resolves to a signed URL, never a storage path", async () => {
  let signedPath: string | null = null;
  const resolved = await resolveCompletedStudioInspiration(user, generation, {
    generation: (id) => {
      assertEquals(id, generation);
      return Promise.resolve(completedInspiration());
    },
    signedImageURL: (candidate) => {
      signedPath = candidate;
      return Promise.resolve(signedURL);
    },
  }, storageOrigin);
  assertEquals(signedPath, resultPath);
  assertEquals(resolved, { imageURL: signedURL });
  assertEquals(Object.keys(resolved ?? {}).sort(), ["imageURL"]);
});

Deno.test("inspiration lookup fails closed for peer, deleted, incomplete, non-inspiration, and missing-image rows", async () => {
  const invalidRows = [
    completedInspiration({ user_id: "44444444-4444-4444-8444-444444444444" }),
    completedInspiration({ deleted_at: "2026-10-08T00:00:00Z" }),
    completedInspiration({ status: "generating" }),
    completedInspiration({ prompt_payload: { mode: "reference" } }),
    completedInspiration({ result_image_path: null }),
    completedInspiration({ result_image_path: `users/${user}/studio/${generation}/other.png` }),
  ];
  for (const row of invalidRows) {
    let signed = false;
    const resolved = await resolveCompletedStudioInspiration(user, generation, {
      generation: () => Promise.resolve(row),
      signedImageURL: () => {
        signed = true;
        return Promise.resolve("https://storage.example/signed/result.png");
      },
    }, storageOrigin);
    assertEquals(resolved, null);
    assertEquals(signed, false);
  }
});

Deno.test("missing object, foreign host, wrong object path, or non-HTTPS URL never reaches Kyra", async () => {
  for (
    const url of [
      null,
      "http://project.supabase.co/storage/v1/object/sign/user-content/" + resultPath,
      "https://attacker.example/storage/v1/object/sign/user-content/" + resultPath,
      `${storageOrigin}/storage/v1/object/sign/user-content/users/${user}/studio/other/result.png`,
    ]
  ) {
    const resolved = await resolveCompletedStudioInspiration(user, generation, {
      generation: () => Promise.resolve(completedInspiration()),
      signedImageURL: () => Promise.resolve(url),
    }, storageOrigin);
    assertEquals(resolved, null);
  }
});
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
