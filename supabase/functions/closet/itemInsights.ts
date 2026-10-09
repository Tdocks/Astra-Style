import type { SupabaseClient } from "@supabase/supabase-js";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import {
  AppError,
  badRequest,
  errorResponse,
  jsonResponse,
  notFound,
  rateLimited,
  serverError,
} from "../_shared/errors.ts";
import { CORS_HEADERS, handleCorsPreflight } from "../_shared/cors.ts";
import { computeItemInsights, type InsightItem } from "../_shared/scoring/itemInsights.ts";
import {
  type ClosetItemMapperRow,
  mapClosetItemRowToScorableItem,
} from "../_shared/scoring/closetItemMapper.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { createLogger } from "../_shared/logger.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
interface ItemRow extends ClosetItemMapperRow {
  condition: string | null;
  archived_at: string | null;
}
interface OutfitRow {
  id: string;
  archived_at: string | null;
}
interface LinkRow {
  id: string;
  outfit_id: string;
  closet_item_id: string | null;
}
const ITEM_COLUMNS =
  "id,category,primary_color,secondary_colors,pattern,material,fit,seasonality,formality_score,warmth_score,water_resistance_score,laundry_state,availability_state,last_worn_at,condition,archived_at";
/** Stable pagination prevents silently ignoring garments beyond PostgREST's row cap. */
async function rows<T>(
  client: SupabaseClient,
  table: string,
  columns: string,
  userId: string,
): Promise<T[]> {
  const result: T[] = [];
  for (let page = 0; page < 100; page++) {
    const response = await client.from(table).select(columns).eq("user_id", userId).order("id")
      .range(page * 500, page * 500 + 499);
    if (response.error) throw serverError("Couldn't load your item insights.");
    const batch = (response.data ?? []) as T[];
    result.push(...batch);
    if (batch.length < 500) return result;
  }
  throw serverError("Your closet is too large to load its insights right now.");
}
export async function handleItemInsights(
  req: Request,
  deps: { authClient: AuthClient; supabase: SupabaseClient; rateLimiter: RateLimiter },
  itemId: string,
): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  const requestId = resolveRequestId(req);
  const logger = createLogger(requestId);
  const startedAt = Date.now();
  try {
    const userId = await authenticateRequest(req, deps.authClient);
    const limit = deps.rateLimiter.check(userId, Date.now());
    if (!limit.allowed) throw rateLimited("Please wait a moment before refreshing item insights.");
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(itemId)) {
      throw badRequest("Choose a valid closet item.");
    }
    const [items, outfits, links, profile] = await Promise.all([
      rows<ItemRow>(deps.supabase, "closet_items", ITEM_COLUMNS, userId),
      rows<OutfitRow>(deps.supabase, "outfits", "id,archived_at", userId),
      rows<LinkRow>(deps.supabase, "outfit_items", "id,outfit_id,closet_item_id", userId),
      deps.supabase.from("profiles").select("wardrobe_graph").eq("id", userId).maybeSingle(),
    ]);
    if (profile.error) throw serverError("Couldn't load your styling preferences.");
    const targetRow = items.find((item) => item.id === itemId.toLowerCase());
    if (!targetRow) throw notFound("That closet item is unavailable.");
    const mapped = mapClosetItemRowToScorableItem(targetRow);
    if (!mapped) throw badRequest("Insights aren't available for this item category yet.");
    const closet: InsightItem[] = items.flatMap((row) => {
      const item = mapClosetItemRowToScorableItem(row);
      return item
        ? [{
          ...item,
          condition: row.condition,
          archivedAt: row.archived_at ? new Date(row.archived_at) : null,
        }]
        : [];
    });
    const target = {
      ...mapped,
      condition: targetRow.condition,
      archivedAt: targetRow.archived_at ? new Date(targetRow.archived_at) : null,
    };
    const gallery = outfits.map((outfit) => ({
      id: outfit.id,
      archivedAt: outfit.archived_at ? new Date(outfit.archived_at) : null,
      itemIds: links.filter((link) => link.outfit_id === outfit.id).flatMap((link) =>
        link.closet_item_id ? [link.closet_item_id] : []
      ),
    }));
    const result = computeItemInsights(target, closet, gallery, {
      wardrobeGraph: profile.data?.wardrobe_graph === "womenswear"
        ? "womenswear"
        : "menswear_3_role",
    });
    logger.info("closet_item_insights.completed", { duration_ms: Date.now() - startedAt });
    return jsonResponse(result, {
      requestId,
      extraHeaders: { ...CORS_HEADERS, "Cache-Control": "no-store" },
    });
  } catch (error) {
    logger.error("closet_item_insights.failed", {
      category: error instanceof AppError ? error.category : "server",
    });
    return errorResponse(
      error instanceof AppError ? error : serverError("Couldn't calculate item insights."),
      requestId,
      CORS_HEADERS,
    );
  }
}
