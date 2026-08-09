// ============================================================================
// closet/handler.ts
// ============================================================================
// Handlers for the `closet` Edge Function (spec §14):
//   POST /analyze-item     — synchronous single-item analysis + idempotency
//   POST /batch-analyze    — enqueue a job, return job_id (never sync fan-out)
//   GET  /batch-status/:id — advance the job and return status/results
//
// Spec §14's six per-endpoint requirements (JWT, rate limit, schema,
// ownership, request-id logging, no private image/prompt logging) are
// implemented below. Ownership: `userId` is JWT-derived only; storage paths
// must live under `users/{uid}/`; job rows are scoped by RLS + the JWT id.
// ============================================================================

import { CORS_HEADERS, handleCorsPreflight } from "../_shared/cors.ts";
import {
  AppError,
  badRequest,
  errorResponse,
  jsonResponse,
  methodNotAllowed,
  notFound,
  serverError,
} from "../_shared/errors.ts";
import { createLogger } from "../_shared/logger.ts";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { ProviderError } from "../_shared/providers/types.ts";
import type { VisionAnalysisProvider } from "../_shared/providers/visionAnalysis.ts";
import { isUUID } from "../_shared/validation.ts";
import { degradedResultFromHints, mapProviderResultToWire } from "./mapper.ts";
import {
  type AnalyzeItemElement,
  type AnalyzeItemRequestBody,
  assertOwnsStoragePath,
  type BatchJobEnqueueDTO,
  type BatchJobStatusDTO,
  type ClosetItemAnalysisBatchItemDTO,
  type ClosetItemAnalysisResultDTO,
  parseAnalyzeItemBody,
  parseBatchAnalyzeBody,
  parseEnvelope,
  parseIdempotencyKey,
} from "./schema.ts";

/**
 * When to give up on the vision provider.
 *
 * This was 5_500 — `docs/08` §2.4's "≤ 5.5s p50" budget, used as a hard
 * abort deadline. Those are different quantities and confusing them is not a
 * tuning mistake, it is a category error: a p50 is the MEDIAN, so an abort set
 * at the p50 kills about half of all calls by construction. §2.5.3's own
 * measurements said so before this shipped — p50 3.8-4.0s but p95 4.5-5.8s,
 * with a maximum of 5796ms across 24 readings of a single easy photograph.
 * The maximum was already past the deadline.
 *
 * It failed the way that arithmetic predicts: intermittently, on nothing the
 * user did, and worst on the garments that take the model longest to read — a
 * fine-striped textured knit on a cluttered sofa, exactly the photograph a man
 * would expect an app called Astra Style to handle. The client reported it as
 * "couldn't be read just now", which was true and useless.
 *
 * Aborting early does not even save money. The provider has begun generating
 * and the tokens are billed whether or not we wait for the answer, so a
 * too-short deadline pays full price for a result it throws away, and then
 * pays again when the user rescans.
 *
 * 20s is a deadline, not a target. §2.4's budget is unchanged and still the
 * thing to measure against; this is the point past which something is wrong
 * rather than slow. Set from the tail with headroom, which is the only place a
 * timeout can honestly come from.
 */
const PROVIDER_TIMEOUT_MS = 20_000;

export interface IdempotencyStore {
  get(
    userId: string,
    key: string,
  ): Promise<{ requestHash: string; responsePayload: ClosetItemAnalysisResultDTO } | null>;
  put(
    userId: string,
    key: string,
    requestHash: string,
    responsePayload: ClosetItemAnalysisResultDTO,
  ): Promise<void>;
}

export type JobStatus = "queued" | "generating" | "complete" | "failed";

export interface AnalysisJobRow {
  id: string;
  userId: string;
  status: JobStatus;
  items: AnalyzeItemElement[];
  results: ClosetItemAnalysisBatchItemDTO[];
  errorMessage?: string;
}

export interface AnalysisJobStore {
  create(userId: string, items: AnalyzeItemElement[]): Promise<AnalysisJobRow>;
  get(userId: string, jobId: string): Promise<AnalysisJobRow | null>;
  save(job: AnalysisJobRow): Promise<void>;
}

export interface AnalyzeHandlerDeps {
  authClient: AuthClient;
  provider: VisionAnalysisProvider;
  idempotencyStore: IdempotencyStore;
  rateLimiter: RateLimiter;
  now: () => Date;
  hashRequest: (canonical: string) => Promise<string>;
}

