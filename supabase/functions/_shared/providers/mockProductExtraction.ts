// ============================================================================
// _shared/providers/mockProductExtraction.ts
// ============================================================================
// Deterministic `ProductExtractionProvider` for local development, Deno
// tests, and any deploy that has not flipped on the live HTML adapter — the
// same role `mockVisionAnalysis.ts` plays for `closet/`. No network access,
// no vendor key, and the same input always produces the same output.
//
// WHY THIS DERIVES A RESULT FROM THE URL'S SHAPE RATHER THAN RETURNING ONE
// FIXED FIXTURE. `products/handler_test.ts` and the extract endpoint's own
// dedup logic (`canonical_url` uniqueness) need *different* URLs to
// plausibly extract to *different* products, or every test would be
// exercising a single hardcoded row. Deriving brand/retailer/name from the
// hostname and path is honest about what it is doing — a deterministic
// placeholder, not a claim that anything was read from a real page — and it
// is exactly the same reasoning `mockVisionAnalysis.ts`'s header gives for
// deriving its own output from device hints instead of one canned answer.
//
// A URL containing the literal path segment `/unextractable` always
// resolves to a `name: null` result, so `handler_test.ts` can exercise
// P6-SHOP-03's "unsupported/unparseable URL returns a clear error" path
// without needing the live HTML adapter or a real unparseable page.
// ============================================================================

import type { ProviderRequestContext } from "./types.ts";
import {
  canonicalizeUrl,
  type ExtractedField,
  type ProductExtractionProvider,
  type ProductExtractionRequest,
  type ProductExtractionResult,
} from "./productExtraction.ts";

function field<T>(value: T, confidence: number): ExtractedField<T> {
  return { value, confidence };
}

/** A tiny, deliberately-incomplete retailer→brand table, enough to make two different fixture domains resolve to two different plausible brands in tests. Not a real retailer directory. */
const KNOWN_RETAILERS: ReadonlyMap<string, { retailer: string; brand: string }> = new Map([
  ["uniqlo.com", { retailer: "Uniqlo", brand: "Uniqlo" }],
  ["jcrew.com", { retailer: "J.Crew", brand: "J.Crew" }],
  ["everlane.com", { retailer: "Everlane", brand: "Everlane" }],
]);

const CATEGORY_KEYWORDS: ReadonlyMap<string, string> = new Map([
  ["shirt", "top"],
  ["tee", "top"],
  ["sweater", "top"],
  ["polo", "top"],
  ["chino", "bottom"],
  ["trouser", "bottom"],
  ["jean", "bottom"],
  ["jacket", "outerwear"],
  ["coat", "outerwear"],
  ["sneaker", "shoes"],
  ["boot", "shoes"],
  ["belt", "accessory"],
  ["watch", "watch"],
]);

function hostnameOf(url: string): string | null {
  try {
    return new URL(url).hostname.replace(/^www\./, "").toLowerCase();
  } catch {
    return null;
  }
}

function titleCaseFromSlug(slug: string): string {
  return slug
    .split(/[-_]+/)
    .filter((part) => part.length > 0)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

/** Deterministic: same input, same output. Safe to share across requests in one isolate. */
export class MockProductExtractionProvider implements ProductExtractionProvider {
  extractProduct(
    request: ProductExtractionRequest,
    ctx: ProviderRequestContext,
  ): Promise<ProductExtractionResult> {
    void ctx.idempotencyKey;
    const canonicalUrl = canonicalizeUrl(request.url);
    const unreadFields: string[] = [];

    if (request.url.includes("/unextractable")) {
      // Deliberate test fixture path — see this file's header.
      return Promise.resolve({
        canonicalUrl,
        retailer: null,
        brand: null,
        name: null,
        category: null,
        price: null,
        currency: null,
        imageUrl: null,
        affiliateUrl: null,
        availability: {},
        attributes: {},
        unreadFields: [
          "retailer",
          "brand",
          "name",
          "category",
          "price",
          "currency",
          "image_url",
        ],
      });
    }

    const hostname = hostnameOf(request.url);
    if (hostname === null) {
      unreadFields.push("retailer", "brand", "name", "category", "price", "currency", "image_url");
      return Promise.resolve({
        canonicalUrl,
        retailer: null,
        brand: null,
        name: null,
        category: null,
        price: null,
        currency: null,
        imageUrl: null,
        affiliateUrl: null,
        availability: {},
        attributes: {},
        unreadFields,
      });
    }

    const known = KNOWN_RETAILERS.get(hostname);
    const retailer = known
      ? field(known.retailer, 0.95)
      : field(titleCaseFromSlug(hostname.split(".")[0] ?? hostname), 0.4);
    if (!known) unreadFields.push("retailer");

    const brand = known ? field(known.brand, 0.85) : null;
    if (!known) unreadFields.push("brand");

    // Derive a plausible product name + category from the last non-empty
    // path segment — e.g. "/products/oxford-cloth-button-down" ->
    // "Oxford Cloth Button Down". A URL with no path at all (bare
    // hostname) has genuinely nothing to name a product from.
    let pathname: string;
    try {
      pathname = new URL(request.url).pathname;
    } catch {
      pathname = "";
    }
    const segments = pathname.split("/").filter((s) => s.length > 0);
    const lastSegment = segments[segments.length - 1];

    if (!lastSegment) {
      unreadFields.push("name", "category", "price", "currency", "image_url");
      return Promise.resolve({
        canonicalUrl,
        retailer,
        brand,
        name: null,
        category: null,
        price: null,
        currency: null,
        imageUrl: null,
        affiliateUrl: null,
        availability: {},
        attributes: {},
        unreadFields,
      });
    }

    const productTitle = titleCaseFromSlug(lastSegment.replace(/\.\w+$/, ""));
    const name = field(known ? `${known.brand} ${productTitle}` : productTitle, 0.6);

    let category: ExtractedField<string> | null = null;
    const lowerSlug = lastSegment.toLowerCase();
    for (const [keyword, categoryWord] of CATEGORY_KEYWORDS) {
      if (lowerSlug.includes(keyword)) {
        category = field(categoryWord, 0.7);
        break;
      }
    }
    if (!category) unreadFields.push("category");

    // A mock deliberately does not fabricate a price: URLs have no price
    // encoded in them, and a mock number here would be exactly the
    // confounded reading this file's header warns against. Product pages
    // do sometimes carry price in the URL (rare) — not modeled, so this
    // mock always reports price/currency/image as unread, same as an
    // honest scraper would for a JS-rendered page (see
    // `htmlProductExtraction.ts`'s header on that exact limitation).
    unreadFields.push("price", "currency", "image_url");

    return Promise.resolve({
      canonicalUrl,
      retailer,
      brand,
      name,
      category,
      price: null,
      currency: null,
      imageUrl: null,
      affiliateUrl: null,
      availability: {},
      attributes: {},
      unreadFields,
    });
  }
}
