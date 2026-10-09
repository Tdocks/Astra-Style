// ============================================================================
// kyra/tools/createOutfit.ts
// ============================================================================
// The `create_outfit` tool (P5-KYRA-06, docs/06 §3.3). Mutating: persists a
// REAL `outfits` row plus its `outfit_items`, the same shape `daily-brief`
// writes (`persistOutfits` there is the precedent) — because
// `outfit_wears.outfit_id` is a NOT NULL foreign key, an outfit that was
// only ever an id in a chat response could never later be marked worn. The
// id this tool returns is durable and everything downstream can hang off it.
//
// "DRAFT" IS A DOCS CONCEPT THE SCHEMA DOES NOT HAVE. §3.3 says drafts are
// invisible in saved-outfit stats until the user saves them, and its return
// shape names `source: "kyra_draft"` — but the `outfit_source` Postgres enum
// is exactly {ai_generated, user_created, kyra_suggested, studio_derived},
// with no draft member and no `is_draft` column (P5-KYRA-01's migration
// shipped without one). Inserting "kyra_draft" would simply fail. So rows
// are written with `source = 'kyra_suggested'` — the enum's own name for
// "came out of chat §6.20" — and the response reports that honestly instead
// of echoing a value the database rejected. The draft/saved distinction, if
// the product still wants it, needs a schema change recorded in the report,
// not a fake enum value.
//
// The §10 compatibility score is computed by the same shared engine as
// everywhere else and CACHED on the row (`outfits.compatibility_score`'s own
// column comment describes this cache), then returned.
// ============================================================================

import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";
import {
  type ClosetItemMapperRow,
  mapClosetItemRowToScorableItem,
} from "../../_shared/scoring/closetItemMapper.ts";
import { scoreOutfit } from "../../_shared/scoring/compatibility.ts";
import type { ScorableItem } from "../../_shared/scoring/types.ts";
import {
  parseWardrobeGraph,
  requiredRoleSetsForGeneration,
  type WardrobeGraphId,
} from "../../_shared/scoring/wardrobeGraph.ts";
import { isUUID } from "../../_shared/validation.ts";
import {
  type AtomicOutfitCommit,
  createOutfitQuotaIdentity,
  type OutfitGenerationQuotaOperations,
  replayResultFromQuota,
  type ReservedBuilderOutfitQuota,
} from "../outfitQuota.ts";

export interface NewOutfitRecord {
  readonly name: string | null;
  readonly occasionTags: string[];
  readonly compatibilityScore: number;
  readonly source: "kyra_suggested";
  readonly description: string | null;
  readonly items: ReadonlyArray<{
    readonly closetItemId: string | null;
    readonly productCandidateId: string | null;
    readonly role: string;
    readonly sortOrder: number;
  }>;
}

export interface CreateOutfitDeps {
  listItemsByIds(ids: readonly string[]): Promise<ClosetItemMapperRow[]>;
  listProductCandidateCategories?(
    ids: readonly string[],
  ): Promise<ReadonlyMap<string, string | null>>;
  /** Inserts the outfit and its items; returns the new outfit id. */
  insertOutfit(record: NewOutfitRecord): Promise<string>;
  /** Atomic persistence+quota transaction, supplied by the live store. */
  commitOutfitGeneration?(input: AtomicOutfitCommit): Promise<Record<string, unknown>>;
  readonly generationQuota?: OutfitGenerationQuotaOperations;
  readonly quotaUserID?: string;
  readonly outerRequestID?: string;
  readonly toolCallID?: string;
  readonly now?: () => Date;
  readonly reservedBuilderQuota?: ReservedBuilderOutfitQuota;
  readWardrobeGraph(): Promise<WardrobeGraphId>;
  /** IDs fixed by the authenticated builder context, never model supplied. */
  readonly lockedItemIDs?: readonly string[];
  /** Builder completion cannot introduce products the user does not own. */
  readonly allowProductCandidates?: boolean;
  readonly requireReason?: boolean;
}

export interface CreateOutfitArgs {
  readonly itemIds: string[];
  readonly productCandidateIds: string[];
  readonly name?: string;
  readonly occasionTags: string[];
  readonly reason?: string;
}

export const createOutfitDefinition: StylistToolDefinition = {
  name: "create_outfit",
  description:
    "Construct and persist a new outfit from closet items and/or product candidates (for " +
    "'complete the look' cases). The returned outfit_id is real and can back an outfit card.",
  parametersSchema: {
    type: "object",
    properties: {
      item_ids: { type: "array", items: { type: "string", format: "uuid" } },
      product_candidate_ids: {
        type: "array",
        items: { type: "string", format: "uuid" },
        description: "Missing/not-yet-owned items included in the outfit.",
      },
      name: { type: "string", nullable: true },
      occasion_tags: { type: "array", items: { type: "string" } },
      reason: {
        type: "string",
        description: "Short stylist rationale, surfaced on the outfit card.",
      },
    },
    required: ["item_ids"],
  },
};