export interface BatchHandlerDeps {
  authClient: AuthClient;
  provider: VisionAnalysisProvider;
  jobStore: AnalysisJobStore;
  rateLimiter: RateLimiter;
  now: () => Date;
}

async function readJsonBody(req: Request): Promise<unknown> {
  const text = await req.text();
  if (text.trim().length === 0) {
    throw badRequest("Request body must not be empty.");
  }
  try {
    return JSON.parse(text);
  } catch {
    throw badRequest("Request body must be valid JSON.");
  }
}

function canonicalAnalyzeBody(body: AnalyzeItemRequestBody): string {
  return JSON.stringify({
    request_id: body.requestId,
    storage_path: body.storagePath,
    image_type: body.imageType,
    device_hints: body.deviceHints ?? null,
  });
}

function failureReasonFromProvider(err: ProviderError): string {
  switch (err.code) {
    case "TIMEOUT":
      return "timed_out";
    case "RATE_LIMITED":
      return "rate_limited";
    case "INVALID_INPUT":
      return "image_unusable";
    case "CONTENT_MODERATION_REJECTED":
      return "no_garment_detected";
    default:
      return "provider_unavailable";
  }
}

async function analyzeOne(
  provider: VisionAnalysisProvider,
  element: AnalyzeItemElement,
  userId: string,
  requestId: string,
  idempotencyKey?: string,
): Promise<ClosetItemAnalysisBatchItemDTO> {
  assertOwnsStoragePath(element.storagePath, userId);
  try {
    const providerResult = await provider.analyzeGarment(
      {
        imageStoragePath: element.storagePath,
        deviceHints: element.deviceHints
          ? {
            dominantColorsRgb: element.deviceHints.dominantColorsRgb,
            detectedText: element.deviceHints.detectedText,
            approximateCategory: element.deviceHints.approximateCategory,
          }
          : undefined,
      },
      {
        requestId,
        userId,
        timeoutMs: PROVIDER_TIMEOUT_MS,
        idempotencyKey,
      },
    );
    const result = mapProviderResultToWire(providerResult, {
      deviceHints: element.deviceHints,
    });
    return { request_id: element.requestId, result };
  } catch (err) {
    if (err instanceof ProviderError) {
      // docs/08 §2.2: exhausted / unavailable → degraded draft, not a hard
      // failure of item creation. For batch we still surface per-item
      // failure when the image itself is unusable; for retryable provider
      // faults we return a failed outcome the client can retry.
      if (err.code === "INVALID_INPUT" || err.code === "CONTENT_MODERATION_REJECTED") {
        return {
          request_id: element.requestId,
          error: {
            reason: failureReasonFromProvider(err),
            message: err.message,
          },
        };
      }
      if (!err.retryable) {
        return {
          request_id: element.requestId,
          result: degradedResultFromHints(element.deviceHints),
        };
      }
      return {
        request_id: element.requestId,
        error: {
          reason: failureReasonFromProvider(err),
          message: err.message,
        },
      };
    }
    if (err instanceof AppError) {
      throw err;
    }
    return {
      request_id: element.requestId,
      error: {
        reason: "provider_unavailable",
        message: "Analysis failed unexpectedly.",
      },
    };
  }
}

