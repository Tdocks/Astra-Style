// ============================================================================
// studio/handler.ts
// ============================================================================
// Handlers for the `studio` Edge Function (spec §14):
//   POST /generate    — consent gate, prompt assembly, enqueue (202, queued)
//   GET  /status/:id  — advance the job one step, report state
//
// WHY THE PROVIDER IS CALLED FROM THE STATUS POLL, NOT FROM GENERATE.
// `docs/10` §2.3 designs a scheduled worker (pg_cron every 3s) that
// submits queued rows and polls generating ones. No such worker exists in
// this codebase, and inventing scheduling infrastructure inside one ticket
// would be a second architecture nobody reviewed. The `closet` function
// already solved the same problem another way: batch-analyze ENQUEUES
// only, and batch-status ADVANCES the job on each poll. Studio copies that
// shape — `POST /studio/generate` writes the queued row and returns
// (which is also the P6-STUDIO-04 acceptance criterion verbatim), and each
// `GET /studio/status/:id` moves the job at most one state forward:
// queued → submit → generating, then generating → poll → complete/failed.
// The client polls anyway (spec §6.17's generation states), so the polls
// double as the job's heartbeat, no cron required. The cost is honest and
// stated: with the live (synchronous) OpenAI adapter, the poll that
// performs the submit blocks for the render's duration. If real usage
// outgrows that, the `docs/10` §2.3 worker is the upgrade path and this
// handler's advance function is exactly the code it would run.
//
// QUOTA: one free generate for non-premium, then 429 with upgrade copy.
// Retry of an existing failed row does not consume another trial. Wear This
// is not gated here. Spec §21 still holds: a provider-side failure does not
// debit a paid credit — there is no paid debit; this is a trial count.
//
// Spec §14's six per-endpoint requirements (JWT, rate limit, schema,
// ownership, request-id logging, no private image/prompt logging) are all
// below. Ownership: `userId` is JWT-derived only; the reference path must
// live under `users/{uid}/references/`; rows are scoped by RLS + the JWT
// id. The prompt itself is never logged — only its length.
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
import { createLogger, type RequestLogger } from "../_shared/logger.ts";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { ProviderError, type ProviderErrorCode } from "../_shared/providers/types.ts";
import type {
  ImageGenerationProvider,
  ImageGenerationRequest,
  StudioGarment,
} from "../_shared/providers/imageGeneration.ts";
import { buildStudioPrompt, STUDIO_DISCLAIMER } from "./promptBuilder.ts";
import {
  assertConsentCurrent,
  assertOwnedReferencePath,
  CURRENT_STUDIO_CONSENT_TERMS_VERSION,
  type GenerateRequestBody,
  parseEnvelope,
  parseGenerateBody,
  type StudioGenerationDTO,
  toWireTimestamp,
} from "./schema.ts";
import { isUUID } from "../_shared/validation.ts";

/**
 * Provider deadline. Generous on purpose: with the live adapter a single
 * call IS the whole render (see openaiImageGeneration.ts), and a
 * high-quality portrait can take well past the closet function's 20s
 * vision deadline. This bounds the status poll that performs the submit;
 * the client's own poll loop treats a long poll as time spent generating,
 * which is exactly what it is.
 */
const PROVIDER_TIMEOUT_MS = 90_000;

export type StudioStatus = "queued" | "generating" | "complete" | "failed";

