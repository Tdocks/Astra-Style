// ============================================================================
// _shared/scoring/closetItemMapper.ts
// ============================================================================
// `closet_items` row -> `ScorableItem` (types.ts). The mapping boundary
// `types.ts`'s header describes: every §2 formula reads a `ScorableItem`, so
// a schema drift shows up here once instead of at eight call sites.
//
// Shared under `_shared/scoring/` rather than owned by `outfits/` because
// `/outfits/generate`, `/outfits/rank` and (per `leastRecentlyWorn.ts`'s own
// header) `/products/evaluate` all need the same row -> `ScorableItem`
// mapping, and putting it in one function's directory would make the others
// reach across a deploy boundary (ADR 0013) to use it.
//
// ─────────────────────────────────────────────────────────────────────────────
// TWO MORE PLACES THE SHIPPED SCHEMA DISAGREES WITH WHAT A "CLEAN" MAPPING
// WOULD ASSUME, ON TOP OF THE FOUR `types.ts` ALREADY RECORDS.
//
// 5. `pattern` IS FREE TEXT WRITTEN BY A DIFFERENT VOCABULARY THAN THE ONE
//    `ScorableItem.pattern` EXPECTS. `closet/mapper.ts`'s `PATTERNS` table
//    collapses the vision provider's `herringbone` AND `texture-only` into
//    one stored word, `"textured"` — which is not a member of this file's
//    `Pattern` union at all. A row with `pattern = "textured"` could mean
//    either "penalise this against another pattern" (herringbone) or
//    "never penalise this" (texture-only), and picking one would be a guess
//    presented as a reading. So only an EXACT match to the six words §1.5
//    actually defines is accepted; `"textured"`, `"other"`, and anything
//    else map to `null` — which `color.ts`'s `patternPenalty` already treats
//    as "not patterned enough to judge", the same honest answer.
//
// 6. `secondary_colors` IS ASSUMED TO BE A JSON ARRAY OF COLOUR WORDS, THE
//    SAME VOCABULARY AS `primary_color`, BECAUSE NOTHING HAS WRITTEN A FINAL
//    ROW YET TO CONFIRM IT. No `closet` endpoint persists an analysed item
//    to `closet_items` today (`closet/handler.ts` only produces the review
//    DTO `ClosetItemAnalysisResultDTO`); the save step is unbuilt. The
//    column comment says only "jsonb"; §9's field list and
//    `docs/04-data-model.md` both describe it as a colour-word array with no
//    further shape. Reading it through `resolveColorName` — the same
//    function `primary_color` goes through — is the same assumption
//    `docs/04-data-model.md` line 373 makes ("`primary_color`/
//    `secondary_colors` (free text/jsonb)"). If the eventual save endpoint
//    writes a different shape (e.g. `{value, confidence}` suggestion
//    objects, which is what the IN-PROGRESS analysis DTO uses), this
//    function's array-of-strings parse simply finds nothing to resolve
//    per entry and drops it — see `asColorWordArray` below — rather than
//    throwing, so a shape mismatch degrades silently to "no secondary
//    colours read" instead of crashing outfit generation.
// ─────────────────────────────────────────────────────────────────────────────
// ============================================================================

import { resolveColorName } from "./colorVocabulary.ts";
import {
  type AvailabilityState,
  type ClothingCategory,
  type Fit,
  type LaundryState,
  type Pattern,
  roleFor,
  type ScorableItem,
  type Season,
} from "./types.ts";

/**
 * The `closet_items` columns this mapper reads. A strict subset — chosen to
 * match exactly what `ScorableItem` needs — not the full row, so a caller's
 * `select()` list and this type can be kept in lockstep by eye.
 */
export interface ClosetItemMapperRow {
  readonly id: string;
  readonly category: string;
  readonly primary_color: string | null;
  readonly secondary_colors: unknown;
  readonly pattern: string | null;
  readonly material: unknown;
  readonly fit: string | null;
  readonly seasonality: unknown;
  readonly formality_score: number | null;
  readonly warmth_score: number | null;
  readonly water_resistance_score: number | null;
  readonly laundry_state: string;
  readonly availability_state: string;
  /**
   * Optional because some callers (product-candidate projections, older
   * fixtures) have no wear history to give. The mapper treats missing the
   * same as null: never worn.
   */
  readonly last_worn_at?: string | null;
}