export function parseCreateOutfitArgs(raw: Record<string, unknown>): CreateOutfitArgs {
  const itemIds = Array.isArray(raw["item_ids"]) ? raw["item_ids"].filter(isUUID) : [];
  const productIds = Array.isArray(raw["product_candidate_ids"])
    ? raw["product_candidate_ids"].filter(isUUID)
    : [];
  const occasionTags = Array.isArray(raw["occasion_tags"])
    ? raw["occasion_tags"].filter((entry): entry is string => typeof entry === "string")
    : [];
  const args: {
    itemIds: string[];
    productCandidateIds: string[];
    name?: string;
    occasionTags: string[];
    reason?: string;
  } = { itemIds, productCandidateIds: productIds, occasionTags };
  if (typeof raw["name"] === "string" && raw["name"].trim().length > 0) {
    args.name = raw["name"].trim().slice(0, 120);
  }
  if (typeof raw["reason"] === "string" && raw["reason"].trim().length > 0) {
    args.reason = raw["reason"].trim().slice(0, 500);
  }
  return args;
}

/**
 * §3.3's MINIMUM_ROLES_NOT_MET: an outfit needs a complete required-role
 * set for the caller's wardrobe graph (ADR 0019). Product-candidate slots
 * count toward missing roles — "complete the look" outfits exist precisely
 * because a role is missing from the closet — but their categories are
 * unknown here, so only the closet side is checked strictly.
 */
function coversMinimumRoles(
  items: readonly ScorableItem[],
  productSlotRoles: readonly string[],
  graph: WardrobeGraphId,
): boolean {
  const roles = new Set([...items.map((item) => item.role), ...productSlotRoles]);
  for (const set of requiredRoleSetsForGeneration(graph)) {
    if (set.every((role) => roles.has(role))) return true;
  }
  return false;
}

export async function executeCreateOutfit(
  args: CreateOutfitArgs,
  deps: CreateOutfitDeps,
): Promise<Record<string, unknown>> {
  if (deps.allowProductCandidates === false && args.productCandidateIds.length > 0) {
    return {
      error: "OWNED_ITEMS_ONLY",
      detail: "Builder completion can use owned closet items only.",
    };
  }
  if (deps.requireReason && !args.reason?.trim()) {
    return {
      error: "REASON_REQUIRED",
      detail: "Provide a short styling reason for the completed outfit.",
    };
  }

  const requiredIDs = deps.lockedItemIDs ?? [];
  const requestedIDs = [...new Set([...args.itemIds, ...requiredIDs])];
  if (requestedIDs.length > 12) {
    return { error: "TOO_MANY_ITEMS", detail: "An outfit can contain at most twelve owned items." };
  }
  if (requestedIDs.length === 0) {
    return { error: "ITEM_NOT_FOUND", detail: "item_ids must name at least one closet item." };
  }

  const rows = await deps.listItemsByIds(requestedIDs);
  const rowsById = new Map(rows.map((row) => [row.id, row]));
  const missingIds = requestedIDs.filter((id) => !rowsById.has(id));
  if (missingIds.length > 0) {
    // An id the caller does not own resolves to nothing under RLS —
    // deliberately indistinguishable from one that does not exist.
    return { error: "ITEM_NOT_FOUND", missing_item_ids: missingIds };
  }

  // Locked slots are authoritative. Discard any conflicting model garment
  // for the same role before scoring or persistence; fail closed if the
  // authenticated builder context itself has duplicate locked roles.
  const lockedRoles = new Set<string>();
  for (const id of requiredIDs) {
    const role = rowsById.get(id)!.category;
    if (lockedRoles.has(role)) return { error: "CONFLICTING_LOCKED_ROLES" };
    lockedRoles.add(role);
  }
  const selectedIDs = args.itemIds.filter((id) => {
    return requiredIDs.includes(id) || !lockedRoles.has(rowsById.get(id)!.category);
  });
  const finalIDs = [...new Set([...selectedIDs, ...requiredIDs])];
  if (finalIDs.length + args.productCandidateIds.length > 12) {
    return { error: "TOO_MANY_ITEMS", detail: "An outfit can contain at most twelve owned items." };
  }

  const productCategories =
    args.productCandidateIds.length > 0 && deps.listProductCandidateCategories
      ? await deps.listProductCandidateCategories(args.productCandidateIds)
      : new Map<string, string | null>();
  if (
    deps.listProductCandidateCategories &&
    args.productCandidateIds.some((id) => !productCategories.has(id))
  ) return { error: "PRODUCT_NOT_FOUND" };
  const productRoles = args.productCandidateIds.map((id) =>
    productCategories.get(id) ?? "accessory"
  );

  const scorable: ScorableItem[] = [];
  for (const id of finalIDs) {
    const item = mapClosetItemRowToScorableItem(rowsById.get(id)!);
    if (item !== null) scorable.push(item);
  }
  const wardrobeGraph = parseWardrobeGraph(await deps.readWardrobeGraph());
  if (!coversMinimumRoles(scorable, productRoles, wardrobeGraph)) {
    return { error: "MINIMUM_ROLES_NOT_MET" };
  }

  const score = scoreOutfit(scorable, { wardrobeGraph });
  const items: Array<{
    closetItemId: string | null;
    productCandidateId: string | null;
    role: string;
    sortOrder: number;
  }> = [];
  let sortOrder = 0;
  for (const id of finalIDs) {
    const row = rowsById.get(id)!;
    items.push({
      closetItemId: id,
      productCandidateId: null,
      role: row.category,
      sortOrder: sortOrder++,
    });
  }
  for (const productId of args.productCandidateIds) {
    // `outfit_items.role` is NOT NULL; a product candidate's category is
    // unknowable until Phase 6's catalog exists. "accessory" is the closed
    // enum's least-wrong slot for an unresolved product, and the row's
    // product_candidate_id keeps the real identity.
    items.push({
      closetItemId: null,
      productCandidateId: productId,
      role: productCategories.get(productId) ?? "accessory",
      sortOrder: sortOrder++,
    });
  }

  const record: NewOutfitRecord = {
    name: args.name ?? null,
    occasionTags: args.occasionTags,
    compatibilityScore: score.score,
    source: "kyra_suggested",
    description: args.reason ?? null,
    items,
  };
  const result: Record<string, unknown> = {
    compatibility_score: score.score,
    // See the header: the enum has no "kyra_draft"; this is what was written.
    source: "kyra_suggested",
    reason: args.reason ?? null,
    unmeasured: [...score.degraded],
    item_ids: finalIDs,
  };
  return await persistOutfitWithQuota(args, deps, record, result);
}