/** Astra-shaped row mirror of `studio_generations` (spec §9). */
export interface StudioGenerationRow {
  id: string;
  userId: string;
  referenceImagePath: string;
  outfitId: string | null;
  promptPayload: Record<string, unknown>;
  status: StudioStatus;
  resultImagePath: string | null;
  provider: string | null;
  errorMessage: string | null;
  deletedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface StudioJobInsert {
  userId: string;
  referenceImagePath: string;
  outfitId: string | null;
  promptPayload: Record<string, unknown>;
  provider: string;
}

export interface StudioJobPatch {
  status?: StudioStatus;
  resultImagePath?: string | null;
  errorMessage?: string | null;
  promptPayload?: Record<string, unknown>;
}

export interface StudioJobStore {
  /** Inserts with `status = 'queued'` — the P6-STUDIO-04 contract. */
  insert(row: StudioJobInsert): Promise<StudioGenerationRow>;
  /** Returns null for missing AND for unowned (RLS) — same 404 either way. */
  get(userId: string, id: string): Promise<StudioGenerationRow | null>;
  update(userId: string, id: string, patch: StudioJobPatch): Promise<StudioGenerationRow>;
  /** Own rows only — used to enforce the one free Visualize trial. */
  countForUser(userId: string): Promise<number>;
}

/**
 * Resolves the exact garments to render from the caller's own rows —
 * `outfit_items` joined to `closet_items` for an outfit, or `closet_items`
 * directly for an ad-hoc selection. Never a text description (docs/08
 * §8.2).
 */
export interface StudioGarmentSource {
  outfitGarments(userId: string, outfitId: string): Promise<StudioGarment[]>;
  itemGarments(userId: string, itemIds: string[]): Promise<StudioGarment[]>;
}

export interface StudioHandlerDeps {
  authClient: AuthClient;
  provider: ImageGenerationProvider;
  /** Stored on the row (`studio_generations.provider`), e.g. "mock" | "openai". */
  providerName: string;
  jobStore: StudioJobStore;
  garmentSource: StudioGarmentSource;
  generateRateLimiter: RateLimiter;
  statusRateLimiter: RateLimiter;
  now: () => Date;
  hasActivePremiumSubscription: (nowIso: string) => Promise<boolean>;
  /** Free Visualize trials before the paywall. Spec is 1. */
  freeStudioTrialGenerations: number;
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

function rowToDTO(row: StudioGenerationRow): StudioGenerationDTO {
  return {
    id: row.id,
    user_id: row.userId,
    reference_image_path: row.referenceImagePath,
    outfit_id: row.outfitId,
    prompt_payload: row.promptPayload,
    status: row.status,
    result_image_path: row.resultImagePath,
    provider: row.provider,
    error_message: row.errorMessage,
    deleted_at: row.deletedAt === null ? null : toWireTimestamp(row.deletedAt),
    created_at: toWireTimestamp(row.createdAt),
    updated_at: toWireTimestamp(row.updatedAt),
  };
}

/**
 * The §21-shaped user-facing failure vocabulary. Raw provider text never
 * reaches the client (docs/10 §2.4): a moderation false positive must not
 * read as an accusation, and a vendor's internal error string is neither
 * actionable nor stable enough to show a person waiting on his own face.
 */
function userFacingFailureMessage(code: ProviderErrorCode): string {
  switch (code) {
    case "CONTENT_MODERATION_REJECTED":
      return "That photo can't be used for a Style Studio preview. Try a clear, recent photo of yourself in good lighting.";
    case "INVALID_INPUT":
      return "That request couldn't be processed. Try a different photo or outfit.";
    case "AUTH_FAILED":
    case "PROVIDER_QUOTA_EXCEEDED":
      return "Style Studio is briefly unavailable. You haven't lost your turn — try again shortly.";
    default:
      return "That took longer than expected. Try again?";
  }
}

function garmentsFromPayload(payload: Record<string, unknown>): StudioGarment[] {
  const raw = payload["garments"];
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw as StudioGarment[];
}

function providerRequestFromRow(row: StudioGenerationRow): ImageGenerationRequest {
  const payload = row.promptPayload;
  const controls = (payload["controls"] ?? {}) as Record<string, unknown>;
  const str = (value: unknown, fallback: string): string =>
    typeof value === "string" ? value : fallback;
  return {
    generationId: row.id,
    referenceImageStoragePath: row.referenceImagePath,
    structuredGarmentList: garmentsFromPayload(payload),
    prompt: str(payload["prompt"], ""),
    pose: str(controls["pose"], "standing_front"),
    background: str(controls["background"], "studio"),
    lighting: str(controls["lighting"], ""),
    formality: str(controls["formality"], ""),
    resolution: payload["resolution"] === "hi_res" ? "hi_res" : "draft",
    preserveFace: controls["preserve_face"] !== false,
    preserveBodyProportions: controls["preserve_body_proportions"] !== false,
    preserveHairFacialHair: controls["preserve_hair"] !== false,
  };
}

/**
 * Moves a job at most one state forward. Exported for tests. The
 * three rules that matter:
 *
 * 1. A RETRYABLE submit/poll fault leaves the row where it was. The row
 *    stays `queued`/`generating` and the next poll tries again — a
 *    transient vendor hiccup must not become a terminal "failed" the user
 *    has to act on (§21).
 * 2. A NON-retryable fault (moderation, rejected payload, dead
 *    credentials) is terminal immediately, with a user-facing message and
 *    `prompt_payload` untouched — which is what makes "retry without
 *    reconfiguring anything" possible for the failures that ARE worth a
 *    manual retry.
 * 3. Nothing here debits quota — see the header.
 */
export async function advanceGeneration(
  row: StudioGenerationRow,
  deps: StudioHandlerDeps,
  requestId: string,
  logger: RequestLogger,
): Promise<StudioGenerationRow> {
  if (row.status === "complete" || row.status === "failed") {
    return row;
  }
  const ctx = {
    requestId,
    userId: row.userId,
    timeoutMs: PROVIDER_TIMEOUT_MS,
    // The row id is the natural idempotency key: a poll retried after a
    // network blip must not pay for a second render of the same job.
    idempotencyKey: row.id,
  };

  if (row.status === "queued") {
    try {
      const { providerJobId } = await deps.provider.submitGeneration(
        providerRequestFromRow(row),
        ctx,
      );
      return await deps.jobStore.update(row.userId, row.id, {
        status: "generating",
        promptPayload: { ...row.promptPayload, provider_job_id: providerJobId },
      });
    } catch (err) {
      if (err instanceof ProviderError && err.retryable) {
        logger.warn("studio_status.submit_retryable_fault", { code: err.code });
        return row;
      }
      const code: ProviderErrorCode = err instanceof ProviderError ? err.code : "UNKNOWN";
      logger.warn("studio_status.submit_failed", { code });
      return await deps.jobStore.update(row.userId, row.id, {
        status: "failed",
        errorMessage: userFacingFailureMessage(code),
        promptPayload: { ...row.promptPayload, is_retryable_failure: false },
      });
    }
  }

  // status === "generating"
  const providerJobId = row.promptPayload["provider_job_id"];
  if (typeof providerJobId !== "string" || providerJobId.length === 0) {
    // A generating row with no job id means a partial write somewhere —
    // unrecoverable for THIS row, but the prompt is intact, so a retry
    // rebuilds cleanly.
    return await deps.jobStore.update(row.userId, row.id, {
      status: "failed",
      errorMessage: userFacingFailureMessage("UNKNOWN"),
      promptPayload: { ...row.promptPayload, is_retryable_failure: true },
    });
  }
  let result;
  try {
    result = await deps.provider.pollStatus(providerJobId, ctx);
  } catch (err) {
    if (err instanceof ProviderError && err.retryable) {
      logger.warn("studio_status.poll_retryable_fault", { code: err.code });
      return row;
    }
    const code: ProviderErrorCode = err instanceof ProviderError ? err.code : "UNKNOWN";
    return await deps.jobStore.update(row.userId, row.id, {
      status: "failed",
      errorMessage: userFacingFailureMessage(code),
      promptPayload: { ...row.promptPayload, is_retryable_failure: false },
    });
  }
  if (result.status === "complete" && result.resultStoragePath !== null) {
    return await deps.jobStore.update(row.userId, row.id, {
      status: "complete",
      resultImagePath: result.resultStoragePath,
    });
  }
  if (result.status === "failed") {
    return await deps.jobStore.update(row.userId, row.id, {
      status: "failed",
      errorMessage: userFacingFailureMessage(
        result.isRetryableFailure ? "PROVIDER_UNAVAILABLE" : "CONTENT_MODERATION_REJECTED",
      ),
      promptPayload: {
        ...row.promptPayload,
        is_retryable_failure: result.isRetryableFailure,
      },
    });
  }
  return row;
}

async function enqueueGeneration(
  body: GenerateRequestBody,
  userId: string,
  deps: StudioHandlerDeps,
): Promise<StudioGenerationRow> {
  assertConsentCurrent(body.consent);
  assertOwnedReferencePath(body.referenceImagePath, userId);

  const garments: StudioGarment[] = [];
  if (body.outfitId !== undefined) {
    garments.push(...await deps.garmentSource.outfitGarments(userId, body.outfitId));
  }
  if (body.adHocItemIds.length > 0) {
    garments.push(...await deps.garmentSource.itemGarments(userId, body.adHocItemIds));
  }
  if (garments.length === 0) {
    throw badRequest("None of the selected items could be found in your closet.");
  }

  const controls = {
    pose: body.pose,
    background: body.background,
    preset: body.preset,
    formality: body.formality,
    season: body.season,
    color_palette: body.colorPalette,
    preserve_face: body.preserveFace,
    preserve_body_proportions: body.preserveBodyProportions,
    preserve_hair: body.preserveHair,
  };
  const prompt = buildStudioPrompt(garments, {
    pose: body.pose,
    background: body.background,
    preset: body.preset,
    formality: body.formality,
    season: body.season,
    colorPalette: body.colorPalette,
    preserveFace: body.preserveFace,
    preserveBodyProportions: body.preserveBodyProportions,
    preserveHair: body.preserveHair,
  });

  return await deps.jobStore.insert({
    userId,
    referenceImagePath: body.referenceImagePath,
    outfitId: body.outfitId ?? null,
    promptPayload: {
      prompt,
      // §11's label, attached at row creation rather than at completion
      // (stronger than docs/10 §2.6's flip-time attachment): there is no
      // window in which a generation exists without its disclaimer.
      disclaimer: STUDIO_DISCLAIMER,
      garments,
      controls,
      // §13's draft-before-hi-res: the standard quota generation is a
      // draft. Hi-res export is a distinct later action (P6-STUDIO-07/-11
      // scope), not a second flag on this request.
      resolution: "draft",
      consent: {
        acknowledged: true,
        terms_version: body.consent.termsVersion,
        // Receipt time. The client's consent store holds the original
        // attestation moment; this records when the server accepted it.
        attested_at: toWireTimestamp(deps.now()),
      },
    },
    provider: deps.providerName,
  });
}

async function enqueueRetry(
  retryOf: string,
  userId: string,
  deps: StudioHandlerDeps,
): Promise<StudioGenerationRow> {
  const original = await deps.jobStore.get(userId, retryOf);
  if (!original || original.deletedAt !== null) {
    throw notFound("No generation with that id.");
  }
  if (original.status !== "failed") {
    throw badRequest("Only a failed generation can be retried.");
  }
  // The consent gate runs on retries too (docs/08 §8.3 step 4): the stored
  // attestation must still be against the CURRENT terms. This is the
  // "no path reaches the provider without it" property — a cached job
  // resubmission does not grandfather old consent.
  const consent = original.promptPayload["consent"] as Record<string, unknown> | undefined;
  if (consent?.["terms_version"] !== CURRENT_STUDIO_CONSENT_TERMS_VERSION) {
    throw badRequest(
      "The consent terms have changed since you confirmed this photo. Please confirm the updated terms and try again.",
    );
  }
  // Copy the payload VERBATIM minus job-instance state (§21: the user
  // re-configures nothing; the failed row stays as the audit record).
  const payload = { ...original.promptPayload };
  delete payload["provider_job_id"];
  delete payload["is_retryable_failure"];
  return await deps.jobStore.insert({
    userId,
    referenceImagePath: original.referenceImagePath,
    outfitId: original.outfitId,
    promptPayload: payload,
    provider: deps.providerName,
  });
}

export async function handleGenerate(
  req: Request,
  deps: StudioHandlerDeps,
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
      throw methodNotAllowed("POST /studio/generate only accepts POST.");
    }
    const userId = await authenticateRequest(req, deps.authClient);

