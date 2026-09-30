// ============================================================================
// GET /closet/wardrobe-score
// ============================================================================
// Computes the score from the authenticated user's current closet and profile
// rows. It deliberately does not persist a derived copy that could drift after
// a closet edit or wear event. Every read uses the caller's JWT and RLS.
// ============================================================================

import type { SupabaseClient } from "@supabase/supabase-js";
import { CORS_HEADERS, handleCorsPreflight } from "../_shared/cors.ts";
import {
  AppError,
  errorResponse,
  jsonResponse,
  rateLimited,
  serverError,
} from "../_shared/errors.ts";
import { createLogger } from "../_shared/logger.ts";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import {
  type ClosetItemMapperRow,
  mapClosetItemRowToScorableItem,
} from "../_shared/scoring/closetItemMapper.ts";
import {
  computeWardrobeScore,
  FIXED_MINIMUM_OCCASIONS,
  type WardrobeItem,
} from "../_shared/scoring/wardrobeScore.ts";
import type { FitNote } from "../_shared/scoring/subscores/silhouette.ts";

interface ClosetScoreRow extends ClosetItemMapperRow {
  readonly condition: string | null;
  readonly created_at: string;
  readonly archived_at: string | null;
}

interface ClosetFeedbackRow {
  readonly target_id: string;
  readonly signal: string;
}

interface ScoredWearRow {
  readonly outfit_id: string;
}

interface OutfitItemRow {
  readonly closet_item_id: string | null;
}

interface OccasionOutfitRow {
  readonly occasion_tags: unknown;
  readonly compatibility_score: number | null;
}

interface WardrobeScoreDependencies {
  readonly authClient: AuthClient;
  readonly supabase: SupabaseClient;
  readonly rateLimiter: RateLimiter;
  readonly now: () => Date;
}

const FIT_NOTES: ReadonlySet<string> = new Set<FitNote>([
  "broad_chest",
  "short_torso",
  "long_legs",
  "large_thighs",
]);
const CONDITIONS: ReadonlySet<string> = new Set([
  "new_with_tags",
  "like_new",
  "good",
  "fair",
  "worn",
  "damaged",
]);

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is string => typeof entry === "string");
}

function rowDate(value: string): Date {
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds)) {
    throw serverError("Couldn't read your closet score data.");
  }
  return new Date(milliseconds);
}

function wardrobeItems(rows: readonly ClosetScoreRow[]): WardrobeItem[] {
  const result: WardrobeItem[] = [];
  for (const row of rows) {
    const item = mapClosetItemRowToScorableItem(row);
    if (!item) continue;
    const condition = row.condition;
    result.push({
      ...item,
      condition: condition !== null && CONDITIONS.has(condition)
        ? condition as WardrobeItem["condition"]
        : null,
      addedAt: rowDate(row.created_at),
      archivedAt: row.archived_at === null ? null : rowDate(row.archived_at),
      lastWornAt: item.lastWornAt ?? null,
    });
  }
  return result;
}

