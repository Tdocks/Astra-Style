// ============================================================================
// _shared/providers/productExtraction.ts
// ============================================================================
// `ProductExtractionProvider` — the fifth of spec §8's five provider
// protocols (`docs/00-master-spec.md` §8: StylistReasoningProvider,
// VisionAnalysisProvider, ImageGenerationProvider, EmbeddingProvider,
// ProductExtractionProvider). Interface ONLY, mirroring
// `visionAnalysis.ts`'s shape exactly: no vendor SDK, no HTTP client, no API
// key handling here. A mock lives beside it (`mockProductExtraction.ts`); a
// live adapter lives in `htmlProductExtraction.ts`. Both are constructed
// exclusively in `products/index.ts` (ADR 0004) — never from a handler,
// never from iOS.
//
// WHY THIS TAKES A URL, NOT A RETAILER-SPECIFIC REQUEST SHAPE.
//
// Spec §17 names three MVP ingestion options: a curated admin catalog
// (P6-SHOP-08, a different code path entirely — a service-role insert, not
// this provider), retailer affiliate feeds (also not this provider — a
// batch sync job, unbuilt), and "user-pasted product URLs analyzed on
// demand." This provider protocol exists for exactly the third option: one
// URL in, one best-effort structured product out. It has no per-retailer
// method because §17 explicitly says "do not rely on unrestricted scraping
// as THE ONLY product source" — the plural sources are a schema/ingestion
// concern (`product_candidates` accepting rows from three origins), not
// something a single provider interface should try to special-case per
// retailer. See `htmlProductExtraction.ts`'s header for what the one live
// adapter actually does about that guardrail.
//
// WHY EVERY FIELD BUT `name` IS NULLABLE, AND `name` IS NULLABLE TOO.
//
// This codebase's rule (CLAUDE.md, restated everywhere in `_shared/scoring/`
// and `visionAnalysis.ts`) is that absent is honest and a confounded reading
// is not. A page that has no machine-readable price genuinely has no price
// — returning `0` or omitting the field in favour of a guessed number would
// be exactly the confounded reading the rule forbids. `name` is nullable
// too, for a harsher reason: unlike price, category or image, a product
// candidate with no name at all is not a degraded-but-usable result, it is
// not a result. `products/schema.ts`'s caller treats a `null` name as
// extraction failure (P6-SHOP-03's acceptance criterion: "An
// unsupported/unparseable URL returns a clear error, not a
// partially-populated row") rather than writing a `product_candidates` row
// with an invented title.
//
// `canonicalizeUrl` LIVES HERE, NOT IN `products/`.
//
// Both providers below need to compute `canonicalUrl` as part of their own
// result (it is the field every extraction result carries regardless of
// what the page yielded), and `products/schema.ts` independently needs the
// same function to validate/normalize a pasted URL before ever calling a
// provider. A shared leaf-level helper avoids the alternative — `products/`
// importing from a sibling function's directory, or two independently
// drifting implementations of the same normalization rule.
// ============================================================================

import type { ProviderRequestContext } from "./types.ts";

/** One field this provider read, plus how sure it is. Mirrors `docs/08`'s field-confidence shape used throughout `visionAnalysis.ts`'s consumers. */
export interface ExtractedField<T> {
  readonly value: T;
  /** 0–1. Below 0.6 is this codebase's low-confidence line (`closet/mapper.ts`). */
  readonly confidence: number;
}

export interface ProductExtractionRequest {
  /** The user-pasted URL, already validated as http(s) and non-SSRF-shaped by `products/schema.ts` before this is ever called. */
  readonly url: string;
}

/**
 * `docs/00-master-spec.md` §8 / §9's `product_candidates` field list,
 * provider-shaped. `category` is a free-text guess at a
 * `clothing_category` word (`"top"`, `"bottom"`, ...) rather than the
 * typed enum, for the same reason `GarmentAnalysisResult.category` in
 * `visionAnalysis.ts` is a string: the provider is not trusted to emit a
 * value that is already valid against the Postgres enum, and `products/
 * mapper.ts` is where that gets resolved (with an explicit, flagged
 * default) — never silently inside the provider.
 */
