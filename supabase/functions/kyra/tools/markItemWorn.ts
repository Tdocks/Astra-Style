// ============================================================================
// kyra/tools/markItemWorn.ts
// ============================================================================
// The `mark_item_worn` tool (P5-KYRA-10, docs/06 §3.10). Mutating, and the
// one tool whose confirmation gate is enforced by the SERVER, not by prompt
// text: §3.2's trigger rule says wear may be recorded only when the user's
// own triggering message states or confirms it. A model that decided to call
// this tool speculatively must be stopped here, because "never silently mark
// an item worn" is a product guarantee, not a hope about model behavior. The
// executor therefore runs a deterministic wear-evidence check over the
// triggering user message (verbs of wearing, or an affirmative reply to a
// question Kyra asked last turn) and refuses with CONFIRMATION_REQUIRED when
// none is found. The check is deliberately coarse — a regex cannot read
// intent — but it fails CLOSED: the cost of a false refusal is Kyra asking
// "did you wear it?", while the cost of a false accept is corrupted wear
// history and cost-per-wear stats.
//
// COUNTING HAPPENS IN THE DATABASE, NOT HERE. `outfit_wears` insert fires
// `bump_closet_item_wear_stats()`, which increments `wear_count` and
// advances `last_worn_at` for every closet item in the outfit. This module
// must NOT also update those columns — that is the double-count P5-KYRA-10
// warns about. `updated_wear_counts` in the response is a RE-READ of the
// rows after insert, reporting what the trigger did.
//
// `outfit_wears.outfit_id` is NOT NULL: a wear event is always of an
// outfit. "I wore the navy blazer" with no outfit id therefore persists a
// minimal real outfit (source `user_created` — the user asserting what they
// wore is user-authored fact, not a Kyra suggestion) wrapping exactly the
// named items, then records the wear against it. Same-day duplicates are
// idempotent per §3.10: the existing wear row is returned and nothing is
// double-counted (the trigger only fires on genuine insert).
// ============================================================================

import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";
import { isUUID } from "../../_shared/validation.ts";

export interface MarkItemWornDeps {
  /** The user message that triggered this turn — the only confirmation source. */
  readonly triggeringUserText: string;
  readonly now: () => Date;
  /** Returns the subset of `ids` the caller actually owns (RLS-scoped). */
  listOwnedItemIds(ids: readonly string[]): Promise<string[]>;
  /** Verifies the outfit exists for this caller; null when it does not. */
  getOutfitItemIds(outfitId: string): Promise<string[] | null>;
  /** An ad-hoc wrapper outfit for item-only wear events. Returns its id. */
  insertWornOutfit(itemIds: readonly string[], wornDate: string): Promise<string>;
  /** An existing wear of this outfit on this date, for idempotency. */
  findWearOnDate(outfitId: string, wornDate: string): Promise<{ id: string } | null>;
  insertWear(record: {
    readonly outfitId: string;
    readonly wornAtIso: string;
    readonly occasion: string | null;
  }): Promise<string>;
  /** Post-insert wear counts, read back so the trigger's work is reported. */
  readWearCounts(itemIds: readonly string[]): Promise<ReadonlyMap<string, number>>;
}

export const markItemWornDefinition: StylistToolDefinition = {
  name: "mark_item_worn",
  description:
    "Record that the user wore specific items (or an outfit) on a date. Writes real wear " +
    "history. Only call when the triggering user message contains an explicit, direct " +
    "statement or confirmation that the item was worn — never speculatively.",
  parametersSchema: {
    type: "object",
    properties: {
      item_ids: { type: "array", items: { type: "string", format: "uuid" } },
      outfit_id: { type: "string", format: "uuid", nullable: true },
      worn_at: { type: "string", format: "date", default: "today" },
      occasion: { type: "string", nullable: true },
    },
    required: ["item_ids"],
  },
};

/**
 * §3.2's "execute immediately" evidence: the message states wear in its own
 * words, or affirms a question. Exported for direct testing — this predicate
 * IS the confirmation gate.
 */