const KNOWN_PATTERNS: ReadonlySet<string> = new Set<Pattern>([
  "solid",
  "stripe",
  "check",
  "herringbone",
  "print",
  "texture-only",
]);

const KNOWN_FITS: ReadonlySet<string> = new Set<Fit>([
  "slim",
  "tailored",
  "regular",
  "relaxed",
  "oversized",
]);

const KNOWN_SEASONS: ReadonlySet<string> = new Set<Season>([
  "spring",
  "summer",
  "fall",
  "winter",
]);

/** Note 6 above: an array of colour words, same vocabulary as `primary_color`. */
function asColorWordArray(value: unknown): readonly string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is string => typeof entry === "string");
}

/**
 * `material jsonb` per the migration comment: `[{"fiber": "cotton",
 * "percentage": 100}, ...]`. `silhouette.ts`'s `hasStretch` only ever
 * substring-matches the fiber name, so that is the only field extracted.
 * A bare string entry is accepted too — defensive against a future writer
 * that stores fiber names directly rather than as objects — since either
 * shape answers the same question ("does 'stretch' appear anywhere here?")
 * and guessing between them costs nothing.
 */
function asMaterialFiberArray(value: unknown): readonly string[] {
  if (!Array.isArray(value)) return [];
  const fibers: string[] = [];
  for (const entry of value) {
    if (typeof entry === "string") {
      fibers.push(entry.toLowerCase());
    } else if (
      typeof entry === "object" && entry !== null && "fiber" in entry &&
      typeof (entry as Record<string, unknown>)["fiber"] === "string"
    ) {
      fibers.push(((entry as Record<string, unknown>)["fiber"] as string).toLowerCase());
    }
  }
  return fibers;
}

function asSeasonArray(value: unknown): readonly Season[] {
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is Season =>
    typeof entry === "string" && KNOWN_SEASONS.has(entry)
  );
}

/** Null / missing / unparseable all mean "never worn", never an Invalid Date. */
function parseLastWornAt(value: string | null | undefined): Date | null {
  if (value == null || value === "") return null;
  const ms = Date.parse(value);
  return Number.isNaN(ms) ? null : new Date(ms);
}

/** Empty / whitespace-only colour words are absent, not a blank name in copy. */
function parseColorName(value: string | null): string | null {
  if (value == null) return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

/**
 * Maps one `closet_items` row to a `ScorableItem`, or `null` when the row
 * carries no scoring signal at all — `category = 'fragrance'` (see
 * `roleFor`'s header: "a scent cannot clash with a pair of trousers") or a
 * category this build has never heard of. Filtering happens here rather
 * than forcing every caller to re-derive it from `roleFor`.
 */
export function mapClosetItemRowToScorableItem(row: ClosetItemMapperRow): ScorableItem | null {
  const role = roleFor(row.category as ClothingCategory);
  if (role === null) return null;

  const primary = resolveColorName(row.primary_color);
  const primaryColor = primary?.lch ?? null;
  const isNeutral = primary?.isNeutral ?? false;

  const secondaryColors = asColorWordArray(row.secondary_colors)
    .map((word) => resolveColorName(word)?.lch ?? null)
    .filter((lch): lch is NonNullable<typeof lch> => lch !== null);

  const pattern = row.pattern !== null && KNOWN_PATTERNS.has(row.pattern)
    ? (row.pattern as Pattern)
    : null;

  const fit = row.fit !== null && KNOWN_FITS.has(row.fit) ? (row.fit as Fit) : null;

  return {
    id: row.id,
    category: row.category as ClothingCategory,
    role,
    primaryColor,
    isNeutral,
    secondaryColors,
    pattern,
    // No `pattern_scale` column exists — `types.ts` note 3. Always null.
    patternScale: null,
    materials: asMaterialFiberArray(row.material),
    formalityScore: row.formality_score,
    fit,
    seasonality: asSeasonArray(row.seasonality),
    warmthScore: row.warmth_score,
    waterResistanceScore: row.water_resistance_score,
    // `laundry_state`/`availability_state` are real Postgres enums (see
    // `20260728100100_core_enums.sql`), so every value Supabase returns is
    // already one of these unions' members — unlike `pattern`/`fit` above,
    // which are free text and genuinely need validating.
    laundryState: row.laundry_state as LaundryState,
    availabilityState: row.availability_state as AvailabilityState,
    lastWornAt: parseLastWornAt(row.last_worn_at),
    colorName: parseColorName(row.primary_color),
  };
}
