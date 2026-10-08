import type { SupabaseClient } from "@supabase/supabase-js";
import { AppError, badRequest, serverError } from "../_shared/errors.ts";
import type { StudioGenerationRow, StudioJobStore, StudioStatus } from "./handler.ts";

function mapRow(data: Record<string, unknown>): StudioGenerationRow {
  return {
    id: data["id"] as string,
    userId: data["user_id"] as string,
    referenceImagePath: (data["reference_image_path"] as string | null) ?? "",
    outfitId: (data["outfit_id"] as string | null) ?? null,
    promptPayload: (data["prompt_payload"] as Record<string, unknown> | null) ?? {},
    status: data["status"] as StudioStatus,
    resultImagePath: (data["result_image_path"] as string | null) ?? null,
    provider: (data["provider"] as string | null) ?? null,
    errorMessage: (data["error_message"] as string | null) ?? null,
    deletedAt: (data["deleted_at"] as string | null) ?? null,
    retentionExpiresAt: (data["retention_expires_at"] as string | null) ?? null,
    createdAt: data["created_at"] as string,
    updatedAt: data["updated_at"] as string,
  };
}

/** Privileged client restricted to server-owned jobs. Every operation fences
 * by the verified user ID, including leases and allowance reads (ADR 0022). */
export function supabaseJobStore(supabase: SupabaseClient): StudioJobStore {
  return {
    async insert(row) {
      const { data, error } = await supabase.rpc("enqueue_studio_generation", {
        p_user_id: row.userId,
        p_reference_image_path: row.referenceImagePath,
        p_outfit_id: row.outfitId,
        p_prompt_payload: row.promptPayload,
        p_provider: row.provider,
        p_retry_of: row.retryOf ?? null,
      }).single();
      if (error?.message?.includes("studio_trial_exhausted")) {
        throw new AppError(
          "rate_limited",
          429,
          "You've used your free visual estimate. Upgrade to Astra Style Premium for more.",
        );
      }
      if (error?.message?.includes("studio_retry_unavailable")) {
        throw badRequest("That estimate can't be retried.");
      }
      if (error?.message?.includes("studio_outfit_unavailable")) {
        throw badRequest("That outfit is no longer available.");
      }
      if (error?.message?.includes("studio_source_unavailable")) {
        throw badRequest(
          "That source estimate expired or was removed. Generate a fresh inspiration instead.",
        );
      }
      if (error || !data) throw serverError("Couldn't enqueue the generation job.");
      return mapRow(data as Record<string, unknown>);
    },
    async get(userId, id) {
      const { data, error } = await supabase.from("studio_generations").select("*")
        .eq("user_id", userId).eq("id", id).maybeSingle();
      if (error) throw serverError("Couldn't load the generation job.");
      return data ? mapRow(data as Record<string, unknown>) : null;
    },
    async update(userId, id, patch, claimToken) {
      if (!claimToken) throw serverError("Generation job has no active claim.");
      const updates: Record<string, unknown> = {};
      if (patch.status !== undefined) updates["status"] = patch.status;
      if (patch.resultImagePath !== undefined) updates["result_image_path"] = patch.resultImagePath;
      if (patch.errorMessage !== undefined) updates["error_message"] = patch.errorMessage;
      if (patch.promptPayload !== undefined) updates["prompt_payload"] = patch.promptPayload;
      const { data, error } = await supabase.from("studio_generations").update(updates)
        .eq("user_id", userId).eq("id", id).eq("claim_token", claimToken).select("*").single();
      if (error || !data) throw serverError("Couldn't update the generation job.");
      return mapRow(data as Record<string, unknown>);
    },
    async claim(userId, id) {
      const token = crypto.randomUUID();
      const { data, error } = await supabase.rpc("claim_studio_generation", {
        p_user_id: userId,
        p_generation_id: id,
        p_claim_token: token,
      }).maybeSingle();
      if (error) throw serverError("Couldn't claim the generation job.");
      return data ? { row: mapRow(data as Record<string, unknown>), token } : null;
    },
    async release(userId, id, token) {
      const { error } = await supabase.from("studio_generations")
        .update({ claim_token: null, claim_expires_at: null })
        .eq("user_id", userId).eq("id", id).eq("claim_token", token);
      if (error) throw serverError("Couldn't release the generation job.");
    },
    async countForUser(userId) {
      const { count, error } = await supabase.from("studio_allowances")
        .select("id", { count: "exact", head: true }).eq("user_id", userId).is("released_at", null);
      if (error) throw serverError("Couldn't check your visual estimate allowance.");
      return count ?? 0;
    },
  };
}
