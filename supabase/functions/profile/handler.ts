// ============================================================================
// profile/handler.ts
// ============================================================================
// `POST /profile/complete-onboarding` (spec §14, ticket P2-ONBOARD-12).
// Deployment wiring lives in `index.ts`; everything here is pure enough to
// unit test with injected dependencies and no network access (see
// `handler_test.ts`), following `outfits/handler.ts`'s structure exactly so
// the two read the same way.
//
// Spec §14's six per-endpoint requirements, in the order they run (cheapest
// and most attacker-hostile first, as in `outfits/handler.ts`):
//   1. Validate JWT           -> authenticateRequest() (_shared/jwt.ts). The
//      only source of a user id in this request, full stop.
//   2. Rate limit             -> deps.rateLimiter.check(), keyed on that id.
//      A tighter limit than `outfits` (see index.ts): finishing onboarding is
//      something a user does once, and the write touches four tables.
//   3. Validate request schema-> parseEnvelope() / parseCompleteOnboardingBody()
//   4. Validate ownership     -> structural. `deps.onboardingWriter.complete`
//      receives the step-1 id and the RPC behind it takes NO user-id
//      parameter at all (20260730190000_complete_onboarding_rpc.sql), so the
//      `user_id` fields the client's models happen to encode are read by
//      nothing, anywhere.
//   5. Log request ID+latency -> logger.info/warn/error on every path.
//   6. Avoid logging private content -> only counts, booleans and ids reach
//      the logger. No measurement value, no brand list, no appearance field,
//      no free text. `_shared/logger.ts` redacts by key name as a backstop.
// ============================================================================

import { CORS_HEADERS, handleCorsPreflight } from "../_shared/cors.ts";
import {
  AppError,
  badRequest,
  errorResponse,
  jsonResponse,
  methodNotAllowed,
  serverError,
} from "../_shared/errors.ts";
import { createLogger } from "../_shared/logger.ts";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import {
  type BodyProfileInput,
  type CompleteOnboardingBody,
  type LifestyleProfileInput,
  parseCompleteOnboardingBody,
  parseEnvelope,
  type ProfileDTO,
  type StyleProfileInput,
} from "./schema.ts";

export interface OnboardingWrite {
  styleProfile: StyleProfileInput;
  bodyProfile: BodyProfileInput;
  lifestyleProfile: LifestyleProfileInput;
}

export interface OnboardingRepository {
  /**
   * Writes all four tables and returns the updated `profiles` row.
   *
   * MUST be atomic. The production implementation (index.ts) satisfies this
   * by calling one plpgsql function, whose body is a single transaction. An
   * implementation that made four sequential PostgREST calls would satisfy
   * this interface's TYPES and violate its contract — which is why the
   * requirement is stated here in prose and enforced there in SQL, rather
   * than being left implicit in a method name.
   *
   * `userId` is the JWT-verified id. The production implementation passes it
   * to nothing: the RPC derives the owner from auth.uid() on the caller-
   * scoped connection. It is in this signature so a test can assert the
   * handler never sources an id from the request body, exactly as
   * `ClosetRepository.listCandidateItems` does in `outfits/handler.ts`.
   */
  complete(userId: string, write: OnboardingWrite): Promise<ProfileDTO>;
}

export interface HandlerDeps {
  authClient: AuthClient;
  onboardingRepository: OnboardingRepository;
  rateLimiter: RateLimiter;
  /** Injected clock so latency logging is deterministic in tests. */
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

/**
 * How many axes the vector actually carries, and how many of those produced a
 * score. Logged (as counts only) because it is the single most useful signal
 * for the risk `docs/03-progress.md` calls out — five of eight dimensions
 * currently arrive absent because the comparison set has three pairs — and
 * because it is a number, not content.
 */
function vectorShape(body: CompleteOnboardingBody): { axes: number; scored: number } {
  const readings = Object.values(body.styleProfile.preference_vector.dimensions);
  return {
    axes: readings.length,
    scored: readings.filter((reading) => reading.score !== null).length,
  };
}

export async function handleCompleteOnboarding(
  req: Request,
  deps: HandlerDeps,
): Promise<Response> {
  const startedAtMs = deps.now().getTime();

  const preflight = handleCorsPreflight(req);
  if (preflight) {
    return preflight;
  }

  // Two-stage, as in outfits/handler.ts: the header is readable before the
  // body, so a request whose body fails to parse still logs against an id.
  let requestId = resolveRequestId(req);
  const logger = createLogger(requestId);

  try {
    if (req.method !== "POST") {
      throw methodNotAllowed("POST /profile/complete-onboarding only accepts POST.");
    }

    // 1. Validate JWT.
    const userId = await authenticateRequest(req, deps.authClient);

    // 2. Rate limit.
    const rateLimitResult = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!rateLimitResult.allowed) {
      logger.warn("profile_complete_onboarding.rate_limited", {
        user_id: userId,
        retry_after_seconds: rateLimitResult.retryAfterSeconds,
      });
      return errorResponse(
        new AppError("rate_limited", 429, "Too many requests. Please try again shortly."),
        requestId,
        { ...CORS_HEADERS, "Retry-After": String(rateLimitResult.retryAfterSeconds) },
      );
    }

    // 3. Validate request schema.
    const rawJson = await readJsonBody(req);
    const envelope = parseEnvelope(rawJson);
    requestId = resolveRequestId(req, envelope.requestId);
    logger.adoptRequestId(requestId);
    const body = parseCompleteOnboardingBody(envelope.body);

    // 4. Ownership: `userId` is the step-1 JWT id and the only id in play.
    const profile = await deps.onboardingRepository.complete(userId, {
      styleProfile: body.styleProfile,
      bodyProfile: body.bodyProfile,
      lifestyleProfile: body.lifestyleProfile,
    });

    const shape = vectorShape(body);
    const latencyMs = deps.now().getTime() - startedAtMs;
    // 5 & 6. Request id + latency, and only non-content fields. Counts and
    // booleans describe the submission's shape without recording a single
    // thing the user typed.
    logger.info("profile_complete_onboarding.success", {
      user_id: userId,
      goal_count: body.styleProfile.style_goals.length,
      has_primary_identity: body.styleProfile.primary_identity !== null,
      secondary_identity_count: body.styleProfile.secondary_identities.length,
      quiz_answer_count: body.quizAnswerCount,
      comparisons_offered: body.styleProfile.preference_vector.comparisons_offered,
      preference_axes_present: shape.axes,
      preference_axes_scored: shape.scored,
      has_any_measurement: body.bodyProfile.height_value_cm !== null ||
        body.bodyProfile.chest_cm !== null || body.bodyProfile.waist_cm !== null ||
        body.bodyProfile.inseam_cm !== null || body.bodyProfile.neck_cm !== null ||
        body.bodyProfile.weight_value_kg !== null,
      has_dress_code: body.lifestyleProfile.dress_code !== null,
      onboarding_completed: profile.onboarding_completed_at !== null,
      latency_ms: latencyMs,
    });

    return jsonResponse(profile, { status: 200, requestId, extraHeaders: CORS_HEADERS });
  } catch (err) {
    const latencyMs = deps.now().getTime() - startedAtMs;
    const appError = err instanceof AppError ? err : serverError();

    if (err instanceof AppError) {
      logger.warn("profile_complete_onboarding.rejected", {
        category: appError.category,
        status: appError.status,
        message: appError.message,
        latency_ms: latencyMs,
      });
    } else {
      logger.error("profile_complete_onboarding.unexpected_error", {
        latency_ms: latencyMs,
        error_name: err instanceof Error ? err.name : "unknown",
      });
    }

    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}
