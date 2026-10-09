import type { SupabaseClient } from "@supabase/supabase-js";
import { ProviderError } from "../_shared/providers/types.ts";
import type { RemovalStorage } from "./backgroundRemoval.ts";
const MAX_BYTES = 8 * 1024 * 1024;
const UUID_PATTERN = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
/** Use a caller JWT client and verified owner ID; storage RLS remains enforced. */
export class SupabaseRemovalStorage implements RemovalStorage {
  constructor(private readonly caller: SupabaseClient, private readonly ownerId: string) {}

  private validate(userId: string, path: string, output: boolean): void {
    const suffix = output ? "-cutout\\.png" : "\\.jpg";
    if (
      userId !== this.ownerId || !new RegExp("^" + UUID_PATTERN + "$").test(userId) ||
      !new RegExp("^users/" + userId + "/closet/" + UUID_PATTERN + suffix + "$").test(path)
    ) {
      throw new ProviderError("INVALID_INPUT", false, "That photo is unavailable.");
    }
  }
  async loadOwned(userId: string, path: string): Promise<Uint8Array> {
    this.validate(userId, path, false);
    const { data, error } = await this.caller.storage.from("user-content").download(path);
    if (error || !data || data.size === 0 || data.size > MAX_BYTES) {
      throw new ProviderError("INVALID_INPUT", false, "That capture is unavailable.");
    }
    return new Uint8Array(await data.arrayBuffer());
  }
  async saveOwned(userId: string, path: string, bytes: Uint8Array): Promise<void> {
    this.validate(userId, path, true);
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_BYTES) {
      throw new ProviderError("INVALID_INPUT", false, "That cutout is unavailable.");
    }
    const { error } = await this.caller.storage.from("user-content").upload(path, bytes, {
      contentType: "image/png",
      upsert: false,
    });
    if (error) throw new ProviderError("PROVIDER_UNAVAILABLE", false, "Couldn't save that cutout.");
  }
  async existsOwned(userId: string, path: string): Promise<boolean> {
    this.validate(userId, path, true);
    const { data, error } = await this.caller.storage.from("user-content").download(path);
    if (error) {
      // Pinned storage-js wraps download HTTP failures in StorageUnknownError.
      const response = "originalError" in error && error.originalError instanceof Response
        ? error.originalError
        : null;
      const missing = ("status" in error && error.status === 404) || response?.status === 404;
      await response?.body?.cancel();
      if (missing) return false;
      throw new ProviderError("PROVIDER_UNAVAILABLE", false, "Couldn't load that cutout.");
    }
    return !!data && data.size > 0 && data.size <= MAX_BYTES;
  }
}
