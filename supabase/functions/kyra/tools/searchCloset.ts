// ============================================================================
// kyra/tools/searchCloset.ts
// ============================================================================
// The `search_closet` tool (P5-KYRA-04, docs/06 §3.1). Read-only. The
// repository behind it is RLS-scoped (built in index.ts from the caller's
// own JWT), so "the user's closet" is enforced by Postgres, not by trust.
//
// `query_text` is specified as an embedded semantic query; no
// EmbeddingProvider exists in this codebase and `closet_items.embedding` is
// never written (see contextPacket.ts's header for the full diagnosis), so
// the semantic leg is a keyword match against the columns a request word
// could actually name — category, subcategory, brand, color. That is a
// weaker retriever and it is labeled as such here rather than dressed up;
// the structured filters (category/color/formality/fit/availability) are
// implemented exactly as specified and do the bulk of the work for the
// acceptance case ("blue tops" -> category=top AND color≈blue).
//
// Color matching is "≈", not "=": "blue" must find a navy polo. Exact and
// substring matches are tried first; failing those, both words are resolved
// through the shared colour vocabulary (`_shared/scoring/colorVocabulary.ts`)
// and matched on hue proximity — a measured comparison in LCh space, not a
// guess. Near-zero-chroma colours are excluded from hue matching (grey
// carries a residual hue angle that means nothing perceptually; "blue" must
// not match "grey" through it) — see `HUE_MEANINGFUL_CHROMA` on why the
// vocabulary's `isNeutral` flag is the wrong gate for this.
// ============================================================================

import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";
import { resolveColorName } from "../../_shared/scoring/colorVocabulary.ts";

/** The compact wire shape docs/06 §3.1 returns per item. */
export interface ClosetItemCompact {
  readonly id: string;
  readonly category: string;
  readonly subcategory: string | null;
  readonly primary_color: string | null;
  readonly formality_score: number | null;
  readonly fit: string | null;
  readonly availability_state: string;
  readonly wear_count: number;
  readonly last_worn_at: string | null;
}

/** A closet row as this tool reads it (superset of the compact shape). */
export interface SearchClosetRow extends ClosetItemCompact {
  readonly brand: string | null;
  readonly laundry_state: string;
}

export interface SearchClosetDeps {
  /**
   * Every non-archived closet row for the caller. Filtering happens in this
   * module rather than in SQL so the color-≈ and keyword logic is testable
   * without a database and identical between deploys; closets are bounded
   * (free tier 30 items, spec §16) so the transfer cost is small.
   */
  listClosetItems(): Promise<SearchClosetRow[]>;
}

export interface SearchClosetArgs {
  readonly queryText?: string;
  readonly category: string[];
  readonly color: string[];
  readonly formalityMin?: number;
  readonly formalityMax?: number;
  readonly fit: string[];
  readonly availabilityOnly: boolean;
  readonly limit: number;
}

const CATEGORIES = ["top", "bottom", "outerwear", "shoes", "accessory", "watch", "fragrance", "dress", "skirt"];
const FITS = ["slim", "tailored", "regular", "relaxed", "oversized"];
const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 60;

export const searchClosetDefinition: StylistToolDefinition = {
  name: "search_closet",
  description:
    "Search the user's closet by category, color, formality range, fit, availability, or " +
    "free-text query. Read-only.",
  parametersSchema: {
    type: "object",
    properties: {
      query_text: {
        type: "string",
        description: "Free-text query matched against item attributes. Optional.",
      },
      category: { type: "array", items: { type: "string", enum: CATEGORIES } },
      color: { type: "array", items: { type: "string" } },
      formality_min: { type: "integer", minimum: 0, maximum: 100 },
      formality_max: { type: "integer", minimum: 0, maximum: 100 },
      fit: { type: "array", items: { type: "string", enum: FITS } },
      availability_only: {
        type: "boolean",
        default: true,
        description: "If true, excludes items in laundry or marked unavailable.",
      },
      limit: { type: "integer", default: DEFAULT_LIMIT, maximum: MAX_LIMIT },
    },
    required: [],
  },
};

function asStringArrayArg(value: unknown, allowed?: readonly string[]): string[] {
  if (!Array.isArray(value)) return [];
  const strings = value.filter((entry): entry is string => typeof entry === "string");
  return allowed === undefined ? strings : strings.filter((entry) => allowed.includes(entry));
}

function asBoundedInt(value: unknown, min: number, max: number): number | undefined {
  if (typeof value !== "number" || !Number.isInteger(value)) return undefined;
  return Math.min(max, Math.max(min, value));
}