async function readScoreContext(
  supabase: WardrobeScoreDependencies["supabase"],
  itemIds: readonly string[],
) {
  const [bodyResult, lifestyleResult, outfitsResult, feedbackResult, wearsResult] = await Promise
    .all([
      supabase.from("body_profiles").select("fit_notes").maybeSingle(),
      supabase.from("lifestyle_profiles").select("common_occasions").maybeSingle(),
      supabase.from("outfits").select("occasion_tags,compatibility_score")
        .is("archived_at", null),
      supabase.from("style_feedback").select("target_id,signal")
        .eq("target_type", "closet_item").in("target_id", [...itemIds]),
      supabase.from("outfit_wears").select("outfit_id").gte("rating", 4),
    ]);

  if (
    bodyResult.error || lifestyleResult.error || outfitsResult.error || feedbackResult.error ||
    wearsResult.error
  ) {
    throw serverError("Couldn't load the profile details needed for your Wardrobe Score.");
  }

  const fitNotesRaw = (bodyResult.data as { fit_notes?: unknown } | null)?.fit_notes;
  const allFitNotes = stringArray(fitNotesRaw);
  const fitNotes = allFitNotes.filter((value): value is FitNote => FIT_NOTES.has(value));
  const unavailableFitNotes = allFitNotes.filter((value) => !FIT_NOTES.has(value));
  const additionalTargetOccasions = stringArray(
    (lifestyleResult.data as { common_occasions?: unknown } | null)?.common_occasions,
  );
  const targets = [...new Set([...FIXED_MINIMUM_OCCASIONS, ...additionalTargetOccasions])];

  const outfitRows = (outfitsResult.data ?? []) as OccasionOutfitRow[];
  const occasionCoverage = new Map<string, boolean>(targets.map((occasion) => [occasion, false]));
  for (const outfit of outfitRows) {
    if ((outfit.compatibility_score ?? 0) < 70) continue;
    for (const tag of stringArray(outfit.occasion_tags)) {
      if (occasionCoverage.has(tag)) occasionCoverage.set(tag, true);
    }
  }

  const feedbackRows = (feedbackResult.data ?? []) as ClosetFeedbackRow[];
  const ratingRows = (wearsResult.data ?? []) as ScoredWearRow[];
  const ratedOutfitIds = [...new Set(ratingRows.map((row) => row.outfit_id))];
  let ratedOutfitItemRows: OutfitItemRow[] = [];
  if (ratedOutfitIds.length > 0) {
    const result = await supabase.from("outfit_items").select("closet_item_id")
      .in("outfit_id", ratedOutfitIds).in("closet_item_id", [...itemIds]);
    if (result.error) {
      throw serverError("Couldn't load the wear history needed for your Wardrobe Score.");
    }
    ratedOutfitItemRows = (result.data ?? []) as OutfitItemRow[];
  }

  const feedbackByItemId = new Map<
    string,
    { hasPositiveSignal: boolean; hasNegativeSignal: boolean }
  >();
  for (const row of feedbackRows) {
    const flags = feedbackByItemId.get(row.target_id) ??
      { hasPositiveSignal: false, hasNegativeSignal: false };
    if (row.signal === "like") flags.hasPositiveSignal = true;
    if (row.signal === "bad_fit" || row.signal === "dislike") flags.hasNegativeSignal = true;
    feedbackByItemId.set(row.target_id, flags);
  }
  for (const row of ratedOutfitItemRows) {
    if (!row.closet_item_id) continue;
    const flags = feedbackByItemId.get(row.closet_item_id) ??
      { hasPositiveSignal: false, hasNegativeSignal: false };
    flags.hasPositiveSignal = true;
    feedbackByItemId.set(row.closet_item_id, flags);
  }

  return {
    fitNotes,
    unavailableFitNotes,
    additionalTargetOccasions,
    occasionCoverage,
    ...(feedbackRows.length > 0 || ratedOutfitItemRows.length > 0 ? { feedbackByItemId } : {}),
  };
}

export async function handleWardrobeScore(
  req: Request,
  deps: WardrobeScoreDependencies,
): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  const requestId = resolveRequestId(req);
  const logger = createLogger(requestId);
  const startedAt = deps.now().getTime();

  try {
    const userId = await authenticateRequest(req, deps.authClient);
    const limit = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!limit.allowed) {
      return errorResponse(
        rateLimited("Please wait a moment before refreshing your Wardrobe Score."),
        requestId,
        { ...CORS_HEADERS, "Retry-After": String(limit.retryAfterSeconds) },
      );
    }

    const closetResult = await deps.supabase.from("closet_items")
      .select(
        "id,category,primary_color,secondary_colors,pattern,material,fit,seasonality,formality_score,warmth_score,water_resistance_score,laundry_state,availability_state,last_worn_at,condition,created_at,archived_at",
      )
      .is("archived_at", null);
    if (closetResult.error) throw serverError("Couldn't load your closet for the Wardrobe Score.");

    const allItems = wardrobeItems((closetResult.data ?? []) as ClosetScoreRow[]);
    const items = allItems.filter((item) => item.archivedAt === null);
    if (items.length === 0) {
      const empty = computeWardrobeScore([], deps.now());
      logger.info("closet_wardrobe_score.completed", {
        active_item_count: 0,
        duration_ms: Math.max(0, deps.now().getTime() - startedAt),
      });
      return jsonResponse({
        score: empty.score,
        active_item_count: empty.activeItemCount,
        confidence: empty.confidence,
        components: Object.fromEntries(
          Object.entries(empty.components).map(([name, value]) => [
            name,
            { value: Math.round(value.value * 100), degraded: value.degraded.length > 0 },
          ]),
        ),
      }, { requestId, extraHeaders: CORS_HEADERS });
    }

    const context = await readScoreContext(deps.supabase, items.map((item) => item.id));
    const result = computeWardrobeScore(items, deps.now(), context);
    logger.info("closet_wardrobe_score.completed", {
      active_item_count: result.activeItemCount,
      duration_ms: Math.max(0, deps.now().getTime() - startedAt),
    });
    return jsonResponse({
      score: result.score,
      active_item_count: result.activeItemCount,
      confidence: result.confidence,
      components: Object.fromEntries(
        Object.entries(result.components).map(([name, value]) => [
          name,
          { value: Math.round(value.value * 100), degraded: value.degraded.length > 0 },
        ]),
      ),
    }, { requestId, extraHeaders: CORS_HEADERS });
  } catch (error) {
    const appError = error instanceof AppError
      ? error
      : serverError("Couldn't calculate your Wardrobe Score just now.");
    logger.error("closet_wardrobe_score.failed", { category: appError.category });
    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}
