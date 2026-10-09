import type { BackgroundRemovalProvider } from "../_shared/providers/removeBgBackgroundRemoval.ts";
import { ProviderError, type ProviderRequestContext } from "../_shared/providers/types.ts";

export type RemovalClaim = { state: "complete"; path: string } | {
  state: "reserved";
  token: string;
} | { state: "pending" };
export interface RemovalReservations {
  claim(userId: string, source: string, key: string): Promise<RemovalClaim>;
  beginProvider(token: string): Promise<void>;
  complete(token: string, path: string): Promise<void>;
  fail(token: string, providerAttempted: boolean): Promise<void>;
}
export interface RemovalStorage {
  loadOwned(userId: string, path: string): Promise<Uint8Array>;
  saveOwned(userId: string, path: string, bytes: Uint8Array): Promise<void>;
  existsOwned(userId: string, path: string): Promise<boolean>;
}
/** Storage and reservation adapters must enforce ownership and durable claims, not process-local maps. */
export async function fallbackBackgroundRemoval(
  source: string,
  deviceAdequate: boolean,
  ctx: ProviderRequestContext,
  deps: {
    provider: BackgroundRemovalProvider;
    reservations: RemovalReservations;
    storage: RemovalStorage;
  },
): Promise<string | null> {
  if (deviceAdequate) return null;
  const uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
  if (
    !new RegExp("^" + uuid + "$").test(ctx.userId) || !ctx.idempotencyKey ||
    !new RegExp("^users/" + ctx.userId + "/closet/" + uuid + "\\.jpg$").test(source)
  ) {
    throw new ProviderError("INVALID_INPUT", false, "That capture is unavailable.");
  }
  const output = source.replace(/\.jpg$/, "-cutout.png");
  const image = await deps.storage.loadOwned(ctx.userId, source);
  if (image.byteLength === 0 || image.byteLength > 8 * 1024 * 1024) {
    throw new ProviderError("INVALID_INPUT", false, "That capture is unavailable.");
  }
  const claim = await deps.reservations.claim(ctx.userId, source, ctx.idempotencyKey);
  if (claim.state === "pending") return null;
  if (claim.state === "complete") {
    if (claim.path !== output) {
      throw new ProviderError("INVALID_INPUT", false, "That cutout is unavailable.");
    }
    return await deps.storage.existsOwned(ctx.userId, output) ? output : null;
  }
  let attempted = false;
  try {
    // The durable dispatch marker may commit even if its response is lost.
    // Treat that uncertainty as attempted so failure cannot release a paid retry.
    attempted = true;
    await deps.reservations.beginProvider(claim.token);
    const cutout = await deps.provider.remove(image, ctx);
    await deps.storage.saveOwned(ctx.userId, output, cutout);
    await deps.reservations.complete(claim.token, output);
    return output;
  } catch (error) {
    // After provider dispatch, an error must not make the request chargeable again.
    await deps.reservations.fail(claim.token, attempted);
    throw error;
  }
}