    const rateLimitResult = deps.generateRateLimiter.check(userId, deps.now().getTime());
    if (!rateLimitResult.allowed) {
      logger.warn("studio_generate.rate_limited", {
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
    const body = parseGenerateBody(envelope.body);

    if (body.kind !== "retry") {
      const premium = await deps.hasActivePremiumSubscription(deps.now().toISOString());
      if (!premium) {
        const used = await deps.jobStore.countForUser(userId);
        if (used >= deps.freeStudioTrialGenerations) {
          logger.warn("studio_generate.rate_limited", {
            user_id: userId,
            kind: "studio_trial_quota",
            limit: deps.freeStudioTrialGenerations,
          });
          return errorResponse(
            new AppError(
              "rate_limited",
              429,
              "You've used your free visual estimate. Upgrade to Astra Style Premium for more. Wear This stays free.",
            ),
            requestId,
            CORS_HEADERS,
          );
        }
      }
    }

    const row = body.kind === "retry"
      ? await enqueueRetry(body.retryOf, userId, deps)
      : await enqueueGeneration(body, userId, deps);

    logger.info("studio_generate.enqueued", {
      user_id: userId,
      generation_id: row.id,
      retry: body.kind === "retry",
      // The prompt itself is never logged (spec §14); its length is the
      // only diagnostic anyone has needed.
      prompt_length: typeof row.promptPayload["prompt"] === "string"
        ? (row.promptPayload["prompt"] as string).length
        : 0,
      latency_ms: deps.now().getTime() - startedAtMs,
    });

    return jsonResponse(rowToDTO(row), {
      status: 202,
      requestId,
      extraHeaders: CORS_HEADERS,
    });
  } catch (err) {
    const latencyMs = deps.now().getTime() - startedAtMs;
    const appError = err instanceof AppError ? err : serverError();
    if (err instanceof AppError) {
      logger.warn("studio_generate.rejected", {
        category: appError.category,
        status: appError.status,
        message: appError.message,
        latency_ms: latencyMs,
      });
    } else {
      logger.error("studio_generate.unexpected_error", {
        latency_ms: latencyMs,
        error_name: err instanceof Error ? err.name : "unknown",
      });
    }
    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}

export async function handleStatus(
  req: Request,
  deps: StudioHandlerDeps,
  generationId: string,
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
      throw methodNotAllowed("GET /studio/status/:id only accepts GET.");
    }
    if (!isUUID(generationId)) {
      throw badRequest("generation id must be a UUID.");
    }
    const userId = await authenticateRequest(req, deps.authClient);

    const rateLimitResult = deps.statusRateLimiter.check(userId, deps.now().getTime());
    if (!rateLimitResult.allowed) {
      return errorResponse(
        new AppError("rate_limited", 429, "Too many requests. Please try again shortly."),
        requestId,
        { ...CORS_HEADERS, "Retry-After": String(rateLimitResult.retryAfterSeconds) },
      );
    }

    const existing = await deps.jobStore.get(userId, generationId);
    if (!existing || existing.deletedAt !== null) {
      // Missing, deleted, or someone else's — the store/RLS returns null
      // either way, and a deleted generation is erased (spec §29): the
      // same 404 for all three, so nothing leaks existence across users.
      throw notFound("No generation with that id.");
    }

    const advanced = await advanceGeneration(existing, deps, requestId, logger);

    logger.info("studio_status.poll", {
      user_id: userId,
      generation_id: advanced.id,
      status: advanced.status,
      latency_ms: deps.now().getTime() - startedAtMs,
    });

    return jsonResponse(rowToDTO(advanced), {
      status: 200,
      requestId,
      extraHeaders: CORS_HEADERS,
    });
  } catch (err) {
    const latencyMs = deps.now().getTime() - startedAtMs;
    const appError = err instanceof AppError ? err : serverError();
    if (err instanceof AppError) {
      logger.warn("studio_status.rejected", {
        category: appError.category,
        status: appError.status,
        message: appError.message,
        latency_ms: latencyMs,
      });
    } else {
      logger.error("studio_status.unexpected_error", {
        latency_ms: latencyMs,
        error_name: err instanceof Error ? err.name : "unknown",
      });
    }
    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}
