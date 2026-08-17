// ============================================================================
// products/candidateMapper.ts
// ============================================================================
// Two mapping boundaries, kept in one file because they share the same
// "what does an absent/unknown category mean" policy and would drift if
// written twice:
//
//   1. `ProductExtractionResult` (provider-shaped, `_shared/providers/`) ->
//      the `product_candidates` upsert row + the wire `ProductCandidateDTO`
//      — used by `POST /products/extract`.
//   2. A `product_candidates` row -> `ScorableItem`/`RedundancyItem`
//      (`_shared/scoring/`) — used by `POST /products/evaluate` to feed the
//      candidate into the same compatibility/redundancy engine
//      `closetItemMapper.ts` feeds owned garments into.
//
// WHY `category`/`retailer` GET A DEFAULT HERE BUT `name` NEVER DOES.
//
// `ProductCandidate.retailer: String` and `.category: ClothingCategory` in
// the Swift model are non-optional — a `null` or absent value for either
// makes the client's decode fail outright, which is a worse outcome than a
// flagged, honestly-labelled default. `retailer` defaults to the URL's own
// hostname, which is a true fact about the request (not a guess).
// `category` has no honest "true fact" fallback of the same kind, so it
// defaults to `"top"` — the same choice `mockVisionAnalysis.ts` and
// `closet/mapper.ts`'s `resolveCategory` already make for exactly the same
// reason, recorded there in more detail. Both defaults are always paired
// with a `fields_below_confidence_threshold` entry so nothing downstream
// mistakes the default for a reading. `name`, by contrast, has NO default:
// `mapExtractionToUpsertRow` returns `null` when the provider found none,
// and `products/handler.ts` treats that as extraction failure (P6-SHOP-03's
// "not a partially-populated row" acceptance criterion) rather than writing
// a row titled "Top".
// ============================================================================

import type { ProductExtractionResult } from "../_shared/providers/productExtraction.ts";
import { resolveColorName } from "../_shared/scoring/colorVocabulary.ts";
import { labFromLCh, type RedundancyItem } from "../_shared/scoring/redundancy.ts";
import {
  type ClothingCategory,
  type Fit,
  type Pattern,
  roleFor,
  type ScorableItem,
  type Season,
} from "../_shared/scoring/types.ts";
import type { ProductCandidateDTO } from "./schema.ts";

const KNOWN_CATEGORIES: ReadonlySet<string> = new Set<ClothingCategory>([
  "top",
  "bottom",
  "outerwear",
  "shoes",
  "accessory",
  "watch",
  "fragrance",
]);

/** Same reasoning as `mockVisionAnalysis.ts`'s `resolveCategory` — see this file's header. */
const DEFAULT_CATEGORY: ClothingCategory = "top";
/** Matches `product_candidates.currency`'s declared column default exactly (`20260728100600_commerce.sql`). */
const DEFAULT_CURRENCY = "USD";
const LOW_CONFIDENCE_THRESHOLD = 0.6;

export interface ProductCandidateUpsertRow {
  readonly canonical_url: string;
  readonly retailer: string;
  readonly brand: string | null;
  readonly name: string;
  readonly category: string;
  readonly price: number | null;
  readonly currency: string;
  readonly image_url: string | null;
  readonly affiliate_url: string | null;
  readonly availability: Record<string, unknown>;
  readonly attributes: Record<string, unknown>;
}

export interface MappedExtraction {
  readonly upsertRow: ProductCandidateUpsertRow;
  readonly fieldsBelowConfidenceThreshold: readonly string[];
}

/**
 * Maps a provider result to the row `products/index.ts` upserts.
 * Returns `null` when the provider found no product name at all — see
 * this file's header. Pure and total otherwise (never throws), so
 * `handler.ts` decides what an unmappable extraction means for the HTTP
 * response rather than this file choosing an error shape.
 */
