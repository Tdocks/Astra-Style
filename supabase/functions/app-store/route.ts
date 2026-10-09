import { AppError, badRequest, errorResponse, serverError } from "../_shared/errors.ts";
import { createLogger } from "../_shared/logger.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { type AppStoreWebhookStore, handleAppStoreWebhook } from "./handler.ts";
import type { AppStoreSignedDataVerifier } from "../_shared/appStoreVerifier.ts";

export interface AppStoreWebhookRouteDependencies {
  readonly store: AppStoreWebhookStore;
  readonly verifier: AppStoreSignedDataVerifier;
  readonly inboundRateLimiter: RateLimiter;
  readonly verifiedBundleRateLimiter: RateLimiter;
  readonly now: () => Date;
}

/**
 * Apple authenticates notifications with signed JWS data rather than a user
 * JWT. Keep the inbound limiter global per isolate because forwarded client IP
 * headers are not a trusted identity; verified event payloads are never logged.
 */
export function createAppStoreWebhookRoute(
  deps: AppStoreWebhookRouteDependencies,
): (req: Request) => Promise<Response> {
  return async (req) => {
    const startedAt = deps.now().getTime();
    const requestId = resolveRequestId(req);
    const logger = createLogger(requestId);
    try {
      const limit = deps.inboundRateLimiter.check("app-store-webhook", startedAt);
      if (!limit.allowed) {
        logger.warn("app_store_webhook.rate_limited", {
          retry_after_seconds: limit.retryAfterSeconds,
          latency_ms: Math.max(0, deps.now().getTime() - startedAt),
        });
        return errorResponse(
          new AppError(
            "rate_limited",
            429,
            "Too many requests. Please try again shortly.",
            limit.retryAfterSeconds,
          ),
          requestId,
        );
      }

      const raw = await req.text();
      if (raw.length > 100_000) throw badRequest("Apple notification is too large.");
      let body: unknown;
      try {
        body = JSON.parse(raw);
      } catch {
        throw badRequest("Apple notification body must be valid JSON.");
      }
      if (typeof body !== "object" || body === null || Array.isArray(body)) {
        throw badRequest("Apple notification body must be an object.");
      }
      const signedPayload = (body as Record<string, unknown>)["signedPayload"];
      if (typeof signedPayload !== "string" || signedPayload.length > 80_000) {
        throw badRequest("Apple notification is missing its signed payload.");
      }

      const result = await handleAppStoreWebhook(signedPayload, {
        store: deps.store,
        verifier: deps.verifier,
        rateLimiter: deps.verifiedBundleRateLimiter,
        now: deps.now,
      });
      const latencyMs = Math.max(0, deps.now().getTime() - startedAt);
      logger.info("app_store_webhook.completed", { result, latency_ms: latencyMs });
      return Response.json({ received: true, result }, {
        status: 200,
        headers: { "x-request-id": requestId },
      });
    } catch (error) {
      const appError = typeof error === "object" && error !== null && "status" in error &&
          "category" in error
        ? error as Parameters<typeof errorResponse>[0]
        : serverError();
      const latencyMs = Math.max(0, deps.now().getTime() - startedAt);
      logger.warn("app_store_webhook.rejected", {
        category: appError.category,
        status: appError.status,
        latency_ms: latencyMs,
      });
      return errorResponse(appError, requestId);
    }
  };
}