export function messageContainsWearEvidence(text: string): boolean {
  const normalized = text.toLowerCase();
  if (/\b(wore|i've worn|i have worn|was wearing|ended up wearing|put on)\b/.test(normalized)) {
    return true;
  }
  if (/\bmark (it|that|this|them|those)?\s*(as\s+)?worn\b/.test(normalized)) {
    return true;
  }
  // Affirmative replies to a wear question Kyra asked the previous turn.
  return /^(yes|yeah|yep|yup|correct|i did|sure did|that's right)\b/.test(normalized.trim());
}

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function resolveWornDate(raw: unknown, now: Date): string | null {
  if (raw === undefined || raw === null || raw === "today") {
    return now.toISOString().slice(0, 10);
  }
  if (typeof raw !== "string" || !DATE_PATTERN.test(raw)) return null;
  const parsed = new Date(`${raw}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== raw) return null;
  // The future has not been worn.
  if (parsed.getTime() > now.getTime()) return null;
  return raw;
}

export async function executeMarkItemWorn(
  raw: Record<string, unknown>,
  deps: MarkItemWornDeps,
): Promise<Record<string, unknown>> {
  if (!messageContainsWearEvidence(deps.triggeringUserText)) {
    return {
      error: "CONFIRMATION_REQUIRED",
      detail: "The user's message does not explicitly state or confirm that this was worn. " +
        "Ask a plain yes/no question and call this tool again only after an affirmative reply. " +
        "Nothing was recorded.",
    };
  }

  const itemIds = Array.isArray(raw["item_ids"]) ? raw["item_ids"].filter(isUUID) : [];
  const outfitId = isUUID(raw["outfit_id"]) ? raw["outfit_id"] : null;
  if (itemIds.length === 0 && outfitId === null) {
    return { error: "ITEM_NOT_FOUND", detail: "Neither item_ids nor outfit_id named anything." };
  }

  const now = deps.now();
  const wornDate = resolveWornDate(raw["worn_at"], now);
  if (wornDate === null) {
    return {
      error: "INVALID_DATE",
      detail: "worn_at must be 'today' or a real past/current date in YYYY-MM-DD form.",
    };
  }
  const occasion = typeof raw["occasion"] === "string" && raw["occasion"].trim().length > 0
    ? raw["occasion"].trim().slice(0, 200)
    : null;

  // Resolve the outfit whose wear this records.
  let targetOutfitId: string;
  let affectedItemIds: string[];
  if (outfitId !== null) {
    const outfitItems = await deps.getOutfitItemIds(outfitId);
    if (outfitItems === null) {
      return { error: "ITEM_NOT_FOUND", detail: "No such outfit for this user." };
    }
    targetOutfitId = outfitId;
    affectedItemIds = outfitItems;
  } else {
    const owned = await deps.listOwnedItemIds(itemIds);
    const missing = itemIds.filter((id) => !owned.includes(id));
    if (owned.length === 0) {
      return { error: "ITEM_NOT_FOUND", missing_item_ids: missing };
    }
    if (missing.length > 0) {
      // Recording a wear of a DIFFERENT set of items than the user named
      // would be a confounded write; refuse rather than shrink the claim.
      return { error: "ITEM_NOT_FOUND", missing_item_ids: missing };
    }
    targetOutfitId = await deps.insertWornOutfit(owned, wornDate);
    affectedItemIds = owned;
  }

  // §3.10 idempotency: same outfit, same day -> return the existing record;
  // the wear-stats trigger never re-fires because nothing is inserted.
  const existing = await deps.findWearOnDate(targetOutfitId, wornDate);
  if (existing !== null) {
    const counts = await deps.readWearCounts(affectedItemIds);
    return {
      recorded: true,
      duplicate_of: existing.id,
      error: "DUPLICATE_ENTRY_SAME_DAY",
      outfit_id: targetOutfitId,
      updated_wear_counts: Object.fromEntries(counts),
    };
  }

  // Midday UTC keeps the date stable across timezone renderings of a
  // date-only claim; the client did not tell us a time of day.
  const wearId = await deps.insertWear({
    outfitId: targetOutfitId,
    wornAtIso: `${wornDate}T12:00:00Z`,
    occasion,
  });

  const counts = await deps.readWearCounts(affectedItemIds);
  return {
    recorded: true,
    wear_id: wearId,
    outfit_id: targetOutfitId,
    worn_at: wornDate,
    updated_wear_counts: Object.fromEntries(counts),
  };
}
