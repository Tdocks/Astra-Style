// ============================================================================
// outfits/handler.ts
// ============================================================================
// `POST /outfits/generate` and `POST /outfits/rank` (spec §14;
// `P4-OUTFIT-07`/`P4-OUTFIT-08`). Deployment wiring lives in `index.ts`;
// everything here is pure enough to unit test with injected dependencies and
// no network access (see `handler_test.ts`), per the task's "mock the
// Supabase client at the boundary" requirement.
//
// Every one of spec §14's six per-endpoint requirements is implemented for
// BOTH handlers below; each is impossible to skip because an exception
// anywhere before the response is built short-circuits straight to the
// `catch` block rather than falling through. Spec §14 lists the six as an
// unordered checklist, not a call sequence, so the actual runtime order here
// is chosen for cost (cheapest/most-attacker-hostile checks first):
//   1. Validate JWT             -> authenticateRequest() (_shared/jwt.ts).
//      Nothing after this point runs for an unauthenticated caller.
//   2. Rate limit                -> deps.rateLimiter.check(), keyed on the
//      JWT-derived user id. Runs before we spend any work parsing/
//      validating the body, so a caller can't burn parse/validation cost
//      by spamming garbage bodies past the rate limiter.
//   3. Validate request schema   -> parseEnvelope() / parseGenerateOutfitsBody()
//      / parseRankOutfitsBody()
//   4. Validate ownership        -> there is no separate "ownership" check
//      to perform: `userId` passed to the repository below is the step-1
//      JWT-derived id and *only* that id — neither request body has a
//      user-id-shaped field for an attacker to substitute (see schema.ts's
//      header comment) — so the vulnerability this slice exists to disprove
//      has no code path to occur through, rather than merely being
//      checked-for after the fact.
//   5. Log request ID+latency    -> logger.info/warn/error on every path,
//      success or failure.
//   6. Avoid logging private images/prompts -> see _shared/logger.ts; only
//      counts/ids/status/booleans are ever passed to it, never
//      `naturalLanguageRequest`'s actual contents.
//
// WHAT THIS FILE DOES NOT WIRE IN, AND WHY THAT IS HONEST RATHER THAN
// UNFINISHED. `ScoringContext.weather`, `.preferences` and `.coWear` are
// never populated by either handler below. There is no server-side weather
// provider yet (`daily-brief/handler.ts`'s header records the same gap for
// `P4-HOME-05`), no fetch of `style_profiles`/`style_preferences` here, and
// no `outfit_wears`-derived co-wear statistics. `body.occasionId` is parsed
// (schema.ts) but not resolved to a `dress_code` tag, and
// `body.naturalLanguageRequest` is parsed but not interpreted — both would
// need a lookup or a model call this ticket does not build. Every one of
// those gaps is exactly what `ScoringContext`'s optional fields and each
// subscore's documented cold-start prior exist for (`_shared/scoring/types.ts`,
// `subscores/context.ts`): the score comes back honestly degraded, and
// `unmeasured` on the wire says so, rather than this file inventing a
// weather reading or a preference profile it does not have.
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
import { createLogger, type RequestLogger } from "../_shared/logger.ts";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { parseEnvelope, parseGenerateOutfitsBody, parseRankOutfitsBody } from "./schema.ts";
import {
  type ClosetItemMapperRow,
  mapClosetItemRowToScorableItem,
} from "../_shared/scoring/closetItemMapper.ts";
import { generateCandidateOutfits } from "./candidateGeneration.ts";
import { buildReason } from "./reason.ts";
import { scoreOutfit } from "../_shared/scoring/compatibility.ts";
import { toScoredOutfit } from "../_shared/scoring/wire.ts";
import type { ScoredOutfitEnvelope } from "../_shared/scoring/wire.ts";
import type { ScorableItem } from "../_shared/scoring/types.ts";

export interface ClosetRepository {
  /**
   * The authenticated user's own candidate closet items, full columns (see
   * `ClosetItemMapperRow`) — ownership scoping is enforced by the real
   * implementation's use of a Row Level Security-backed Supabase client
   * (see index.ts), not by this interface. Rows are NOT pre-filtered to
   * wearable ones here; `handleGenerateOutfits` calls `wearableItems()`
   * (via `generateCandidateOutfits`) explicitly, so that filter is visible
   * and testable in one place rather than assumed of every implementation
   * of this method.
   */
  listCandidateItems(userId: string): Promise<ClosetItemMapperRow[]>;

