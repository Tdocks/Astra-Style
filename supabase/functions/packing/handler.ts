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
import type {
  OutfitScorer,
  OutfitScorerRow,
  ScoredOutfit,
} from "../_shared/scoring/outfitScorer.ts";
import {
  type GeneratePackingBody,
  type PackingDayWire,
  type PackingPlanWire,
  parseEnvelope,
  parseGeneratePackingBody,
  planDates,
} from "./schema.ts";

export interface OccasionRow {
  readonly starts_at: string;
  readonly title: string;
  readonly dress_code: string | null;
}

export interface OutfitDraft {
  readonly compatibilityScore: number;
  readonly reason: string;
  readonly itemIds: readonly string[];
  readonly rolesByItemId: ReadonlyMap<string, string>;
  readonly name: string;
}

export interface BriefRow {
  readonly id: string;
  readonly user_id: string;
  readonly brief_date: string;
  readonly primary_outfit_id: string | null;
  readonly alternative_outfit_ids: unknown;
  readonly schedule_snapshot: Record<string, unknown>;
}

export interface PackingRepository {
  listCandidateItems(userId: string): Promise<OutfitScorerRow[]>;
  listOccasions(userId: string, fromDate: string, toExclusive: string): Promise<OccasionRow[]>;
  findBriefs(userId: string, dates: readonly string[]): Promise<BriefRow[]>;
  createOutfits(userId: string, drafts: readonly OutfitDraft[]): Promise<string[]>;
  upsertBrief(input: {
    userId: string;
    briefDate: string;
    primaryOutfitId: string | null;
    alternativeOutfitIds: readonly string[];
    scheduleSnapshot: Record<string, unknown>;
  }): Promise<BriefRow>;
  listOutfitItemIds(outfitIds: readonly string[]): Promise<string[]>;
}

export interface HandlerDeps {
  authClient: AuthClient;
  repository: PackingRepository;
  scorerForDay: (targetOccasion?: string) => OutfitScorer;
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

function occasionsOnDay(rows: readonly OccasionRow[], day: string): OccasionRow[] {
  return rows.filter((row) => row.starts_at.slice(0, 10) === day);
}

function targetOccasion(
  dayOccasions: readonly OccasionRow[],
  dressCodes: readonly string[],
  activities: readonly string[],
): string | undefined {
  const fromRow = dayOccasions[0]?.dress_code ?? dayOccasions[0]?.title;
  if (fromRow && fromRow.length > 0) return fromRow;
  if (dressCodes[0]) return dressCodes[0];
  if (activities[0]) return activities[0];
  return undefined;
}

function outfitName(day: string, dayOccasions: readonly OccasionRow[]): string {
  const title = dayOccasions[0]?.title?.trim();
  if (title) return title;
  return day;
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

async function buildPlan(
  userId: string,
  body: GeneratePackingBody,
  dates: readonly string[],
  deps: HandlerDeps,
): Promise<PackingPlanWire> {
  if (!body.regenerate) {
    const existing = await existingPlan(userId, dates, deps);
    if (existing) return existing;
  }

  const items = await deps.repository.listCandidateItems(userId);
  const rolesByItemId = new Map(items.map((item) => [item.id, item.category as string]));
  const lastExclusive = dates[dates.length - 1]
    ? nextExclusive(dates[dates.length - 1]!)
    : body.endDate;
  const occasions = await deps.repository.listOccasions(userId, body.startDate, lastExclusive);

  const used = new Set<string>();
  const packingList = new Set<string>();
  const daily: PackingDayWire[] = [];
  const missing: string[] = [];

  for (const day of dates) {
    const dayOccasions = occasionsOnDay(occasions, day);
    const occasion = targetOccasion(dayOccasions, body.dressCodes, body.activities);
    const scorer = deps.scorerForDay(occasion);
    const scored = pickOutfit(scorer, items, used);
    if (!scored.outfit) {
      missing.push(`No wearable look for ${day}.`);
      await deps.repository.upsertBrief({
        userId,
        briefDate: day,
        primaryOutfitId: null,
        alternativeOutfitIds: [],
        scheduleSnapshot: {
          event_count: dayOccasions.length,
          headline: dayOccasions[0]?.title ?? null,
        },
      });
      continue;
    }

    const ids = await deps.repository.createOutfits(userId, [{
      compatibilityScore: scored.outfit.compatibilityScore,
      reason: scored.outfit.reason,
      itemIds: scored.outfit.itemIds,
      rolesByItemId,
      name: outfitName(day, dayOccasions),
    }]);
    const outfitId = ids[0];
    if (!outfitId) {
      throw serverError("Couldn't save that day's look.");
    }

    for (const itemId of scored.outfit.itemIds) {
      used.add(itemId);
      packingList.add(itemId);
    }

    await deps.repository.upsertBrief({
      userId,
      briefDate: day,
      primaryOutfitId: outfitId,
      alternativeOutfitIds: [],
      scheduleSnapshot: {
        event_count: dayOccasions.length,
        headline: dayOccasions[0]?.title ?? null,
      },
    });

    daily.push({ date: day, outfit_id: outfitId, is_rewear: scored.isRewear });
    if (scored.isRewear && !body.hasLaundryAccess) {
      missing.push(`No laundry — ${day} rewears a piece from earlier.`);
    }
  }

  const note = body.destination.length > 0
    ? "Pack a rain shell if the forecast shifts. Astra does not invent weather for a city it cannot see."
    : null;

  return {
    packing_list_item_ids: [...packingList],
    daily_outfit_plan: daily,
    missing_essentials: missing,
    weather_contingency_note: note,
  };
}

async function existingPlan(
  userId: string,
  dates: readonly string[],
  deps: HandlerDeps,
): Promise<PackingPlanWire | null> {
  const briefs = await deps.repository.findBriefs(userId, dates);
  if (briefs.length < dates.length) return null;
  const byDate = new Map(briefs.map((row) => [row.brief_date, row]));
  const daily: PackingDayWire[] = [];
  const outfitIds: string[] = [];
  for (const day of dates) {
    const brief = byDate.get(day);
    if (!brief?.primary_outfit_id) return null;
    outfitIds.push(brief.primary_outfit_id);
    daily.push({ date: day, outfit_id: brief.primary_outfit_id, is_rewear: false });
  }
  const itemIds = await deps.repository.listOutfitItemIds(outfitIds);
  return {
    packing_list_item_ids: itemIds,
    daily_outfit_plan: daily,
    missing_essentials: [],
    weather_contingency_note: null,
  };
}

function pickOutfit(
  scorer: OutfitScorer,
  items: readonly OutfitScorerRow[],
  used: ReadonlySet<string>,
): { outfit: ScoredOutfit | null; isRewear: boolean } {
  const fresh = scorer.generate(items, {
    desiredCount: 1,
    lockedItemIds: new Set(),
    excludedItemIds: used,
  })[0];
  if (fresh) return { outfit: fresh, isRewear: false };
  if (used.size === 0) return { outfit: null, isRewear: false };
  const reused = scorer.generate(items, {
    desiredCount: 1,
    lockedItemIds: new Set(),
    excludedItemIds: new Set(),
  })[0];
  return { outfit: reused ?? null, isRewear: reused != null };
}

function nextExclusive(day: string): string {
  const next = new Date(`${day}T00:00:00Z`);
  next.setUTCDate(next.getUTCDate() + 1);
  return next.toISOString().slice(0, 10);
}
