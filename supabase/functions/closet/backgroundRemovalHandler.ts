import { type AuthClient, authenticateUser } from "../_shared/jwt.ts";
import {
  AppError,
  badRequest,
  errorResponse,
  jsonResponse,
  methodNotAllowed,
  rateLimited,
  serverError,
} from "../_shared/errors.ts";
import { CORS_HEADERS, handleCorsPreflight } from "../_shared/cors.ts";
import { createLogger } from "../_shared/logger.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { ProviderError, type ProviderRequestContext } from "../_shared/providers/types.ts";
import { parseEnvelope, parseIdempotencyKey } from "./schema.ts";
async function boundedJSON(req: Request): Promise<unknown> {
  const reader = req.body?.getReader();
  if (!reader) throw badRequest("Choose a capture to process.");
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      length += chunk.value.byteLength;
      if (length > 16_384) {
        await reader.cancel();
        throw badRequest("Photo request is too large.");
      }
      chunks.push(chunk.value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw badRequest("Invalid photo request.");
  }
}
export async function handleBackgroundRemoval(req: Request, deps: {
  authClient: AuthClient;
  rateLimiter: RateLimiter;
  enabled: boolean;
  run(source: string, adequate: boolean, ctx: ProviderRequestContext): Promise<string | null>;
}): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  const requestId = resolveRequestId(req);
  const logger = createLogger(requestId);
  const started = Date.now();
  const headers = { ...CORS_HEADERS, "Cache-Control": "no-store" };
  try {
    if (req.method !== "POST") throw methodNotAllowed();
    const user = await authenticateUser(req, deps.authClient);
    if (user.is_anonymous !== false) {
      throw new AppError("auth", 403, "Sign in to process this photo.");
    }
    if (!deps.rateLimiter.check(user.id, Date.now()).allowed) throw rateLimited();
    const key = parseIdempotencyKey(req.headers.get("Idempotency-Key"));
    const { body } = parseEnvelope(await boundedJSON(req));
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      throw badRequest("Invalid photo request.");
    }
    const input = body as Record<string, unknown>;
    const uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
    if (
      !new RegExp("^" + uuid + "$").test(user.id) || typeof input.storage_path !== "string" ||
      !new RegExp("^users/" + user.id + "/closet/" + uuid + "\\.jpg$").test(input.storage_path) ||
      typeof input.device_adequate !== "boolean"
    ) throw badRequest("Choose a valid capture.");
    if (!input.device_adequate && !deps.enabled) {
      throw new AppError("provider", 503, "Photo processing is unavailable.");
    }
    const path = input.device_adequate ? null : await deps.run(input.storage_path, false, {
      userId: user.id,
      requestId,
      timeoutMs: 30_000,
      idempotencyKey: key,
    });
    logger.info("closet_cutout.completed", { duration_ms: Date.now() - started });
    return jsonResponse({ background_removed_path: path }, { requestId, extraHeaders: headers });
  } catch (error) {
    const failure = error instanceof AppError
      ? error
      : error instanceof ProviderError
      ? new AppError(
        "provider",
        error.code === "INVALID_INPUT" ? 400 : error.code === "PROVIDER_QUOTA_EXCEEDED" ? 429 : 503,
        error.message,
      )
      : serverError("Couldn't process that photo.");
    logger.error("closet_cutout.failed", {
      category: failure.category,
      duration_ms: Date.now() - started,
    });
    return errorResponse(failure, requestId, headers);
  }
}