export function mapExtractionToUpsertRow(result: ProductExtractionResult): MappedExtraction | null {
  if (!result.name) {
    return null;
  }

  const flags = new Set(result.unreadFields);
  const lowConfidence = (
    entry: { readonly confidence: number } | null,
    field: string,
  ) => {
    if (entry && entry.confidence < LOW_CONFIDENCE_THRESHOLD) flags.add(field);
  };
  lowConfidence(result.retailer, "retailer");
  lowConfidence(result.brand, "brand");
  lowConfidence(result.name, "name");
  lowConfidence(result.category, "category");
  lowConfidence(result.price, "price");
  lowConfidence(result.currency, "currency");
  lowConfidence(result.imageUrl, "image_url");

  let hostnameFallback = "unknown";
  try {
    hostnameFallback = new URL(result.canonicalUrl).hostname.replace(/^www\./, "");
  } catch {
    // canonicalizeUrl already tried to parse this; an unparsable URL here
    // means the input was never a URL to begin with, which schema.ts's
    // validation should have already rejected — this is defense-in-depth.
  }
  const retailer = result.retailer?.value ?? hostnameFallback;

  const categoryValue = result.category?.value;
  const category = categoryValue && KNOWN_CATEGORIES.has(categoryValue)
    ? categoryValue
    : DEFAULT_CATEGORY;
  if (!categoryValue || !KNOWN_CATEGORIES.has(categoryValue)) {
    flags.add("category");
  }

  // §7's currency is always populated — the DB column is `not null default
  // 'USD'` and a price with no stated currency is far more often USD (the
  // dominant currency across this codebase's fixture/test retailers) than
  // it is meaningfully ambiguous; flagged low-confidence either way so nothing
  // downstream treats a defaulted currency as a read one.
  const currency = result.currency?.value ?? DEFAULT_CURRENCY;

  return {
    upsertRow: {
      canonical_url: result.canonicalUrl,
      retailer,
      brand: result.brand?.value ?? null,
      name: result.name.value,
      category,
      price: result.price?.value ?? null,
      currency,
      image_url: result.imageUrl?.value ?? null,
      affiliate_url: result.affiliateUrl,
      availability: { ...result.availability },
      attributes: { ...result.attributes },
    },
    fieldsBelowConfidenceThreshold: [...flags].sort(),
  };
}

// ── product_candidates row -> wire DTO ──────────────────────────────────────

/** The `product_candidates` columns every reader below needs. */
export interface ProductCandidateRow {
  readonly id: string;
  readonly canonical_url: string;
  readonly retailer: string | null;
  readonly brand: string | null;
  readonly name: string;
  readonly category: string | null;
  readonly price: number | null;
  readonly currency: string;
  readonly image_url: string | null;
  readonly affiliate_url: string | null;
  readonly availability: unknown;
  readonly attributes: unknown;
  readonly sponsored: boolean;
  readonly last_checked_at: string | null;
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

/**
 * Reads a `product_candidates` row back onto the wire, applying the same
 * category/retailer default policy `mapExtractionToUpsertRow` applies at
 * write time — a row inserted by a future curated-catalog path
 * (P6-SHOP-08, not built here) is not guaranteed to have populated either
 * column, and the Swift `ProductCandidate` decode requires both present.
 */
export function mapProductCandidateRowToDTO(row: ProductCandidateRow): ProductCandidateDTO {
  const flags: string[] = [];

  let hostnameFallback = "unknown";
  try {
    hostnameFallback = new URL(row.canonical_url).hostname.replace(/^www\./, "");
  } catch {
    // See mapExtractionToUpsertRow's matching comment.
  }
  const retailer = row.retailer ?? hostnameFallback;
  if (!row.retailer) flags.push("retailer");

  const category = row.category && KNOWN_CATEGORIES.has(row.category)
    ? row.category
    : DEFAULT_CATEGORY;
  if (!row.category || !KNOWN_CATEGORIES.has(row.category)) flags.push("category");

  return {
    id: row.id,
    canonical_url: row.canonical_url,
    retailer,
    ...(row.brand ? { brand: row.brand } : {}),
    name: row.name,
    category,
    ...(row.price !== null ? { price: row.price } : {}),
    ...(row.currency ? { currency: row.currency } : {}),
    ...(row.image_url ? { image_url: row.image_url } : {}),
    ...(row.affiliate_url ? { affiliate_url: row.affiliate_url } : {}),
    availability: asRecord(row.availability),
    attributes: asRecord(row.attributes),
    ...(row.last_checked_at ? { last_checked_at: row.last_checked_at } : {}),
    sponsored: row.sponsored,
    fields_below_confidence_threshold: flags.sort(),
  };
}

// ── product_candidates row -> ScorableItem / RedundancyItem ────────────────
//
// `product_candidates.attributes jsonb` is, per that column's own comment
// in `20260728100600_commerce.sql`, heterogeneous and less trustworthy than
// `closet_items`' discrete columns — no writer of this codebase's own
// (`mapExtractionToUpsertRow` above) currently populates colour/pattern/
// fit/material/seasonality/warmth data into it at all (see
// `products/README.md`'s honest accounting of what the extraction
// providers actually read). Every field below is therefore expected to be
// absent far more often than a closet item's equivalent column, and each
// one degrades to the exact same documented prior `closetItemMapper.ts`'s
// consumers already use for an unread closet item — there is no second
// "candidate is unknown" prior invented here.

const KNOWN_PATTERNS_C: ReadonlySet<string> = new Set<Pattern>([
  "solid",
  "stripe",
  "check",
  "herringbone",
  "print",
  "texture-only",
]);
const KNOWN_FITS_C: ReadonlySet<string> = new Set<Fit>([
  "slim",
  "tailored",
  "regular",
  "relaxed",
  "oversized",
]);
const KNOWN_SEASONS_C: ReadonlySet<string> = new Set<Season>([
  "spring",
  "summer",
  "fall",
  "winter",
]);

function stringArray(value: unknown): readonly string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((v): v is string => typeof v === "string");
}

