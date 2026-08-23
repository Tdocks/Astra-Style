// ============================================================================
// packing/handler.ts
// ============================================================================
// `POST /packing/generate` (spec §6.24, §14; P7-HOME-04).
//
// THE SAME ENGINE AS THE MORNING. Week-strip and packing are this function
// looping `OutfitScorer.generate` over a date range, excluding garments
// already assigned to an earlier day so the plan is not Acloset's hoodie
// stack. Rewear is allowed only when a required role would otherwise be
// empty. Outfits persist before daily_briefs, same FK ordering as
// daily-brief. Wear This is not gated here.
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
import { parseEnvelope, parseGeneratePackingBody, planDates } from "./schema.ts";
import { buildPlan, type BuildPlanDeps } from "./plan.ts";

export type { BriefRow, OccasionRow, OutfitDraft, PackingRepository } from "./plan.ts";
export { buildPlan } from "./plan.ts";

export interface HandlerDeps extends BuildPlanDeps {
  authClient: AuthClient;
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

export async function handleGeneratePacking(req: Request, deps: HandlerDeps): Promise<Response> {
  const startedAtMs = deps.now().getTime();
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  let requestId = resolveRequestId(req);
  const logger = createLogger(requestId);

  try {
    if (req.method !== "POST") {
      throw methodNotAllowed("POST /packing/generate only accepts POST.");
    }

    const userId = await authenticateRequest(req, deps.authClient);
    const rateLimit = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!rateLimit.allowed) {
      logger.warn("packing_generate.rate_limited", {
        user_id: userId,
        retry_after_seconds: rateLimit.retryAfterSeconds,
      });
      return errorResponse(
        new AppError("rate_limited", 429, "Too many requests. Please try again shortly."),
        requestId,
        { ...CORS_HEADERS, "Retry-After": String(rateLimit.retryAfterSeconds) },
      );
    }

    const envelope = parseEnvelope(await readJsonBody(req));
    requestId = resolveRequestId(req, envelope.requestId);
    logger.adoptRequestId(requestId);
    const body = parseGeneratePackingBody(envelope.body);
    const dates = planDates(body.startDate, body.endDate);

    const plan = await buildPlan(userId, body, dates, deps);

    logger.info("packing_generate.success", {
      user_id: userId,
      days: dates.length,
      outfits: plan.daily_outfit_plan.length,
      regenerated: body.regenerate,
      latency_ms: deps.now().getTime() - startedAtMs,
    });

    return jsonResponse(plan, { status: 200, requestId, extraHeaders: CORS_HEADERS });
  } catch (err) {
    const latencyMs = deps.now().getTime() - startedAtMs;
    const appError = err instanceof AppError ? err : serverError();
    if (err instanceof AppError) {
      logger.warn("packing_generate.rejected", {
        category: appError.category,
        status: appError.status,
        message: appError.message,
        latency_ms: latencyMs,
      });
    } else {
      logger.error("packing_generate.unexpected_error", {
        latency_ms: latencyMs,
        error_name: err instanceof Error ? err.name : "unknown",
      });
    }
    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}
