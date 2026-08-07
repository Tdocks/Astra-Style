// ============================================================================
// outfits/handler.ts
// ============================================================================
// `POST /outfits/generate` (spec §14). Deployment wiring lives in
// `index.ts`; everything here is pure enough to unit test with injected
// dependencies and no network access (see `handler_test.ts`), per the
// task's "mock the Supabase client at the boundary" requirement.
//
// Every one of spec §14's six per-endpoint requirements is implemented
// below; each is impossible to skip because an exception anywhere before
// the response is built short-circuits straight to the `catch` block
// rather than falling through. Spec §14 lists the six as an unordered
// checklist, not a call sequence, so the actual runtime order here is
// chosen for cost (cheapest/most-attacker-hostile checks first):
//   1. Validate JWT             -> authenticateRequest() (_shared/jwt.ts).
//      Nothing after this point runs for an unauthenticated caller.
//   2. Rate limit                -> deps.rateLimiter.check(), keyed on the
//      JWT-derived user id. Runs before we spend any work parsing/
//      validating the body, so a caller can't burn parse/validation cost
//      by spamming garbage bodies past the rate limiter.
//   3. Validate request schema   -> parseEnvelope() / parseGenerateOutfitsBody()
//   4. Validate ownership        -> there is no separate "ownership" check
//      to perform: `userId` passed to closetRepository.listCandidateItems()
//      below is the step-1 JWT-derived id and *only* that id — the request
//      body has no user-id-shaped field for an attacker to substitute (see
//      schema.ts's header comment) — so the vulnerability this slice exists
//      to disprove has no code path to occur through, rather than merely
//      being checked-for after the fact.
//   5. Log request ID+latency    -> logger.info/warn/error on every path,
//      success or failure.
//   6. Avoid logging private images/prompts -> see _shared/logger.ts; only
//      counts/ids/status/booleans are ever passed to it, never
//      `naturalLanguageRequest`'s actual contents.
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
import { type OutfitRecommendationDTO, parseEnvelope, parseGenerateOutfitsBody } from "./schema.ts";
import type { ClosetItemRow, OutfitScorer } from "../_shared/scoring/leastRecentlyWorn.ts";

export interface ClosetRepository {
  /**
   * Returns the authenticated user's own candidate closet items
   * (top/bottom/shoes only, non-archived, currently wearable). Ownership
   * scoping is enforced by the real implementation's use of a Row Level
   * Security-backed Supabase client (see index.ts), not by this interface —
   * a test double that ignored `userId` entirely would still be "correct"
   * from this interface's point of view, which is exactly why the
   * ownership test in handler_test.ts asserts the *caller* passes the
   * JWT-derived id here, not that this method internally re-checks it.
   */
  listCandidateItems(userId: string): Promise<ClosetItemRow[]>;
}

export interface HandlerDeps {
  authClient: AuthClient;
  closetRepository: ClosetRepository;
  scorer: OutfitScorer;
  rateLimiter: RateLimiter;
  /** Injected clock so latency logging and least-recently-worn ordering are deterministic in tests. */
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

export async function handleGenerateOutfits(req: Request, deps: HandlerDeps): Promise<Response> {
  const startedAtMs = deps.now().getTime();

  const preflight = handleCorsPreflight(req);
  if (preflight) {
    return preflight;
  }

  // Resolved in two stages on purpose. The header is available immediately,
  // so logging can start before the body is read — which matters, because a
  // request whose body fails to parse still needs an id to log against. Once
  // the envelope IS parsed, a body-supplied `request_id` is adopted if no
  // header was present, so a client that sends only the envelope field (the
  // shape documented in supabase/functions/README.md) still gets its own id
  // echoed back rather than a server-generated one it has never seen.
  let requestId = resolveRequestId(req);
  const logger = createLogger(requestId);

  try {
    if (req.method !== "POST") {
      throw methodNotAllowed("POST /outfits/generate only accepts POST.");
    }

    // 1. Validate JWT — the ONLY source of `userId` for this request.
    const userId = await authenticateRequest(req, deps.authClient);

    // 2. Rate limit (best-effort in-memory; see _shared/rateLimit.ts).
    const rateLimitResult = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!rateLimitResult.allowed) {
      logger.warn("outfits_generate.rate_limited", {
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
    // Adopt the envelope's id only when the caller did not supply a header —
    // the header stays authoritative so a proxy or gateway can override.
    requestId = resolveRequestId(req, envelope.requestId);
    logger.adoptRequestId(requestId);
    const body = parseGenerateOutfitsBody(envelope.body);

    // 4. Validate ownership: `userId` below is the JWT-verified id from
    // step 1. `body` (schema.ts) has no `user_id` field at all, so there is
    // nothing here to "trust" or "not trust" from the client — the
    // vulnerability this slice exists to disprove structurally cannot
    // occur, rather than being merely checked-for.
    const items = await deps.closetRepository.listCandidateItems(userId);

    // SEAM: `deps.scorer` is where the real CompatibilityScorer plugs in
    // later — see _shared/scoring/leastRecentlyWorn.ts's module header.
    const scored = deps.scorer.generate(items, {
      desiredCount: body.desiredCount,
      lockedItemIds: new Set(body.lockedClosetItemIds),
      excludedItemIds: new Set(body.excludedClosetItemIds),
    });

    const payload: OutfitRecommendationDTO[] = scored.map((outfit) => ({
      id: crypto.randomUUID(),
      name: "Today's Outfit",
      reason: outfit.reason,
      compatibility_score: outfit.compatibilityScore,
      item_ids: outfit.itemIds,
      missing_product_ids: [],
    }));

    const latencyMs = deps.now().getTime() - startedAtMs;
    // 5 & 6. Log request id + latency; only safe, non-content fields.
    logger.info("outfits_generate.success", {
      user_id: userId,
      candidate_item_count: items.length,
      outfits_returned: payload.length,
      desired_count: body.desiredCount,
      had_natural_language_request: body.naturalLanguageRequest !== undefined,
      latency_ms: latencyMs,
    });

    return jsonResponse(payload, { status: 200, requestId, extraHeaders: CORS_HEADERS });
  } catch (err) {
    const latencyMs = deps.now().getTime() - startedAtMs;
    const appError = err instanceof AppError ? err : serverError();

    if (err instanceof AppError) {
      logger.warn("outfits_generate.rejected", {
        category: appError.category,
        status: appError.status,
        message: appError.message,
        latency_ms: latencyMs,
      });
    } else {
      // Unexpected/programmer error: log a category + generic message for
      // observability, never the raw error/stack to the client, and never
      // request content in this line (see _shared/logger.ts's denylist).
      logger.error("outfits_generate.unexpected_error", {
        latency_ms: latencyMs,
        error_name: err instanceof Error ? err.name : "unknown",
      });
    }

    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}