export interface ProductExtractionResult {
  /** Normalized form of the input URL (tracking parameters stripped). Always present — computed from the input, not "extracted." */
  readonly canonicalUrl: string;
  readonly retailer: ExtractedField<string> | null;
  readonly brand: ExtractedField<string> | null;
  /** `null` means extraction found no product title at all — see this file's header. */
  readonly name: ExtractedField<string> | null;
  /** A `clothing_category` word, unvalidated — `products/mapper.ts` checks membership. */
  readonly category: ExtractedField<string> | null;
  readonly price: ExtractedField<number> | null;
  /** ISO 4217. Only ever set when the page stated a currency; never inferred from locale/TLD. */
  readonly currency: ExtractedField<string> | null;
  readonly imageUrl: ExtractedField<string> | null;
  /**
   * An affiliate/monetized version of the product URL, if this provider
   * itself resolved one (e.g. a retailer API that returns a tracked link).
   * NOT the same question as `product_candidates.sponsored` — see
   * `products/index.ts`'s upsert comment. A user-pasted URL extraction
   * has no reason to ever populate this; it exists on the interface for a
   * future retailer-API-based adapter (§8's other named MVP option) that
   * might.
   */
  readonly affiliateUrl: string | null;
  /** e.g. in-stock sizes — shape varies by retailer, echoed into `product_candidates.availability` as-is. */
  readonly availability: Readonly<Record<string, unknown>>;
  /** e.g. material, color words, fit notes — echoed into `product_candidates.attributes` as-is. */
  readonly attributes: Readonly<Record<string, unknown>>;
  /** Field names this extraction could not read at all (absent from the object above), for the wire's `fields_below_confidence_threshold`. */
  readonly unreadFields: readonly string[];
}

export interface ProductExtractionProvider {
  extractProduct(
    request: ProductExtractionRequest,
    ctx: ProviderRequestContext,
  ): Promise<ProductExtractionResult>;
}

// ── URL canonicalization (shared by both providers and `products/schema.ts`) ──

/**
 * Tracking/analytics query parameters stripped before a URL becomes a
 * `product_candidates.canonical_url` de-dup key. Not exhaustive of every
 * retailer's tracking scheme — it is the common cross-retailer set (UTM,
 * the major ad networks' click ids, Amazon's own `tag`/`linkCode`
 * affiliate params) — but §14/`20260728100600_commerce.sql`'s whole reason
 * `canonical_url` exists is "repeated pastes of the same product resolve
 * to one row," and the overwhelmingly common way two pastes of the same
 * product differ is exactly one of these.
 */
const TRACKING_PARAM_PREFIXES = ["utm_"];
const TRACKING_PARAM_NAMES = new Set([
  "fbclid",
  "gclid",
  "gclsrc",
  "msclkid",
  "mc_cid",
  "mc_eid",
  "ref",
  "ref_",
  "referrer",
  "igshid",
  "si",
  "tag",
  "linkcode",
  "ascsubtag",
  "affid",
]);

/**
 * Normalizes a product URL to a stable de-dup key: lowercases the host,
 * drops the fragment, strips known tracking parameters, and sorts the
 * remaining query parameters so two pastes that differ only in parameter
 * order or an added tracking tag still resolve to the same
 * `canonical_url`.
 *
 * Deliberately conservative: it does NOT strip parameters this list does
 * not name (a retailer's own `variant`/`size`/`color` query parameter is
 * left alone, since two different colorways genuinely are two different
 * products a user might paste separately), and a URL this cannot parse is
 * returned trimmed but otherwise unchanged rather than thrown away — the
 * caller (`products/schema.ts`) has already validated the URL is
 * structurally a URL before this ever runs, so that branch exists only as
 * defense-in-depth, not an expected path.
 */
export function canonicalizeUrl(rawUrl: string): string {
  let url: URL;
  try {
    url = new URL(rawUrl.trim());
  } catch {
    return rawUrl.trim();
  }

  url.hostname = url.hostname.toLowerCase();
  url.hash = "";

  const kept: [string, string][] = [];
  for (const [key, value] of url.searchParams.entries()) {
    const lowerKey = key.toLowerCase();
    if (TRACKING_PARAM_NAMES.has(lowerKey)) continue;
    if (TRACKING_PARAM_PREFIXES.some((prefix) => lowerKey.startsWith(prefix))) continue;
    kept.push([key, value]);
  }
  kept.sort(([a], [b]) => a.localeCompare(b));
  url.search = "";
  for (const [key, value] of kept) {
    url.searchParams.append(key, value);
  }

  let normalized = url.toString();
  if (url.search === "" && normalized.endsWith("/") && url.pathname !== "/") {
    normalized = normalized.slice(0, -1);
  }
  return normalized;
}
