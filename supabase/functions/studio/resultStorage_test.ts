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
    ownerHasPendingDeletion(userId) {
      calls.push(`deletion-check:${userId}`);
      return Promise.resolve(false);
    },
    enqueueOrphanCleanup() {
      return Promise.resolve();
    },
    completeOrphanCleanup() {
      return Promise.resolve();
    },
    upload(path, bytes, contentType) {
      calls.push(`upload:${path}:${bytes.byteLength}:${contentType}`);
      return Promise.resolve();
    },
    remove(path) {
      calls.push(`remove:${path}`);
      return Promise.resolve();
    },
  });

  assertEquals(calls, [
    `deletion-check:${OWNER_ID}`,
    `lookup:${OWNER_ID}:${GENERATION_ID}`,
    `upload:${OWNED_PATH}:3:image/png`,
    `deletion-check:${OWNER_ID}`,
    `lookup:${OWNER_ID}:${GENERATION_ID}`,
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
          ownerHasPendingDeletion() {
            return Promise.resolve(false);
          },
          enqueueOrphanCleanup() {
            return Promise.resolve();
          },
          completeOrphanCleanup() {
            return Promise.resolve();
          },
          upload() {
            uploaded = true;
            return Promise.resolve();
          },
          remove() {
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
    ownerHasPendingDeletion() {
      return Promise.resolve(false);
    },
    enqueueOrphanCleanup() {
      return Promise.resolve();
    },
    completeOrphanCleanup() {
      return Promise.resolve();
    },
    upload() {
      uploads += 1;
      return Promise.resolve();
    },
    remove() {
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
        ownerHasPendingDeletion() {
          return Promise.resolve(false);
        },
        enqueueOrphanCleanup() {
          return Promise.resolve();
        },
        completeOrphanCleanup() {
          return Promise.resolve();
        },
        upload() {
          uploads += 1;
          return Promise.resolve();
        },
        remove() {
          return Promise.resolve();
        },
      },
    )
  );
  assertEquals(lookups, 0);
  assertEquals(uploads, 0);
});

Deno.test("Studio result writes reject an owner with pending account deletion before upload", async () => {
  let uploads = 0;
  await assertRejects(() =>
    storeOwnedStudioResult(OWNER_ID, OWNED_PATH, new Uint8Array([1]), "image/png", {
      hasLiveOwnedGeneration() {
        return Promise.resolve(true);
      },
      ownerHasPendingDeletion() {
        return Promise.resolve(true);
      },
      enqueueOrphanCleanup() {
        return Promise.resolve();
      },
      upload() {
        uploads += 1;
        return Promise.resolve();
      },
      remove() {
        return Promise.resolve();
      },
      completeOrphanCleanup() {
        return Promise.resolve();
      },
    })
  );
  assertEquals(uploads, 0);
});

Deno.test("Studio result upload removes its canonical object if account deletion starts during upload", async () => {
  const calls: string[] = [];
  let pendingDeletion = false;
  await assertRejects(() =>
    storeOwnedStudioResult(OWNER_ID, OWNED_PATH, new Uint8Array([1]), "image/png", {
      hasLiveOwnedGeneration() {
        return Promise.resolve(true);
      },
      ownerHasPendingDeletion() {
        return Promise.resolve(pendingDeletion);
      },
      enqueueOrphanCleanup(userId, generationId, path) {
        calls.push(`queue:${userId}:${generationId}:${path}`);
        return Promise.resolve();
      },
      upload(path) {
        calls.push(`upload:${path}`);
        pendingDeletion = true;
        return Promise.resolve();
      },
      remove(path) {
        calls.push(`remove:${path}`);
        return Promise.resolve();
      },
      completeOrphanCleanup(path) {
        calls.push(`complete:${path}`);
        return Promise.resolve();
      },
    })
  );
  assertEquals(calls, [
    `upload:${OWNED_PATH}`,
    `queue:${OWNER_ID}:${GENERATION_ID}:${OWNED_PATH}`,
    `remove:${OWNED_PATH}`,
    `complete:${OWNED_PATH}`,
  ]);
});

Deno.test("Studio result upload removes its object if the live job disappears during upload", async () => {
  const calls: string[] = [];
  let live = true;
  await assertRejects(() =>
    storeOwnedStudioResult(OWNER_ID, OWNED_PATH, new Uint8Array([1]), "image/png", {
      hasLiveOwnedGeneration() {
        return Promise.resolve(live);
      },
      ownerHasPendingDeletion() {
        return Promise.resolve(false);
      },
      enqueueOrphanCleanup() {
        return Promise.resolve();
      },
      completeOrphanCleanup() {
        return Promise.resolve();
      },
      upload(path) {
        calls.push(`upload:${path}`);
        live = false;
        return Promise.resolve();
      },
      remove(path) {
        calls.push(`remove:${path}`);
        return Promise.resolve();
      },
    })
  );
  assertEquals(calls, [`upload:${OWNED_PATH}`, `remove:${OWNED_PATH}`]);
});

Deno.test("Studio result upload cleans up if the post-upload owner check is uncertain", async () => {
  const calls: string[] = [];
  let deletionChecks = 0;
  await assertRejects(() =>
    storeOwnedStudioResult(OWNER_ID, OWNED_PATH, new Uint8Array([1]), "image/png", {
      hasLiveOwnedGeneration() {
        return Promise.resolve(true);
      },
      ownerHasPendingDeletion() {
        deletionChecks += 1;
        if (deletionChecks === 2) return Promise.reject(new Error("Database unavailable"));
        return Promise.resolve(false);
      },
      enqueueOrphanCleanup() {
        return Promise.resolve();
      },
      completeOrphanCleanup() {
        return Promise.resolve();
      },
      upload(path) {
        calls.push(`upload:${path}`);
        return Promise.resolve();
      },
      remove(path) {
        calls.push(`remove:${path}`);
        return Promise.resolve();
      },
    })
  );
  assertEquals(calls, [`upload:${OWNED_PATH}`, `remove:${OWNED_PATH}`]);
});

Deno.test("Studio result upload reports cleanup failure instead of accepting a possible orphan", async () => {
  let cleanupAttempted = false;
  let durableJobQueued = false;
  let live = true;
  await assertRejects(() =>
    storeOwnedStudioResult(OWNER_ID, OWNED_PATH, new Uint8Array([1]), "image/png", {
      hasLiveOwnedGeneration() {
        return Promise.resolve(live);
      },
      ownerHasPendingDeletion() {
        return Promise.resolve(false);
      },
      enqueueOrphanCleanup(userId, generationId, path) {
        durableJobQueued = userId === OWNER_ID && generationId === GENERATION_ID &&
          path === OWNED_PATH;
        return Promise.resolve();
      },
      upload() {
        live = false;
        return Promise.resolve();
      },
      remove() {
        cleanupAttempted = true;
        return Promise.reject(new Error("Storage removal unavailable"));
      },
      completeOrphanCleanup() {
        return Promise.resolve();
      },
    })
  );
  assertEquals(durableJobQueued, true);
  assertEquals(cleanupAttempted, true);
});