export interface MappedCandidateForEvaluation {
  /**
   * `laundryState`/`availabilityState` are fixed at `"clean"`/`"available"`
   * — correct BY DEFINITION for a not-yet-owned candidate, not a guess:
   * the hypothetical this scores is "if you bought this today," and a
   * just-purchased garment is, by definition, clean and available. See
   * `unlockCount.ts`'s own note that its candidate pool answers a
   * hypothetical-ownership question, not "what can I wear today."
   */
  readonly item: ScorableItem | null;
  readonly redundancyItem: RedundancyItem | null;
  /** `null` when the category has no wardrobe-graph role at all (fragrance — see `roleFor`). Every anchored-generation/redundancy path in `products/evaluation.ts` branches on this. */
  readonly role: ScorableItem["role"] | null;
  readonly degraded: readonly string[];
}

export function mapProductCandidateRowToEvaluationInput(
  row: ProductCandidateRow,
): MappedCandidateForEvaluation {
  const attrs = asRecord(row.attributes);
  const degraded: string[] = [];

  const categoryWord = row.category && KNOWN_CATEGORIES.has(row.category)
    ? (row.category as ClothingCategory)
    : DEFAULT_CATEGORY;
  if (!row.category) degraded.push("category (never extracted; scored as the default 'top')");
  const role = roleFor(categoryWord);

  const colorWord = typeof attrs["color"] === "string" ? attrs["color"] as string : null;
  const resolvedColor = resolveColorName(colorWord);
  if (colorWord && !resolvedColor) {
    degraded.push(`colour "${colorWord}" (not in the known vocabulary)`);
  }
  if (!colorWord) degraded.push("colour (not extracted for this candidate)");

  const secondaryColorWords = stringArray(attrs["secondary_colors"]);
  const secondaryColors = secondaryColorWords
    .map((w) => resolveColorName(w)?.lch ?? null)
    .filter((lch): lch is NonNullable<typeof lch> => lch !== null);

  const patternRaw = typeof attrs["pattern"] === "string" ? attrs["pattern"] : null;
  const pattern = patternRaw && KNOWN_PATTERNS_C.has(patternRaw) ? patternRaw as Pattern : null;

  const fitRaw = typeof attrs["fit"] === "string" ? attrs["fit"] : null;
  const fit = fitRaw && KNOWN_FITS_C.has(fitRaw) ? fitRaw as Fit : null;
  if (!fit) degraded.push("fit (not extracted for this candidate)");

  const materials = stringArray(attrs["materials"] ?? attrs["material"]).map((m) =>
    m.toLowerCase()
  );

  const seasonalityRaw = stringArray(attrs["seasonality"]);
  const seasonality = seasonalityRaw.filter((s): s is Season => KNOWN_SEASONS_C.has(s));

  const formalityScore = typeof attrs["formality_score"] === "number"
    ? attrs["formality_score"]
    : null;
  if (formalityScore === null) {
    degraded.push("formality (not extracted; scored against the category default)");
  }

  const warmthScore = typeof attrs["warmth_score"] === "number" ? attrs["warmth_score"] : null;
  const waterResistanceScore = typeof attrs["water_resistance_score"] === "number"
    ? attrs["water_resistance_score"]
    : null;

  if (role === null) {
    // Fragrance: no wardrobe-graph role exists for it at all (`roleFor`'s
    // own header — "a scent cannot clash with a pair of trousers").
    // Neither `ScorableItem` nor `RedundancyItem` can be honestly
    // constructed (both require a `GarmentRole`), so both are `null` and
    // `products/evaluation.ts` takes its documented no-role branch instead
    // of calling into the outfit-compatibility/redundancy engine at all.
    return {
      item: null,
      redundancyItem: null,
      role: null,
      degraded: [...degraded, "wardrobe-graph role (this category has none — see roleFor)"],
    };
  }

  const item: ScorableItem = {
    id: row.id,
    category: categoryWord,
    role,
    primaryColor: resolvedColor?.lch ?? null,
    isNeutral: resolvedColor?.isNeutral ?? false,
    secondaryColors,
    pattern,
    patternScale: null,
    materials,
    formalityScore,
    fit,
    seasonality,
    warmthScore,
    waterResistanceScore,
    laundryState: "clean",
    availabilityState: "available",
  };

  const redundancyItem: RedundancyItem = {
    id: row.id,
    category: categoryWord,
    role,
    primaryColorLab: resolvedColor ? labFromLCh(resolvedColor.lch) : null,
    formalityScore,
    fit,
    materials,
    seasonality,
  };

  return { item, redundancyItem, role, degraded };
}
