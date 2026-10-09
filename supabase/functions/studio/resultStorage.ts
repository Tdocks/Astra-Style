import { serverError } from "../_shared/errors.ts";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export interface StudioResultPersistence {
  hasLiveOwnedGeneration(userId: string, generationId: string): Promise<boolean>;
  upload(path: string, bytes: Uint8Array, contentType: string): Promise<void>;
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

  if (!await persistence.hasLiveOwnedGeneration(owner, generationId)) {
    throw serverError("Couldn't store the generated image.");
  }

  await persistence.upload(storagePath, bytes, contentType);
}
