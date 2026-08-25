// ============================================================================
// daily-brief/handler.ts
// ============================================================================
// `POST /daily-brief/generate` (spec §14, §6.11; ticket P4-HOME-02).
// Deployment wiring lives in `index.ts`; everything here takes injected
// dependencies and no network, so `handler_test.ts` drives it directly.
//
// WHAT THIS ENDPOINT IS FOR, AND WHAT IT DELIBERATELY IS NOT
//
// It assembles the day's brief: a primary outfit, its alternatives, and
// whatever schedule context exists — persisted as one `daily_briefs` row.
// One of §14's listed inputs is NOT assembled here, and its absence is the
// honest answer rather than an oversight:
//
//   * A KYRA-AUTHORED MESSAGE. The compatibility scorer explains measured
//     components, but that deterministic explanation is not a model-authored
//     stylist note. `kyra_message` stays null rather than relabeling scorer
//     copy as Kyra's judgement; `HomeView` renders the module only when a
//     genuine message is present.
//
// WEATHER (P4-HOME-05) is assembled, but not looked up here — there is
// still no server-side weather provider. `weather_snapshot` is exactly
// whatever the caller's own `WeatherService` reading was, validated by
// `parseWeatherSnapshot`, converted from the iOS wire convention (Fahrenheit)
// to the scorer's canonical Celsius, and passed through to `upsertBrief`. A
// request with no weather (permission never granted, or the lookup failed)
// still succeeds; `weather_snapshot` is null and the weather component uses
// its documented prior. This handler never invents a forecast.
//
// IDEMPOTENCY (P4-HOME-02's second acceptance criterion) is enforced in two
// independent places, because one of them alone is a race. The handler
// reads the existing brief first and returns it untouched; and the write is
// an upsert on the table's own `(user_id, brief_date)` unique constraint,
// so two requests that both miss the read still converge on one row instead
// of one succeeding and one 500ing.
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
import type { OutfitScorer, OutfitScorerRow } from "../_shared/scoring/outfitScorer.ts";
import type { ScoringContext } from "../_shared/scoring/types.ts";
import { FREE_DAILY_BRIEF_COUNT, morningLoopQuotaError } from "../_shared/premium.ts";
import {
  type DailyBriefRow,
  mapBriefRowToWire,
  parseEnvelope,
  parseGenerateDailyBriefBody,
} from "./schema.ts";

/** One outfit to persist before the brief can reference it. */
export interface OutfitDraft {
  readonly compatibilityScore: number;
  readonly reason: string;
  /** Closet item ids, in the order the scorer produced them. */
  readonly itemIds: readonly string[];
  /** Category per item id, so `outfit_items.role` is a real role. */
  readonly rolesByItemId: ReadonlyMap<string, string>;
}

export interface BriefRepository {
  /** Today's brief for this user, or null. */
  findBrief(userId: string, briefDate: string): Promise<DailyBriefRow | null>;

  /** Non-archived, currently wearable candidate items. */
  listCandidateItems(userId: string): Promise<OutfitScorerRow[]>;

  /**
   * Count of occasions starting within the brief's day, for
   * `schedule_snapshot`. Zero is a real answer and is stored as such — an
   * empty diary is a fact about the day, not a missing reading.
   */
  countOccasions(userId: string, briefDate: string): Promise<number>;

  /**
   * Persists the drafts as `outfits` + `outfit_items` rows and returns
   * their ids in the same order.
   *
   * Outfits must exist as rows BEFORE the brief is written:
   * `daily_briefs.primary_outfit_id` is a foreign key into `outfits`, so a
   * brief referencing the client-minted ids that `POST /outfits/generate`
   * returns — which are never persisted anywhere — would be rejected by the
   * database. That asymmetry between the two endpoints is easy to miss.
   */
  createOutfits(userId: string, drafts: readonly OutfitDraft[]): Promise<string[]>;

  /** Upsert on `(user_id, brief_date)`; returns the stored row. */
  upsertBrief(input: UpsertBriefInput): Promise<DailyBriefRow>;
}

export interface UpsertBriefInput {
  readonly userId: string;
  readonly briefDate: string;
  readonly primaryOutfitId: string | null;
  readonly alternativeOutfitIds: readonly string[];
  readonly weatherSnapshot: Record<string, unknown> | null;
  readonly scheduleSnapshot: Record<string, unknown>;
}