async function persistOutfitWithQuota(
  args: CreateOutfitArgs,
  deps: CreateOutfitDeps,
  record: NewOutfitRecord,
  result: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const quota = deps.generationQuota;
  const userID = deps.quotaUserID;
  const outerRequestID = deps.outerRequestID;
  const now = deps.now?.() ?? new Date();
  if (!quota || !userID || !outerRequestID || !deps.commitOutfitGeneration) {
    const outfitId = await deps.insertOutfit(record);
    return { ...result, outfit_id: outfitId, source: "kyra_suggested" };
  }

  let operation = deps.reservedBuilderQuota ?? null;
  if (operation?.used) {
    return {
      error: "OUTFIT_GENERATION_IN_FLIGHT",
      detail: "This builder request already completed an outfit.",
    };
  }
  if (!operation) {
    const identity = await createOutfitQuotaIdentity(outerRequestID, {
      kind: "kyra.create_outfit",
      args,
      locked_item_ids: deps.lockedItemIDs ?? [],
      allow_product_candidates: deps.allowProductCandidates !== false,
      require_reason: deps.requireReason === true,
    }, deps.toolCallID ?? "conversation");
    const premium = await quota.isPremium(userID, now);
    let reservationID: string | null = null;
    let replayResult: Record<string, unknown> | null = null;
    if (!premium) {
      const reservation = await quota.reserve(
        userID,
        identity.requestID,
        identity.fingerprint,
        now,
      );
      replayResult = replayResultFromQuota(reservation.replay_payload);
      if (!replayResult && reservation.in_flight) {
        return { error: "OUTFIT_GENERATION_IN_FLIGHT" };
      }
      if (!replayResult && !reservation.allowed) {
        return {
          error: "OUTFIT_GENERATION_LIMIT_REACHED",
          details: {
            limit: "outfit_generation_daily",
            limit_count: reservation.limitCount,
            remaining: reservation.remaining,
            resets_at: reservation.resetsAt,
          },
        };
      }
      if (!replayResult) {
        if (!reservation.reservation_id) throw new Error("Quota reservation did not return an ID.");
        reservationID = reservation.reservation_id;
      }
    }
    operation = {
      ...identity,
      userID,
      premium,
      reservationID,
      replayResult,
      used: false,
      settled: replayResult !== null,
    };
  }

  operation.used = true;
  if (operation.replayResult) return operation.replayResult;

  try {
    const committed = await deps.commitOutfitGeneration({
      userID,
      requestID: operation.requestID,
      fingerprint: operation.fingerprint,
      reservationID: operation.reservationID,
      record,
      result,
      lockedItemIDs: deps.lockedItemIDs ?? [],
      allowProductCandidates: deps.allowProductCandidates !== false,
      now,
    });
    operation.settled = true;
    return committed;
  } catch (error) {
    if (operation.reservationID) {
      try {
        await quota.finish(userID, operation.reservationID, false, null, now);
      } catch {
        // Preserve the original atomic RPC failure; a committed reservation
        // makes finish(false) a no-op, while a rolled-back write is released.
      }
    }
    throw error;
  }
}
