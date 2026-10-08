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
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createLogger } from "../_shared/logger.ts";
import {
  deletionDeps,
  processPreparedDeletion,
  type StudioDeletionDeps,
} from "../studio/deletion.ts";

const limiter = createRateLimiter({ limit: 30, windowMs: 60_000 });

async function readPath(req: Request, userID: string): Promise<string> {
  if (!req.body) throw badRequest("A reference photo is required.");
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const chunk = await reader.read();
    if (chunk.done) break;
    size += chunk.value.byteLength;
    if (size > 2048) {
      await reader.cancel();
      throw badRequest("The request is too large.");
    }
    chunks.push(chunk.value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw badRequest("The request must contain valid JSON.");
  }
  const path = body !== null && typeof body === "object" && !Array.isArray(body)
    ? (body as Record<string, unknown>)["path"]
    : undefined;
  if (
    typeof path !== "string" ||
    !new RegExp(
      `^users/${userID.toLowerCase()}/references/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.jpg$`,
    ).test(path)
  ) {
    throw badRequest("Choose a reference photo from your own profile.");
  }
  return path;
}

export async function handleReferenceDelete(
  req: Request,
  deps: StudioDeletionDeps,
): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  const requestID = resolveRequestId(req);
  const started = Date.now();
  try {
    if (req.method !== "DELETE") throw methodNotAllowed();
    const userID = await authenticateRequest(req, deps.authClient);
    if (!limiter.check(userID, Date.now()).allowed) {
      throw new AppError("rate_limited", 429, "Too many requests. Try again shortly.");
    }
    const path = await readPath(req, userID);
    const job = await deps.prepare(userID, path);
    const status = await processPreparedDeletion(job, userID, deps);
    createLogger(requestID).info("reference_delete.accepted", {
      status,
      latency_ms: Date.now() - started,
    });
    // The reference itself can finish while child-file jobs remain pending.
    // Their status is available through the owned cleanup queue, never its paths.
    return jsonResponse({ id: job.id, status }, {
      status: status === "complete" ? 200 : 202,
      requestId: requestID,
      extraHeaders: CORS_HEADERS,
    });
  } catch (error) {
    return errorResponse(
      error instanceof AppError
        ? error
        : serverError("Couldn't remove that reference photo. Try again."),
      requestID,
      CORS_HEADERS,
    );
  }
}

export function referenceDeletionDeps(
  authClient: AuthClient,
  service: SupabaseClient,
): StudioDeletionDeps {
  return {
    ...deletionDeps(authClient, service),
    async prepare(userID, path) {
      const { data, error } = await service.rpc("prepare_reference_deletion", {
        p_user_id: userID,
        p_path: path,
      });
      if (error?.message.includes("reference_photo_unavailable")) {
        throw notFound("That reference photo is no longer saved.");
      }
      if (error?.message.includes("reference_photo_in_progress")) {
        throw new AppError(
          "validation",
          409,
          "A preview using this photo is in progress. Try again when it finishes.",
        );
      }
      if (error || !data) throw serverError("Couldn't prepare reference-photo removal.");
      return data;
    },
  };
}