/** Model-supplied arguments are untrusted input; parse defensively, never throw. */
export function parseSearchClosetArgs(raw: Record<string, unknown>): SearchClosetArgs {
  const args: {
    queryText?: string;
    category: string[];
    color: string[];
    formalityMin?: number;
    formalityMax?: number;
    fit: string[];
    availabilityOnly: boolean;
    limit: number;
  } = {
    category: asStringArrayArg(raw["category"], CATEGORIES),
    color: asStringArrayArg(raw["color"]),
    fit: asStringArrayArg(raw["fit"], FITS),
    availabilityOnly: raw["availability_only"] !== false,
    limit: asBoundedInt(raw["limit"], 1, MAX_LIMIT) ?? DEFAULT_LIMIT,
  };
  if (typeof raw["query_text"] === "string" && raw["query_text"].trim().length > 0) {
    args.queryText = raw["query_text"].trim();
  }
  const min = asBoundedInt(raw["formality_min"], 0, 100);
  const max = asBoundedInt(raw["formality_max"], 0, 100);
  if (min !== undefined) args.formalityMin = min;
  if (max !== undefined) args.formalityMax = max;
  return args;
}

const HUE_MATCH_DEGREES = 45;
// Below this chroma a hue angle is numerically present but perceptually
// meaningless — grey resolves to h≈158 with c≈0.00001, and "blue ≈ grey"
// via that residual hue would be a false reading. NOT the vocabulary's
// `isNeutral` flag: that encodes the MENSWEAR pairing concept (navy and
// olive are "neutrals" you can pair with anything), and a search for "blue
// tops" absolutely should find a navy polo.
const HUE_MEANINGFUL_CHROMA = 8;

function circularHueDistance(a: number, b: number): number {
  const diff = Math.abs(a - b) % 360;
  return diff > 180 ? 360 - diff : diff;
}

/** "blue" ≈ "navy": exact, substring, or same hue family in LCh. */
export function colorMatches(requested: string, itemColor: string | null): boolean {
  if (itemColor === null) return false;
  const wanted = requested.trim().toLowerCase();
  const actual = itemColor.trim().toLowerCase();
  if (wanted.length === 0 || actual.length === 0) return false;
  if (actual === wanted || actual.includes(wanted) || wanted.includes(actual)) return true;
  const wantedResolved = resolveColorName(wanted);
  const actualResolved = resolveColorName(actual);
  if (wantedResolved === null || actualResolved === null) return false;
  if (
    wantedResolved.lch.c < HUE_MEANINGFUL_CHROMA || actualResolved.lch.c < HUE_MEANINGFUL_CHROMA
  ) {
    return false;
  }
  return circularHueDistance(wantedResolved.lch.h, actualResolved.lch.h) <= HUE_MATCH_DEGREES;
}

const WEARABLE_LAUNDRY_STATES = new Set(["clean", "worn_once"]);

function matchesQueryText(row: SearchClosetRow, queryWords: readonly string[]): boolean {
  if (queryWords.length === 0) return true;
  const haystack = [row.category, row.subcategory, row.brand, row.primary_color, row.fit]
    .filter((field): field is string => field !== null)
    .join(" ")
    .toLowerCase();
  return queryWords.some((word) =>
    haystack.includes(word) || colorMatches(word, row.primary_color)
  );
}

function toCompact(row: SearchClosetRow): ClosetItemCompact {
  return {
    id: row.id,
    category: row.category,
    subcategory: row.subcategory,
    primary_color: row.primary_color,
    formality_score: row.formality_score,
    fit: row.fit,
    availability_state: row.availability_state,
    wear_count: row.wear_count,
    last_worn_at: row.last_worn_at === null ? null : row.last_worn_at.slice(0, 10),
  };
}

/**
 * Executes the search. Domain outcomes — including §3.1's `EMPTY_CLOSET` —
 * come back as structured results the model can relay, never thrown: a
 * closet with nothing matching is an answer, not a failure.
 */
export async function executeSearchCloset(
  args: SearchClosetArgs,
  deps: SearchClosetDeps,
): Promise<Record<string, unknown>> {
  const rows = await deps.listClosetItems();
  if (rows.length === 0) {
    return { items: [], total_matched: 0, error: "EMPTY_CLOSET" };
  }

  const queryWords = (args.queryText ?? "")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((word) => word.length >= 3);

  const matched = rows.filter((row) => {
    if (args.category.length > 0 && !args.category.includes(row.category)) return false;
    if (
      args.color.length > 0 && !args.color.some((color) => colorMatches(color, row.primary_color))
    ) return false;
    if (args.formalityMin !== undefined) {
      if (row.formality_score === null || row.formality_score < args.formalityMin) return false;
    }
    if (args.formalityMax !== undefined) {
      if (row.formality_score === null || row.formality_score > args.formalityMax) return false;
    }
    if (args.fit.length > 0 && (row.fit === null || !args.fit.includes(row.fit))) return false;
    if (args.availabilityOnly) {
      if (row.availability_state !== "available") return false;
      if (!WEARABLE_LAUNDRY_STATES.has(row.laundry_state)) return false;
    }
    return matchesQueryText(row, queryWords);
  });

  return {
    items: matched.slice(0, args.limit).map(toCompact),
    total_matched: matched.length,
  };
}