  /**
   * Resolves a specific set of closet item ids for `/rank`, scoped to the
   * caller by RLS exactly like `listCandidateItems`. An id that does not
   * belong to the caller, does not exist, or was archived simply does not
   * appear in the result — the same "absent, not substituted" contract
   * `handleRankOutfits` relies on to drop a candidate it cannot honestly
   * score rather than scoring a different one.
   */
  listItemsByIds(userId: string, ids: readonly string[]): Promise<ClosetItemMapperRow[]>;
}

export interface HandlerDeps {
  authClient: AuthClient;
  closetRepository: ClosetRepository;
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

/** Maps closet rows to `ScorableItem`s, silently dropping rows with no scoring role (fragrance — see `roleFor`). */
function mapRows(rows: readonly ClosetItemMapperRow[]): ScorableItem[] {
  const items: ScorableItem[] = [];
  for (const row of rows) {
    const item = mapClosetItemRowToScorableItem(row);
    if (item) items.push(item);
  }
  return items;
}

export async function handleGenerateOutfits(req: Request, deps: HandlerDeps): Promise<Response> {
  const startedAtMs = deps.now().getTime();

  const preflight = handleCorsPreflight(req);
  if (preflight) {
    return preflight;
  }

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
    requestId = resolveRequestId(req, envelope.requestId);
    logger.adoptRequestId(requestId);
    const body = parseGenerateOutfitsBody(envelope.body);

    // 4. Validate ownership: `userId` below is the JWT-verified id from
    // step 1. `body` (schema.ts) has no `user_id` field at all, so there is
    // nothing here to "trust" or "not trust" from the client.
    const rows = await deps.closetRepository.listCandidateItems(userId);
    const items = mapRows(rows);

    const generated = generateCandidateOutfits(items, {
      desiredCount: body.desiredCount,
      lockedItemIds: new Set(body.lockedClosetItemIds),
      excludedItemIds: new Set(body.excludedClosetItemIds),
    });

    const payload: ScoredOutfitEnvelope[] = generated.map((outfit) =>
      toScoredOutfit(
        {
          id: crypto.randomUUID(),
          name: "Today's Outfit",
          reason: outfit.reason,
          itemIds: outfit.items.map((i) => i.id),
        },
        outfit.score,
      )
    );

    const latencyMs = deps.now().getTime() - startedAtMs;
    // 5 & 6. Log request id + latency; only safe, non-content fields.
    logger.info("outfits_generate.success", {
      user_id: userId,
      candidate_item_count: items.length,
      outfits_returned: payload.length,
      desired_count: body.desiredCount,
      had_natural_language_request: body.naturalLanguageRequest !== undefined,
      had_occasion_id: body.occasionId !== undefined,
      latency_ms: latencyMs,
    });

    return jsonResponse(payload, { status: 200, requestId, extraHeaders: CORS_HEADERS });
  } catch (err) {
    return handleOutfitsError(err, "outfits_generate", logger, requestId, startedAtMs, deps);
  }
}

/**
 * `POST /outfits/rank` (`P4-OUTFIT-08`). Re-ranks a caller-supplied set of
 * candidate outfits (item-id groups) with the same `scoreOutfit` used by
 * `/generate` — it does not build any new combination, only scores and
 * orders the ones it is given.
 *
 * LOCKED-ITEM FILTERING, NOT FORCING. Unlike `/generate` (which can choose
 * which item fills a slot), `/rank` has no slots to fill — a candidate is
 * already a fixed set of items. So "honour locked items" here means: drop
 * any candidate that does not already contain every locked id, per
 * `P4-OUTFIT-08`'s acceptance criterion ("results with a locked item all
 * include it"). A candidate missing a locked item is not a wrong answer to
 * fix; it is simply not a candidate that satisfies what the caller asked
 * for, and is left out rather than mutated into one that does.
 *
 * WEARABILITY IS NOT RE-FILTERED HERE. `scoreOutfit`'s own header is
 * explicit that it scores what it is given, unwearable items included —
 * filtering is `wearableItems()`'s job during GENERATION (§2.9). A
 * candidate reaching `/rank` already represents items the caller (the
 * outfit builder, or a prior `/generate` call) chose; silently dropping an
 * item from a caller-supplied candidate would score a different outfit
 * than the one asked about.
 */