export async function handleAnalyzeItem(
  req: Request,
  deps: AnalyzeHandlerDeps,
): Promise<Response> {
  const startedAtMs = deps.now().getTime();
  const preflight = handleCorsPreflight(req);
  if (preflight) {
    return preflight;
  }

  let requestId = resolveRequestId(req);
  const logger = createLogger(requestId);

  try {
    if (req.method !== "POST") {
      throw methodNotAllowed("POST /closet/analyze-item only accepts POST.");
    }

    const userId = await authenticateRequest(req, deps.authClient);

    const rateLimitResult = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!rateLimitResult.allowed) {
      logger.warn("closet_analyze_item.rate_limited", {
        user_id: userId,
        retry_after_seconds: rateLimitResult.retryAfterSeconds,
      });
      return errorResponse(
        new AppError("rate_limited", 429, "Too many requests. Please try again shortly."),
        requestId,
        { ...CORS_HEADERS, "Retry-After": String(rateLimitResult.retryAfterSeconds) },
      );
    }

    const idempotencyKey = parseIdempotencyKey(
      req.headers.get("Idempotency-Key") ?? req.headers.get("idempotency-key"),
    );

    const rawJson = await readJsonBody(req);
    const envelope = parseEnvelope(rawJson);
    requestId = resolveRequestId(req, envelope.requestId);
    logger.adoptRequestId(requestId);
    const body = parseAnalyzeItemBody(envelope.body);
    assertOwnsStoragePath(body.storagePath, userId);

    const requestHash = await deps.hashRequest(canonicalAnalyzeBody(body));
    const existing = await deps.idempotencyStore.get(userId, idempotencyKey);
    if (existing) {
      if (existing.requestHash !== requestHash) {
        throw badRequest(
          "Idempotency-Key was reused with a different request body.",
        );
      }
      logger.info("closet_analyze_item.idempotent_replay", {
        user_id: userId,
        latency_ms: deps.now().getTime() - startedAtMs,
      });
      return jsonResponse(existing.responsePayload, {
        status: 200,
        requestId,
        extraHeaders: CORS_HEADERS,
      });
    }

    const outcome = await analyzeOne(
      deps.provider,
      body,
      userId,
      requestId,
      idempotencyKey,
    );

    if (outcome.error || !outcome.result) {
      // Single-item path: a hard per-item failure becomes a provider error
      // for the whole call (the user is staring at one photo).
      throw new AppError(
        "provider",
        502,
        outcome.error?.message ?? "Couldn't analyse that garment.",
      );
    }

    await deps.idempotencyStore.put(
      userId,
      idempotencyKey,
      requestHash,
      outcome.result,
    );

    logger.info("closet_analyze_item.success", {
      user_id: userId,
      category: outcome.result.category.value,
      latency_ms: deps.now().getTime() - startedAtMs,
      idempotent: false,
    });

    return jsonResponse(outcome.result, {
      status: 200,
      requestId,
      extraHeaders: CORS_HEADERS,
    });
  } catch (err) {
    const latencyMs = deps.now().getTime() - startedAtMs;
    const appError = err instanceof AppError ? err : serverError();
    if (err instanceof AppError) {
      logger.warn("closet_analyze_item.rejected", {
        category: appError.category,
        status: appError.status,
        message: appError.message,
        latency_ms: latencyMs,
      });
    } else {
      logger.error("closet_analyze_item.unexpected_error", {
        latency_ms: latencyMs,
        error_name: err instanceof Error ? err.name : "unknown",
      });
    }
    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}

export async function handleBatchAnalyze(
  req: Request,
  deps: BatchHandlerDeps,
): Promise<Response> {
  const startedAtMs = deps.now().getTime();
  const preflight = handleCorsPreflight(req);
  if (preflight) {
    return preflight;
  }

  let requestId = resolveRequestId(req);
  const logger = createLogger(requestId);

  try {
    if (req.method !== "POST") {
      throw methodNotAllowed("POST /closet/batch-analyze only accepts POST.");
    }

    const userId = await authenticateRequest(req, deps.authClient);

    const rateLimitResult = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!rateLimitResult.allowed) {
      logger.warn("closet_batch_analyze.rate_limited", {
        user_id: userId,
        retry_after_seconds: rateLimitResult.retryAfterSeconds,
      });
      return errorResponse(
        new AppError("rate_limited", 429, "Too many requests. Please try again shortly."),
        requestId,
        { ...CORS_HEADERS, "Retry-After": String(rateLimitResult.retryAfterSeconds) },
      );
    }

    const rawJson = await readJsonBody(req);
    const envelope = parseEnvelope(rawJson);
    requestId = resolveRequestId(req, envelope.requestId);
    logger.adoptRequestId(requestId);
    const body = parseBatchAnalyzeBody(envelope.body);

    for (const item of body.items) {
      assertOwnsStoragePath(item.storagePath, userId);
    }

    // Enqueue only — do NOT analyze here. A sync fan-out on this path would
    // saturate the shared closet isolate and starve analyze-item (HANDOFF §9.3).
    const job = await deps.jobStore.create(userId, body.items);
    const payload: BatchJobEnqueueDTO = {
      job_id: job.id,
      status: job.status,
    };

    logger.info("closet_batch_analyze.enqueued", {
      user_id: userId,
      job_id: job.id,
      item_count: body.items.length,
      latency_ms: deps.now().getTime() - startedAtMs,
    });

    return jsonResponse(payload, {
      status: 202,
      requestId,
      extraHeaders: CORS_HEADERS,
    });
  } catch (err) {
    const latencyMs = deps.now().getTime() - startedAtMs;
    const appError = err instanceof AppError ? err : serverError();
    if (err instanceof AppError) {
      logger.warn("closet_batch_analyze.rejected", {
        category: appError.category,
        status: appError.status,
        message: appError.message,
        latency_ms: latencyMs,
      });
    } else {
      logger.error("closet_batch_analyze.unexpected_error", {
        latency_ms: latencyMs,
        error_name: err instanceof Error ? err.name : "unknown",
      });
    }
    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}