export interface HandlerDeps {
  authClient: AuthClient;
  repository: BriefRepository;
  scorer: OutfitScorer;
  rateLimiter: RateLimiter;
  now: () => Date;
  hasActivePremiumSubscription?: (nowIso: string) => Promise<boolean>;
  countBriefs?: (userId: string) => Promise<number>;
}

/**
 * How many outfits to ask the scorer for: one primary plus alternatives.
 *
 * P4-HOME-02's first acceptance criterion is "a primary outfit and at least
 * one alternative", so asking for two would satisfy it exactly and leave no
 * margin — the scorer returns fewer than requested whenever the closet runs
 * out of a role, which is the common case for a new user. Four is the
 * §6.11 alternatives carousel's own comfortable size.
 */
const DESIRED_OUTFIT_COUNT = 4;

const WET_CONDITIONS = new Set([
  "rain",
  "drizzle",
  "thunderstorm",
  "snow",
  "sleet",
]);

/**
 * Turns the device snapshot into the exact context §2.5 scores.
 *
 * `LiveWeatherService` stores the wire snapshot in Fahrenheit so the existing
 * iOS formatter and persisted briefs remain backward compatible. The scoring
 * core is canonical Celsius. Convert at this boundary rather than letting a
 * 71°F day become 71°C and rank every warm garment as a total miss.
 *
 * Current apparent temperature is the best dressing signal when WeatherKit
 * supplied it. Older briefs only carry high/low, so their midpoint is the
 * honest fallback. Precipitation chance is measured when present; otherwise
 * the measured condition answers only the binary rain threshold the scorer
 * needs.
 */
export function weatherScoringContext(
  snapshot: Record<string, unknown> | null,
): ScoringContext {
  if (snapshot === null) return {};

  const high = snapshot["temperature_high"];
  const low = snapshot["temperature_low"];
  if (typeof high !== "number" || typeof low !== "number") return {};

  const apparent = snapshot["apparent_temperature"];
  const temperatureF = typeof apparent === "number" ? apparent : (high + low) / 2;
  const rawPrecipitation = snapshot["precipitation_chance"];
  const condition = snapshot["condition"];
  const precipitationProbability = typeof rawPrecipitation === "number"
    ? Math.min(1, Math.max(0, rawPrecipitation))
    : typeof condition === "string" && WET_CONDITIONS.has(condition)
    ? 1
    : 0;

  return {
    weather: {
      temperatureC: (temperatureF - 32) * 5 / 9,
      precipitationProbability,
    },
  };
}

