import type { SupabaseClient } from "@supabase/supabase-js";
import { CORS_HEADERS, handleCorsPreflight } from "../_shared/cors.ts";
import {
  AppError,
  badRequest,
  errorResponse,
  jsonResponse,
  methodNotAllowed,
  notFound,
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
import type { ComponentWeights } from "../_shared/scoring/compatibility.ts";
import { asHypotheticalOwnership } from "../_shared/scoring/unlockCountCache.ts";
import { computeUnlockCount } from "../_shared/scoring/unlockCount.ts";
import type { ScorableItem, ScoringContext } from "../_shared/scoring/types.ts";

const ITEM_COLUMNS = [
  "id",
  "user_id",
  "category",
  "primary_color",
  "secondary_colors",
  "pattern",
  "material",
  "fit",
  "seasonality",
  "formality_score",
  "warmth_score",
  "water_resistance_score",
  "laundry_state",
  "availability_state",
  "last_worn_at",
  "archived_at",
].join(",");

interface ClosetUnlockRow extends ClosetItemMapperRow {
  readonly user_id: string;
  readonly archived_at: string | null;
}

export interface ScanUnlockCountDTO {
  readonly status: "available" | "unmeasurable";
  readonly outfits_unlocked: number | null;
}

export interface ScanUnlockCountDependencies {
  readonly authClient: AuthClient;
  readonly supabase: SupabaseClient;
  readonly rateLimiter: RateLimiter;
  readonly now: () => Date;
  readonly readWeights: () => Promise<ComponentWeights>;
  readonly readOwnedScoringContext: (
    ownerID: string,
    itemIDs: ReadonlySet<string>,
  ) => Promise<Pick<ScoringContext, "preferences" | "coWear" | "coWearByRole">>;
}

async function fetchOwnedActiveItems(
  supabase: SupabaseClient,
  ownerID: string,
): Promise<ClosetUnlockRow[]> {
  const items: ClosetUnlockRow[] = [];
  const pageSize = 500;
  for (let offset = 0; offset < 50_000; offset += pageSize) {
    const { data, error } = await supabase.from("closet_items")
      .select(ITEM_COLUMNS)
      .eq("user_id", ownerID)
      .is("archived_at", null)
      .order("id", { ascending: true })
      .range(offset, offset + pageSize - 1);
    if (error) throw serverError("Couldn't load the saved item for its outfit count.");
    const page = (data ?? []) as unknown as ClosetUnlockRow[];
    items.push(...page);
    if (page.length < pageSize) return items;
  }
  throw serverError("Your closet is too large to calculate this outfit count right now.");
}

function scorableItems(rows: readonly ClosetUnlockRow[]): ScorableItem[] {
  return rows.flatMap((row) => {
    const item = mapClosetItemRowToScorableItem(row);
    return item ? [item] : [];
  });
}

/** Returns a score for one server-owned saved item; no client garment data is accepted. */
export async function handleScanUnlockCount(
  req: Request,
  itemID: string,
  deps: ScanUnlockCountDependencies,
): Promise<Response> {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  const requestID = resolveRequestId(req);
  const logger = createLogger(requestID);
  const startedAt = deps.now().getTime();

  try {
    if (req.method !== "GET") throw methodNotAllowed("This outfit count route only accepts GET.");
    const ownerID = await authenticateRequest(req, deps.authClient);
    const limit = deps.rateLimiter.check(ownerID, deps.now().getTime());
    if (!limit.allowed) {
      throw rateLimited("Please wait a moment before refreshing this outfit count.");
    }
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(itemID)) {
      throw badRequest("Choose a valid closet item.");
    }

    const rows = await fetchOwnedActiveItems(deps.supabase, ownerID);
    const targetRow = rows.find((row) => row.id.toLowerCase() === itemID.toLowerCase());
    if (!targetRow || targetRow.user_id !== ownerID) {
      // Same response for absent, archived, and peer-owned rows.
      throw notFound("That saved closet item is unavailable.");
    }
    const candidate = mapClosetItemRowToScorableItem(targetRow);
    if (candidate === null) {
      const response: ScanUnlockCountDTO = { status: "unmeasurable", outfits_unlocked: null };
      logger.info("closet_scan_unlock_count.unmeasurable", {
        duration_ms: deps.now().getTime() - startedAt,
      });
      return jsonResponse(response, {
        requestId: requestID,
        extraHeaders: { ...CORS_HEADERS, "Cache-Control": "no-store" },
      });
    }

    const itemIDs = new Set(rows.map((row) => row.id));
    const [profile, weights, ownedContext] = await Promise.all([
      deps.supabase.from("profiles").select("wardrobe_graph").eq("id", ownerID).maybeSingle(),
      deps.readWeights(),
      deps.readOwnedScoringContext(ownerID, itemIDs),
    ]);
    if (profile.error) throw serverError("Couldn't load your styling preferences.");

    // The candidate is already present in the saved closet. It must be
    // removed from the pool because computeUnlockCount requires a hypothetical
    // candidate separate from owned items; leaving it in makes it its own
    // equivalent substitute and incorrectly reports zero.
    const pool = scorableItems(rows)
      .filter((item) => item.id !== candidate.id)
      .map(asHypotheticalOwnership);
    const wardrobeGraph =
      (profile.data as { wardrobe_graph?: unknown } | null)?.wardrobe_graph === "womenswear"
        ? "womenswear"
        : "menswear_3_role";
    const result = computeUnlockCount(
      asHypotheticalOwnership(candidate),
      pool,
      { scoringContext: { ...ownedContext, wardrobeGraph }, weights },
    );
    const response: ScanUnlockCountDTO = {
      status: "available",
      outfits_unlocked: result.unlockCount,
    };
    logger.info("closet_scan_unlock_count.completed", {
      duration_ms: deps.now().getTime() - startedAt,
      closet_item_count: rows.length,
      combinations_scored: result.combinationsScored,
    });
    return jsonResponse(response, {
      requestId: requestID,
      extraHeaders: { ...CORS_HEADERS, "Cache-Control": "no-store" },
    });
  } catch (error) {
    logger.error("closet_scan_unlock_count.failed", {
      category: error instanceof AppError ? error.category : "server",
      duration_ms: deps.now().getTime() - startedAt,
    });
    return errorResponse(
      error instanceof AppError ? error : serverError("Couldn't calculate that outfit count."),
      requestID,
      CORS_HEADERS,
    );
  }
}