/**
 * Advances a batch job by processing at most one pending item per poll.
 * Keeps each poll short so the interactive analyze-item path shares the
 * isolate safely, and makes progress deterministic in tests.
 */
export async function advanceJob(
  job: AnalysisJobRow,
  provider: VisionAnalysisProvider,
  requestId: string,
): Promise<AnalysisJobRow> {
  if (job.status === "complete" || job.status === "failed") {
    return job;
  }

  const doneIds = new Set(job.results.map((entry) => entry.request_id));
  const next = job.items.find((item) => !doneIds.has(item.requestId));
  if (!next) {
    return {
      ...job,
      status: "complete",
    };
  }

  const working: AnalysisJobRow = {
    ...job,
    status: "generating",
  };

  const outcome = await analyzeOne(
    provider,
    next,
    job.userId,
    `${requestId}:${next.requestId}`,
  );
  const results = [...working.results, outcome];
  const status: JobStatus = results.length >= working.items.length ? "complete" : "generating";
  return {
    ...working,
    status,
    results,
  };
}

export async function handleBatchStatus(
  req: Request,
  deps: BatchHandlerDeps,
  jobId: string,
): Promise<Response> {
  const startedAtMs = deps.now().getTime();
  const preflight = handleCorsPreflight(req);
  if (preflight) {
    return preflight;
  }

  const requestId = resolveRequestId(req);
  const logger = createLogger(requestId);

  try {
    if (req.method !== "GET") {
      throw methodNotAllowed("GET /closet/batch-status/:id only accepts GET.");
    }
    if (!isUUID(jobId)) {
      throw badRequest("job id must be a UUID.");
    }

    const userId = await authenticateRequest(req, deps.authClient);

    const rateLimitResult = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!rateLimitResult.allowed) {
      return errorResponse(
        new AppError("rate_limited", 429, "Too many requests. Please try again shortly."),
        requestId,
        { ...CORS_HEADERS, "Retry-After": String(rateLimitResult.retryAfterSeconds) },
      );
    }

    const existing = await deps.jobStore.get(userId, jobId);
    if (!existing) {
      // Either the job does not exist, or it belongs to someone else —
      // RLS/the store returns null either way. Same 404 either way so we
      // do not leak existence across users.
      throw notFound("No batch analysis job with that id.");
    }

    const advanced = await advanceJob(existing, deps.provider, requestId);
    if (
      advanced.status !== existing.status ||
      advanced.results.length !== existing.results.length
    ) {
      await deps.jobStore.save(advanced);
    }

    const payload: BatchJobStatusDTO = {
      job_id: advanced.id,
      status: advanced.status,
      results: advanced.status === "complete" || advanced.status === "failed"
        ? advanced.results
        : advanced.results,
      error_message: advanced.errorMessage,
    };

    logger.info("closet_batch_status.poll", {
      user_id: userId,
      job_id: advanced.id,
      status: advanced.status,
      result_count: advanced.results.length,
      item_count: advanced.items.length,
      latency_ms: deps.now().getTime() - startedAtMs,
    });

    return jsonResponse(payload, {
      status: 200,
      requestId,
      extraHeaders: CORS_HEADERS,
    });
  } catch (err) {
    const latencyMs = deps.now().getTime() - startedAtMs;
    const appError = err instanceof AppError ? err : serverError();
    if (err instanceof AppError) {
      logger.warn("closet_batch_status.rejected", {
        category: appError.category,
        status: appError.status,
        message: appError.message,
        latency_ms: latencyMs,
      });
    } else {
      logger.error("closet_batch_status.unexpected_error", {
        latency_ms: latencyMs,
        error_name: err instanceof Error ? err.name : "unknown",
      });
    }
    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}
