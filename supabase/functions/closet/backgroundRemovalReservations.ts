import type { SupabaseClient } from "@supabase/supabase-js";
import { ProviderError } from "../_shared/providers/types.ts";
import type { RemovalClaim, RemovalReservations } from "./backgroundRemoval.ts";
/** Construct with the server service client, never a caller JWT client. */
export class SupabaseRemovalReservations implements RemovalReservations {
  constructor(private readonly admin: SupabaseClient) {}
  private async call(name: string, args: Record<string, unknown>): Promise<unknown> {
    const { data, error } = await this.admin.rpc(name, args);
    if (error) {
      if (error.message === "cutout_quota_exhausted") {
        throw new ProviderError(
          "PROVIDER_QUOTA_EXCEEDED",
          false,
          "Photo processing limit reached.",
        );
      }
      // Ambiguous dispatch must never suggest an automatic vendor retry.
      throw new ProviderError("PROVIDER_UNAVAILABLE", false, "Couldn't prepare that cutout.");
    }
    return data;
  }
  async claim(userId: string, source: string, key: string): Promise<RemovalClaim> {
    const data = await this.call("claim_closet_cutout", {
      p_user: userId,
      p_source: source,
      p_key: key,
    });
    if (typeof data === "object" && data !== null) {
      const r = data as Record<string, unknown>;
      if (r.state === "pending") return { state: "pending" };
      if (r.state === "complete" && typeof r.path === "string" && r.path.length > 0) {
        return { state: "complete", path: r.path };
      }
      if (r.state === "reserved" && typeof r.token === "string" && r.token.length > 0) {
        return { state: "reserved", token: r.token };
      }
    }
    throw new ProviderError("PROVIDER_UNAVAILABLE", false, "Couldn't prepare that cutout.");
  }
  async beginProvider(token: string): Promise<void> {
    await this.call("begin_closet_cutout", { p_token: token });
  }
  async complete(token: string, path: string): Promise<void> {
    await this.call("complete_closet_cutout", { p_token: token, p_path: path });
  }
  async fail(token: string, providerAttempted: boolean): Promise<void> {
    await this.call("fail_closet_cutout", { p_token: token, p_attempted: providerAttempted });
  }
}