function hasStoredWeather(value: unknown): boolean {
  return typeof value === "object" && value !== null && !Array.isArray(value) &&
    Object.keys(value as Record<string, unknown>).length > 0;
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

export async function handleGenerateDailyBrief(req: Request, deps: HandlerDeps): Promise<Response> {
  const startedAtMs = deps.now().getTime();

  const preflight = handleCorsPreflight(req);
  if (preflight) {
    return preflight;
  }

  let requestId = resolveRequestId(req);
  const logger = createLogger(requestId);

  try {
    if (req.method !== "POST") {
      throw methodNotAllowed("POST /daily-brief/generate only accepts POST.");
    }

    // 1. JWT is the only source of identity for this request.
    const userId = await authenticateRequest(req, deps.authClient);

    // 2. Rate limit before parsing, so garbage bodies cost nothing.
    const rateLimit = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!rateLimit.allowed) {
      logger.warn("daily_brief_generate.rate_limited", {
        user_id: userId,
        retry_after_seconds: rateLimit.retryAfterSeconds,
      });
      return errorResponse(
        new AppError("rate_limited", 429, "Too many requests. Please try again shortly."),
        requestId,
        { ...CORS_HEADERS, "Retry-After": String(rateLimit.retryAfterSeconds) },
      );
    }

    // 3. Schema.
    const envelope = parseEnvelope(await readJsonBody(req));
    requestId = resolveRequestId(req, envelope.requestId);
    logger.adoptRequestId(requestId);
    const body = parseGenerateDailyBriefBody(envelope.body);

    // 4. Idempotency, half one. The row is scoped by RLS to this caller, so
    // "the existing brief" can only ever be his own.
    let refreshingMissingWeather = false;
    if (!body.regenerate) {
      const existing = await deps.repository.findBrief(userId, body.briefDate);
      if (existing) {
        // Enabling weather after Home already created today's brief is the
        // one non-destructive cache refresh. Returning the old row would put
        // a real forecast in the header while keeping an outfit ranked with
        // the no-weather prior. Rebuild once when the stored row has no
        // forecast; later reads stay idempotent.
        refreshingMissingWeather = body.weatherSnapshot !== null &&
          !hasStoredWeather(existing.weather_snapshot);
        if (!refreshingMissingWeather) {
          logger.info("daily_brief_generate.returned_existing", {
            user_id: userId,
            brief_date: body.briefDate,
            latency_ms: deps.now().getTime() - startedAtMs,
          });
          return jsonResponse(mapBriefRowToWire(existing), {
            status: 200,
            requestId,
            extraHeaders: CORS_HEADERS,
          });
        }
      }
    }

    const premium = deps.hasActivePremiumSubscription
      ? await deps.hasActivePremiumSubscription(deps.now().toISOString())
      : true;
    if (!premium && !refreshingMissingWeather) {
      const used = deps.countBriefs ? await deps.countBriefs(userId) : 0;
      if (used >= FREE_DAILY_BRIEF_COUNT) {
        throw morningLoopQuotaError(
          "You've used your free Daily Briefs. Upgrade to Astra Style Premium for a full brief every morning.",
        );
      }
    }

    const brief = await buildBrief(userId, body.briefDate, body.weatherSnapshot, deps);

    logger.info("daily_brief_generate.success", {
      user_id: userId,
      brief_date: body.briefDate,
      regenerated: body.regenerate,
      refreshed_missing_weather: refreshingMissingWeather,
      has_primary_outfit: brief.primary_outfit_id !== null,
      alternative_count: Array.isArray(brief.alternative_outfit_ids)
        ? brief.alternative_outfit_ids.length
        : 0,
      latency_ms: deps.now().getTime() - startedAtMs,
    });

    return jsonResponse(mapBriefRowToWire(brief), {
      status: 200,
      requestId,
      extraHeaders: CORS_HEADERS,
    });
  } catch (err) {
    const latencyMs = deps.now().getTime() - startedAtMs;
    const appError = err instanceof AppError ? err : serverError();

    if (err instanceof AppError) {
      logger.warn("daily_brief_generate.rejected", {
        category: appError.category,
        status: appError.status,
        message: appError.message,
        latency_ms: latencyMs,
      });
    } else {
      logger.error("daily_brief_generate.unexpected_error", {
        latency_ms: latencyMs,
        error_name: err instanceof Error ? err.name : "unknown",
      });
    }

    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}

/**
 * Builds and stores the day's brief.
 *
 * The empty-closet path is not an error and not an early return with a
 * different shape: it writes a real row whose `primary_outfit_id` is null.
 * `DailyBrief.hasPrimaryOutfit` on the client is what drives §6.11's "add
 * five pieces" empty state, so "no outfit today" has to be a brief the
 * client can hold, not a failure it has to interpret.
 */
async function buildBrief(
  userId: string,
  briefDate: string,
  weatherSnapshot: Record<string, unknown> | null,
  deps: HandlerDeps,
): Promise<DailyBriefRow> {
  const items = await deps.repository.listCandidateItems(userId);
  const rolesByItemId = new Map(items.map((item) => [item.id, item.category as string]));

  const scored = deps.scorer.generate(items, {
    desiredCount: DESIRED_OUTFIT_COUNT,
    lockedItemIds: new Set<string>(),
    excludedItemIds: new Set<string>(),
    context: weatherScoringContext(weatherSnapshot),
  });

  const occasionCount = await deps.repository.countOccasions(userId, briefDate);

  const outfitIds = scored.length === 0 ? [] : await deps.repository.createOutfits(
    userId,
    scored.map((outfit) => ({
      compatibilityScore: outfit.compatibilityScore,
      reason: outfit.reason,
      itemIds: outfit.itemIds,
      rolesByItemId,
    })),
  );

  return deps.repository.upsertBrief({
    userId,
    briefDate,
    primaryOutfitId: outfitIds[0] ?? null,
    alternativeOutfitIds: outfitIds.slice(1),
    weatherSnapshot,
    // `event_count` only. `earliest_formality_level` would need each
    // occasion's dress code mapped onto a formality band, and
    // `headline` would be prose about the day — both are P4-HOME-06 work
    // and neither is derivable from a count.
    scheduleSnapshot: { event_count: occasionCount },
  });
}
