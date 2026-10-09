import { serverError } from "../_shared/errors.ts";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export interface StudioResultPersistence {
  hasLiveOwnedGeneration(userId: string, generationId: string): Promise<boolean>;
  ownerHasPendingDeletion(userId: string): Promise<boolean>;
  enqueueOrphanCleanup(userId: string, generationId: string, path: string): Promise<void>;
  upload(path: string, bytes: Uint8Array, contentType: string): Promise<void>;
  remove(path: string): Promise<void>;
  completeOrphanCleanup(path: string): Promise<void>;
}

/**
 * Persist a generated render through the server-role Storage client. Provider
 * outputs are server-generated, so caller-scoped Storage insert policies are
 * intentionally not broadened to admit them. Both the path and live job row
 * are checked against the authenticated owner before the privileged write.
 */
export async function storeOwnedStudioResult(
  authenticatedUserId: string,
  storagePath: string,
  bytes: Uint8Array,
  contentType: string,
  persistence: StudioResultPersistence,
): Promise<void> {
  const match = /^users\/([0-9a-f-]+)\/studio\/([0-9a-f-]+)\/result\.png$/.exec(storagePath);
  const owner = match?.[1];
  const generationId = match?.[2];
  if (
    !owner || !generationId || !UUID_PATTERN.test(owner) || !UUID_PATTERN.test(generationId) ||
    owner !== authenticatedUserId.toLowerCase()
  ) {
    throw serverError("Couldn't store the generated image.");
  }

  const canWrite = async (): Promise<boolean> => {
    if (await persistence.ownerHasPendingDeletion(owner)) return false;
    return await persistence.hasLiveOwnedGeneration(owner, generationId);
  };

  if (!await canWrite()) {
    throw serverError("Couldn't store the generated image.");
  }

  await persistence.upload(storagePath, bytes, contentType);

  // Account deletion starts its Storage sweep before removing database rows.
  // A render can pass the first check, then upload after that sweep. Recheck
  // both owner and job after upload; if either became ineligible, remove only
  // this already-validated canonical result path with the service client.
  let remainsWritable = false;
  try {
    remainsWritable = await canWrite();
  } catch {
    // An uncertain owner/job read must fail closed. The narrowly scoped
    // cleanup below is still attempted before surfacing the storage error.
  }
  if (!remainsWritable) {
    // Persist cleanup intent before attempting removal. If Storage is
    // unavailable, the scheduled retention worker retries this exact path
    // even after account deletion removes Auth and generation rows.
    try {
      await persistence.enqueueOrphanCleanup(owner, generationId, storagePath);
    } catch {
      // If durable enqueue itself failed, still make one immediate cleanup
      // attempt. Never report success for an ineligible result.
      await persistence.remove(storagePath).catch(() => undefined);
      throw serverError("Couldn't store the generated image.");
    }
    await persistence.remove(storagePath);
    // A failed completion update is safe: the persistent job will retry the
    // idempotent Storage removal and verify absence before completing.
    await persistence.completeOrphanCleanup(storagePath).catch(() => undefined);
    throw serverError("Couldn't store the generated image.");
  }
}
