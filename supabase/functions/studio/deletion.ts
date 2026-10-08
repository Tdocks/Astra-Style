import type { SupabaseClient } from "@supabase/supabase-js";
import { CORS_HEADERS, handleCorsPreflight } from "../_shared/cors.ts";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import {
  AppError,
  badRequest,
  errorResponse,
  jsonResponse,
  methodNotAllowed,
  notFound,
  serverError,
} from "../_shared/errors.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { isUUID } from "../_shared/validation.ts";
import { type RetentionJob, validResultPath } from "../studio-retention/handler.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createLogger } from "../_shared/logger.ts";

const deletionLimiter = createRateLimiter({ limit: 30, windowMs: 60_000 });

type DeletionJob = RetentionJob & { status: "pending" | "processing" | "complete" };
export interface StudioDeletionDeps {
  authClient: AuthClient;
  prepare(userID: string, generationID: string): Promise<DeletionJob>;
  claim(userID: string, jobID: string, token: string): Promise<DeletionJob | null>;
  finish(jobID: string, token: string, succeeded: boolean): Promise<boolean>;
  removeImage(path: string): Promise<void>;
  token(): string;
}

/** Shared fenced cleanup for an already accepted, owner-scoped deletion job. */
export async function processPreparedDeletion(
  prepared: DeletionJob,
  userID: string,
  deps: StudioDeletionDeps,
): Promise<"pending" | "complete"> {
  if (prepared.user_id !== userID) throw serverError();
  if (prepared.status === "complete") return "complete";
  const token = deps.token();
  let claimed: DeletionJob | null;
  try {
    claimed = await deps.claim(userID, prepared.id, token);
  } catch {
    return "pending";
  }
  if (!claimed) return "pending";
  try {
    if (claimed.user_id !== userID || !validResultPath(claimed)) throw serverError();
    if (claimed.result_image_path !== null) await deps.removeImage(claimed.result_image_path);
    return await deps.finish(claimed.id, token, true) ? "complete" : "pending";
  } catch {
    try {
      await deps.finish(claimed.id, token, false);
    } catch { /* Expiring the claim also recovers this accepted job. */ }
    return "pending";
  }
}

/** The client never sees a privileged path, lease token or Storage response. */
export async function handleDelete(
  req: Request,
  deps: StudioDeletionDeps,
  generationID: string,
): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  const requestID = resolveRequestId(req);
  const reply = (id: string, status: "pending" | "complete") =>
    jsonResponse({ id, status }, {
      status: status === "complete" ? 200 : 202,
      requestId: requestID,
      extraHeaders: CORS_HEADERS,
    });
  try {
    if (req.method !== "DELETE") throw methodNotAllowed();
    if (!isUUID(generationID)) throw badRequest("Generation id must be a UUID.");
    const userID = await authenticateRequest(req, deps.authClient);
    if (!deletionLimiter.check(userID, Date.now()).allowed) {
      throw new AppError("rate_limited", 429, "Too many requests. Try again shortly.");
    }
    const prepared = await deps.prepare(userID, generationID);
    createLogger(requestID).info("studio_delete.accepted", { status: prepared.status });
    return reply(prepared.id, await processPreparedDeletion(prepared, userID, deps));
  } catch (error) {
    return errorResponse(
      error instanceof AppError ? error : serverError("Couldn't remove that estimate. Try again."),
      requestID,
      CORS_HEADERS,
    );
  }
}

export function deletionDeps(authClient: AuthClient, service: SupabaseClient): StudioDeletionDeps {
  return {
    authClient,
    token: () => crypto.randomUUID(),
    async prepare(userID, generationID) {
      const { data, error } = await service.rpc("prepare_studio_deletion", {
        p_user_id: userID,
        p_generation_id: generationID,
      });
      if (error?.message.includes("studio_delete_unavailable")) {
        throw notFound("That estimate is no longer available.");
      }
      if (error?.message.includes("studio_delete_in_progress")) {
        throw new AppError(
          "validation",
          409,
          "Wait for this estimate to finish before deleting it.",
        );
      }
      if (error?.message.includes("studio_delete_has_variations")) {
        throw new AppError(
          "validation",
          409,
          "Another variation uses this image. Delete its newer variations first, then try again.",
        );
      }
      if (error || !data) throw serverError("Couldn't prepare image removal.");
      return data as DeletionJob;
    },
    async claim(userID, jobID, token) {
      const { data, error } = await service.rpc("claim_studio_deletion", {
        p_user_id: userID,
        p_job_id: jobID,
        p_token: token,
      }).maybeSingle();
      if (error) throw serverError("Couldn't start image removal.");
      return data as DeletionJob | null;
    },
    async finish(jobID, token, succeeded) {
      const { data, error } = await service.rpc("finish_studio_retention", {
        p_job_id: jobID,
        p_token: token,
        p_succeeded: succeeded,
      });
      if (error) throw serverError("Image removal will be retried.");
      return data === true;
    },
    async removeImage(path) {
      const { error } = await service.storage.from("user-content").remove([path]);
      if (error) throw serverError("Image removal will be retried.");
    },
  };
}
