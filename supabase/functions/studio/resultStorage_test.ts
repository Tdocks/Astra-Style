import { assertEquals, assertRejects } from "@std/assert";
import { storeOwnedStudioResult } from "./resultStorage.ts";

const OWNER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const PEER_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const GENERATION_ID = "12121212-1212-4121-8121-121212121212";
const OWNED_PATH = `users/${OWNER_ID}/studio/${GENERATION_ID}/result.png`;

Deno.test("Studio result writes use server persistence only after matching live owner row", async () => {
  const calls: string[] = [];
  await storeOwnedStudioResult(OWNER_ID, OWNED_PATH, new Uint8Array([1, 2, 3]), "image/png", {
    hasLiveOwnedGeneration(userId, generationId) {
      calls.push(`lookup:${userId}:${generationId}`);
      return Promise.resolve(userId === OWNER_ID && generationId === GENERATION_ID);
    },
    upload(path, bytes, contentType) {
      calls.push(`upload:${path}:${bytes.byteLength}:${contentType}`);
      return Promise.resolve();
    },
  });

  assertEquals(calls, [
    `lookup:${OWNER_ID}:${GENERATION_ID}`,
    `upload:${OWNED_PATH}:3:image/png`,
  ]);
});

Deno.test("Studio result write rejects another owner's path before privileged upload", async () => {
  let uploaded = false;
  await assertRejects(
    () =>
      storeOwnedStudioResult(
        OWNER_ID,
        `users/${PEER_ID}/studio/${GENERATION_ID}/result.png`,
        new Uint8Array([1]),
        "image/png",
        {
          hasLiveOwnedGeneration() {
            return Promise.resolve(false);
          },
          upload() {
            uploaded = true;
            return Promise.resolve();
          },
        },
      ),
  );
  assertEquals(uploaded, false);
});

Deno.test("Studio result write rejects noncanonical paths and deleted or absent rows", async () => {
  let lookups = 0;
  let uploads = 0;
  const persistence = {
    hasLiveOwnedGeneration() {
      lookups += 1;
      return Promise.resolve(false);
    },
    upload() {
      uploads += 1;
      return Promise.resolve();
    },
  };

  await assertRejects(() =>
    storeOwnedStudioResult(
      OWNER_ID,
      `${OWNED_PATH}/../other.png`,
      new Uint8Array([1]),
      "image/png",
      persistence,
    )
  );
  await assertRejects(() =>
    storeOwnedStudioResult(OWNER_ID, OWNED_PATH, new Uint8Array([1]), "image/png", persistence)
  );

  assertEquals(lookups, 1);
  assertEquals(uploads, 0);
});

Deno.test("Studio result write rejects a path owned by another authenticated user before lookup", async () => {
  let lookups = 0;
  let uploads = 0;
  await assertRejects(() =>
    storeOwnedStudioResult(
      OWNER_ID,
      `users/${PEER_ID}/studio/${GENERATION_ID}/result.png`,
      new Uint8Array([1]),
      "image/png",
      {
        hasLiveOwnedGeneration() {
          lookups += 1;
          return Promise.resolve(true);
        },
        upload() {
          uploads += 1;
          return Promise.resolve();
        },
      },
    )
  );
  assertEquals(lookups, 0);
  assertEquals(uploads, 0);
});