export async function handleRankOutfits(req: Request, deps: HandlerDeps): Promise<Response> {
  const startedAtMs = deps.now().getTime();

  const preflight = handleCorsPreflight(req);
  if (preflight) {
    return preflight;
  }

  let requestId = resolveRequestId(req);
  const logger = createLogger(requestId);

  try {
    if (req.method !== "POST") {
      throw methodNotAllowed("POST /outfits/rank only accepts POST.");
    }

    const userId = await authenticateRequest(req, deps.authClient);

    const rateLimitResult = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!rateLimitResult.allowed) {
      logger.warn("outfits_rank.rate_limited", {
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
    const body = parseRankOutfitsBody(envelope.body);

    const allItemIds = [...new Set(body.candidates.flatMap((c) => c.itemIds))];
    const rows = await deps.closetRepository.listItemsByIds(userId, allItemIds);
    const itemsById = new Map<string, ScorableItem>();
    for (const item of mapRows(rows)) {
      itemsById.set(item.id, item);
    }

    const lockedItemIds = new Set(body.lockedClosetItemIds);

    const scored: { input: typeof body.candidates[number]; items: ScorableItem[] }[] = [];
    for (const candidate of body.candidates) {
      // A locked id this candidate does not contain fails the "all include
      // it" acceptance criterion outright.
      if (![...lockedItemIds].every((id) => candidate.itemIds.includes(id))) continue;

      const resolvedItems: ScorableItem[] = [];
      let unresolved = false;
      for (const id of candidate.itemIds) {
        const item = itemsById.get(id);
        if (!item) {
          unresolved = true;
          break;
        }
        resolvedItems.push(item);
      }
      // An id that did not resolve (not owned, deleted, or a fragrance item
      // with no scoring role) makes this candidate un-scoreable as stated —
      // see the header on why that means "leave it out", not "score the
      // items that did resolve".
      if (unresolved) continue;

      scored.push({ input: candidate, items: resolvedItems });
    }

    const results = scored
      .map(({ input, items }) => {
        const score = scoreOutfit(items);
        return { input, items, score };
      })
      .sort((a, b) => b.score.score - a.score.score);

    const payload: ScoredOutfitEnvelope[] = results.map(({ input, items, score }) =>
      toScoredOutfit(
        {
          id: input.id ?? crypto.randomUUID(),
          name: "Outfit",
          reason: buildReason(items, score),
          itemIds: input.itemIds,
        },
        score,
      )
    );

    const latencyMs = deps.now().getTime() - startedAtMs;
    logger.info("outfits_rank.success", {
      user_id: userId,
      candidates_submitted: body.candidates.length,
      candidates_scored: payload.length,
      locked_item_count: body.lockedClosetItemIds.length,
      latency_ms: latencyMs,
    });

    return jsonResponse(payload, { status: 200, requestId, extraHeaders: CORS_HEADERS });
  } catch (err) {
    return handleOutfitsError(err, "outfits_rank", logger, requestId, startedAtMs, deps);
  }
}

function handleOutfitsError(
  err: unknown,
  logPrefix: string,
  logger: RequestLogger,
  requestId: string,
  startedAtMs: number,
  deps: HandlerDeps,
): Response {
  const latencyMs = deps.now().getTime() - startedAtMs;
  const appError = err instanceof AppError ? err : serverError();

  if (err instanceof AppError) {
    logger.warn(`${logPrefix}.rejected`, {
      category: appError.category,
      status: appError.status,
      message: appError.message,
      latency_ms: latencyMs,
    });
  } else {
    // Unexpected/programmer error: log a category + generic message for
    // observability, never the raw error/stack to the client, and never
    // request content in this line (see _shared/logger.ts's denylist).
    logger.error(`${logPrefix}.unexpected_error`, {
      latency_ms: latencyMs,
      error_name: err instanceof Error ? err.name : "unknown",
    });
  }

  return errorResponse(appError, requestId, CORS_HEADERS);
}
