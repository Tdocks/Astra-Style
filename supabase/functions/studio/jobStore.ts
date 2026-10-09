import type { SupabaseClient } from "@supabase/supabase-js";
import { AppError, badRequest, serverError } from "../_shared/errors.ts";
import { quotaPeriod, studioQuotaExceededError } from "./quota.ts";
import type { StudioGenerationRow, StudioJobStore, StudioStatus } from "./handler.ts";

async function monthlyQuotaError(
  supabase: SupabaseClient,
  userID: string,
  message: string,
): Promise<AppError> {
  const now = new Date();
  const period = quotaPeriod(now);
  const [configuration, usage] = await Promise.all([
    supabase.from("studio_quota_config")
      .select("premium_monthly_limit").eq("singleton", true).single(),
    supabase.from("studio_allowances").select("id", { count: "exact", head: true })
      .eq("user_id", userID).is("released_at", null)
      .gte("created_at", period.start).lt("created_at", period.reset),
  ]);
  if (configuration.error || !configuration.data || usage.error || usage.count === null) {
    return serverError("Couldn't load your preview allowance.");
  }
  const limitCount = configuration.data.premium_monthly_limit;
  return studioQuotaExceededError(
    "studio_generation_monthly",
    limitCount,
    Math.max(0, limitCount - usage.count),
    period.reset,
    message,
  );
}

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
    altDescription: (data["alt_description"] as string | null) ?? null,
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
    async enqueueHiResExport(userId, sourceGenerationId, consent, provider) {
      const { data, error } = await supabase.rpc("enqueue_studio_hi_res_export", {
        p_user_id: userId,
        p_source_generation_id: sourceGenerationId,
        p_provider: provider,
        p_consent_acknowledged: consent.acknowledged,
        p_consent_terms_version: consent.termsVersion || null,
      }).single();
      if (error?.message?.includes("studio_monthly_quota_exhausted")) {
        throw await monthlyQuotaError(
          supabase,
          userId,
          "You've used your monthly Studio render allowance. It resets on the first day of next month (UTC).",
        );
      }
      if (error?.message?.includes("studio_hi_res_premium_required")) {
        throw new AppError("auth", 403, "Higher-quality export is available with Premium.");
      }
      if (error?.message?.includes("studio_hi_res_provider_unavailable")) {
        throw new AppError(
          "provider",
          503,
          "Higher-quality export is temporarily unavailable. Try again later.",
        );
      }
      if (error?.message?.includes("studio_export_already_removed")) {
        throw new AppError("validation", 409, "That higher-quality export was already removed.");
      }
      if (error?.message?.includes("studio_export_consent_required")) {
        throw badRequest(
          "Confirm the current reference-photo terms before exporting this estimate.",
        );
      }
      if (error?.message?.includes("studio_export_source_unavailable")) {
        throw new AppError(
          "validation",
          404,
          "That Studio estimate is no longer available to export.",
        );
      }
      if (error || !data) throw serverError("Couldn't queue the higher-quality export.");
      return mapRow(data as Record<string, unknown>);
    },
    async insert(row) {
      const { data, error } = await supabase.rpc(
        row.cacheKey
          ? "enqueue_studio_generation_cached"
          : (row.requestKey ? "enqueue_studio_generation_idempotent" : "enqueue_studio_generation"),
        {
          ...(row.cacheKey ? { p_cache_key: row.cacheKey } : {}),
          ...(row.cacheKey
            ? { p_request_key: row.requestKey ?? null, p_request_hash: row.requestHash ?? null }
            : row.requestKey
            ? { p_request_key: row.requestKey, p_request_hash: row.requestHash }
            : {}),
          p_user_id: row.userId,
          p_reference_image_path: row.referenceImagePath,
          p_outfit_id: row.outfitId,
          p_prompt_payload: row.promptPayload,
          p_provider: row.provider,
          ...(!row.cacheKey ? { p_retry_of: row.retryOf ?? null } : {}),
        },
      ).single();
      if (error?.message?.includes("studio_monthly_quota_exhausted")) {
        throw await monthlyQuotaError(
          supabase,
          row.userId,
          "You've used your monthly preview allowance. It resets on the first day of next month (UTC).",
        );
      }
      if (error?.message?.includes("studio_trial_exhausted")) {
        throw studioQuotaExceededError(
          "studio_trial_generation",
          1,
          0,
          null,
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
      if (error?.message?.includes("studio_confirmation_unavailable")) {
        throw new AppError(
          "validation",
          409,
          "This preview confirmation expired or was cancelled. Ask Kyra for a new preview.",
        );
      }
      if (error?.message?.includes("studio_request_conflict")) {
        throw new AppError(
          "validation",
          409,
          "This request key was already used for a different preview.",
        );
      }
      if (error?.message?.includes("studio_request_removed")) {
        throw new AppError("validation", 409, "That preview was removed. Start a new request.");
      }
      if (error || !data) throw serverError("Couldn't enqueue the generation job.");
      return mapRow(data as Record<string, unknown>);
    },
    async findSemanticCache(userId, cacheKey) {
      const { data, error } = await supabase.rpc("find_studio_generation_cache", {
        p_user_id: userId,
        p_cache_key: cacheKey,
      }).maybeSingle();
      if (error) throw serverError("Couldn't check for an equivalent preview.");
      return data ? mapRow(data as Record<string, unknown>) : null;
    },
    async findSubmission(userId, key, hash) {
      const { data, error } = await supabase.from("studio_submission_requests")
        .select("request_hash,generation_id").eq("user_id", userId).eq("request_key", key)
        .maybeSingle();
      if (error) throw serverError("Couldn't check the preview request.");
      if (!data) return null;
      if (data.request_hash !== hash) {
        throw new AppError(
          "validation",
          409,
          "This request key was already used for a different preview.",
        );
      }
      const { data: generation, error: lookupError } = await supabase.from("studio_generations")
        .select("*").eq("user_id", userId).eq("id", data.generation_id).is("deleted_at", null)
        .maybeSingle();
      if (lookupError) throw serverError("Couldn't retrieve the preview request.");
      if (!generation) {
        throw new AppError("validation", 409, "That preview was removed. Start a new request.");
      }
      return mapRow(generation);
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
