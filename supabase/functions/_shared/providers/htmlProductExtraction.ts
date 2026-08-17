// ============================================================================
// _shared/providers/htmlProductExtraction.ts
// ============================================================================
// The one live `ProductExtractionProvider` adapter (P6-SHOP-02). Read this
// header before trusting what "live" means here — it is the scraping-based
// option spec §8/§17 name, not a vendor product API, and it is materially
// weaker than either.
//
// WHAT THIS ADAPTER ACTUALLY DOES, PLAINLY.
//
// It issues one `fetch()` for the pasted URL, reads the response body as
// text, and regex-extracts three things a retailer's own storefront usually
// puts in the raw HTML `<head>` for search engines and social-media link
// previews to read — because this adapter has no more privileged a view of
// the page than a search-engine crawler does:
//
//   1. Open Graph / `product:` meta tags (`<meta property="og:title" ...>`,
//      `og:image`, `product:price:amount`, `product:price:currency`,
//      `og:site_name`).
//   2. schema.org JSON-LD `<script type="application/ld+json">` blocks,
//      preferring a `Product` node's `name`/`brand`/`image`/`offers.price`/
//      `offers.priceCurrency`/`category` when present — usually more
//      complete than the OG tags where both exist.
//   3. A bare `<title>` tag, as the last-resort name source.
//
// WHAT IT DOES NOT DO, AND WHY THAT MATTERS MORE THAN WHAT IT DOES.
//
// - No JavaScript execution. A storefront that renders price/availability
//   client-side (React/Vue hydration, a "loading price..." skeleton) hands
//   this adapter an HTML shell with none of that in it, and it will
//   honestly report those fields unread — not guess at them.
// - No pagination/variant awareness — one fetch of one URL, so a
//   "select a size first" price gate is invisible to it.
// - No retry against anti-bot defenses. A 403/429/CAPTCHA response is
//   surfaced as a `PROVIDER_UNAVAILABLE`/`RATE_LIMITED` `ProviderError`
//   (see `products/handler.ts`), never retried with a different user agent
//   or a headless browser — this codebase has no such infrastructure.
// - No vendor account, no SLA, no data contract with any retailer. It reads
//   whatever a plain HTTP GET happens to return today, which a retailer can
//   change or block at any time without notice.
//
// This is exactly why spec §17 says "do not rely on unrestricted scraping
// as the only product source": this adapter alone is not a durable product
// pipeline. It is one of three MVP ingestion paths, existing specifically
// for the "user pastes a link" flow (§5.5 step 1); the curated admin
// catalog (P6-SHOP-08, service-role insert path, not built by this ticket)
// and retailer affiliate feeds are the other two and are load-bearing
// precisely because this adapter is this limited.
//
// MANUAL VERIFICATION STATUS (read before treating P6-SHOP-02's "3 real
// retailer pages" acceptance criterion as closed): the regex extraction
// below was written against, and is unit-tested with (`*_test.ts`), fixture
// HTML modeled on real Open-Graph/JSON-LD markup shapes. It has NOT been
// run in this change against three live retailer URLs from an environment
// with verified general internet egress — see `products/README.md` for the
// honest status of that specific acceptance criterion.
//
// `fetchImpl` IS INJECTED, NOT `globalThis.fetch` DIRECTLY.
//
// Same reason `OpenAIVisionAnalysisProvider` takes `loadImageBytes` as a
// constructor callback rather than reaching for a global: every test in
// `htmlProductExtraction_test.ts` supplies a fixture-returning function, so
// the whole adapter is exercised with zero real network access, matching
// this project's "mock the boundary" testing rule. `products/index.ts` is
// the only place this is ever constructed with real `fetch`.
// ============================================================================

import { ProviderError } from "./types.ts";
import type { ProviderRequestContext } from "./types.ts";
import {
  canonicalizeUrl,
  type ExtractedField,
  type ProductExtractionProvider,
  type ProductExtractionRequest,
  type ProductExtractionResult,
} from "./productExtraction.ts";

export interface HtmlProductExtractionDeps {
  /** Injected so tests never touch the network — see this file's header. */
  readonly fetchImpl: (url: string, init: RequestInit) => Promise<Response>;
  /** Max bytes of response body read before giving up on a page — defends against an unbounded/streamed response tying up the isolate. */
  readonly maxBodyBytes?: number;
}

const DEFAULT_MAX_BODY_BYTES = 2_000_000; // 2MB — generous for a product page's <head>, small next to a media response.

const CATEGORY_KEYWORDS: ReadonlyMap<string, string> = new Map([
  ["shirt", "top"],
  ["tee", "top"],
  ["sweater", "top"],
  ["polo", "top"],
  ["hoodie", "top"],
  ["chino", "bottom"],
  ["trouser", "bottom"],
  ["pant", "bottom"],
  ["jean", "bottom"],
  ["short", "bottom"],
  ["jacket", "outerwear"],
  ["coat", "outerwear"],
  ["parka", "outerwear"],
  ["sneaker", "shoes"],
  ["boot", "shoes"],
  ["loafer", "shoes"],
  ["belt", "accessory"],
  ["wallet", "accessory"],
  ["watch", "watch"],
  ["cologne", "fragrance"],
  ["fragrance", "fragrance"],
  ["eau de", "fragrance"],
]);

function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ")
    .trim();
}

/** Every `<meta property="..." content="...">` / `<meta name="..." content="...">` tag, keyed lowercase. Attribute order in the source tag is not assumed. */
function extractMetaTags(html: string): Map<string, string> {
  const result = new Map<string, string>();
  const tags = html.match(/<meta\b[^>]*>/gi) ?? [];
  for (const tag of tags) {
    const keyMatch = /(?:property|name)\s*=\s*["']([^"']+)["']/i.exec(tag);
    const contentMatch = /content\s*=\s*["']([^"']*)["']/i.exec(tag);
    if (keyMatch?.[1] && contentMatch) {
      const key = keyMatch[1].toLowerCase();
      if (!result.has(key)) {
        result.set(key, decodeHtmlEntities(contentMatch[1] ?? ""));
      }
    }
  }
  return result;
}

function extractTitleTag(html: string): string | null {
  const match = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
  if (!match?.[1]) return null;
  const decoded = decodeHtmlEntities(match[1]).replace(/\s+/g, " ").trim();
  return decoded.length > 0 ? decoded : null;
}

/** Recursively collects schema.org `Product` nodes from a parsed JSON-LD document, which may be a single object, an array of documents, or an `@graph` wrapper. */
function collectProductNodes(node: unknown, out: Record<string, unknown>[]): void {
  if (Array.isArray(node)) {
    for (const entry of node) collectProductNodes(entry, out);
    return;
  }
  if (typeof node !== "object" || node === null) return;
  const record = node as Record<string, unknown>;
  const type = record["@type"];
  const typeStr = Array.isArray(type) ? type.join(",") : typeof type === "string" ? type : "";
  if (typeStr.toLowerCase().includes("product")) {
    out.push(record);
  }
  if (Array.isArray(record["@graph"])) {
    collectProductNodes(record["@graph"], out);
  }
}

/** Every schema.org `Product` node found across all `application/ld+json` script blocks. Malformed JSON in one block does not abort the others. */
function extractJsonLdProducts(html: string): Record<string, unknown>[] {
  const products: Record<string, unknown>[] = [];
  const scriptRe =
    /<script[^>]+type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let match: RegExpExecArray | null;
  while ((match = scriptRe.exec(html)) !== null) {
    const raw = match[1];
    if (!raw) continue;
    try {
      collectProductNodes(JSON.parse(raw), products);
    } catch {
      // One retailer's malformed JSON-LD must not sink extraction for a
      // page that has a second, valid block or usable OG tags.
      continue;
    }
  }
  return products;
}

/** JSON-LD `offers` is an object, an array of offers, or (rarely) absent. Reads the first offer's price/currency, since a variant-level price breakdown is not something a single static fetch can resolve anyway (see this file's header on JS-rendered variant pricing). */
function firstOffer(product: Record<string, unknown>): Record<string, unknown> | null {
  const offers = product["offers"];
  if (Array.isArray(offers)) {
    const first = offers.find((o) => typeof o === "object" && o !== null);
    return (first as Record<string, unknown> | undefined) ?? null;
  }
  if (typeof offers === "object" && offers !== null) {
    return offers as Record<string, unknown>;
  }
  return null;
}

function toFiniteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const cleaned = value.replace(/[^0-9.]/g, "");
    const parsed = Number.parseFloat(cleaned);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function brandNameFrom(product: Record<string, unknown>): string | null {
  const brand = product["brand"];
  if (typeof brand === "string") return brand;
  if (typeof brand === "object" && brand !== null) {
    const name = (brand as Record<string, unknown>)["name"];
    if (typeof name === "string") return name;
  }
  return null;
}

/** Matches known category keywords against free text (a JSON-LD `category` string, a breadcrumb, or the product name) — same vocabulary `mockProductExtraction.ts` uses, kept in sync manually since the two files test independently. */
function categoryFromText(text: string | null): string | null {
  if (!text) return null;
  const lower = text.toLowerCase();
  for (const [keyword, categoryWord] of CATEGORY_KEYWORDS) {
    if (lower.includes(keyword)) return categoryWord;
  }
  return null;
}

function field<T>(value: T, confidence: number): ExtractedField<T> {
  return { value, confidence };
}

export class HtmlProductExtractionProvider implements ProductExtractionProvider {
  constructor(private readonly deps: HtmlProductExtractionDeps) {}

  async extractProduct(
    request: ProductExtractionRequest,
    ctx: ProviderRequestContext,
  ): Promise<ProductExtractionResult> {
    const canonicalUrl = canonicalizeUrl(request.url);
    const html = await this.fetchHtml(request.url, ctx.timeoutMs);
    return buildResultFromHtml(canonicalUrl, html);
  }

  private async fetchHtml(url: string, timeoutMs: number): Promise<string> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let response: Response;
    try {
      response = await this.deps.fetchImpl(url, {
        method: "GET",
        redirect: "follow",
        signal: controller.signal,
        headers: {
          // Honest, identifiable UA — this is a user-initiated fetch, not a
          // crawler impersonating a browser to evade blocking.
          "User-Agent": "AstraStyleBot/1.0 (+product-link extraction; user-initiated)",
          "Accept": "text/html,application/xhtml+xml",
        },
      });
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") {
        throw new ProviderError("TIMEOUT", true, "Timed out fetching that product page.");
      }
      throw new ProviderError(
        "PROVIDER_UNAVAILABLE",
        true,
        "Couldn't reach that URL.",
      );
    } finally {
      clearTimeout(timer);
    }

    if (!response.ok) {
      throw mapHttpStatusToProviderError(response.status);
    }

    const maxBytes = this.deps.maxBodyBytes ?? DEFAULT_MAX_BODY_BYTES;
    const buffer = await response.arrayBuffer();
    const bytes = buffer.byteLength > maxBytes ? buffer.slice(0, maxBytes) : buffer;
    return new TextDecoder("utf-8", { fatal: false }).decode(bytes);
  }
}

function mapHttpStatusToProviderError(status: number): ProviderError {
  if (status === 429) {
    return new ProviderError(
      "RATE_LIMITED",
      true,
      "That retailer is rate-limiting requests right now.",
    );
  }
  if (status === 403 || status === 401) {
    // A block/anti-bot response, not a credentials problem this adapter
    // has any way to fix — see this file's header on "no retry against
    // anti-bot defenses." Not retryable: a second identical request from
    // the same isolate will get the same answer.
    return new ProviderError(
      "PROVIDER_UNAVAILABLE",
      false,
      "That retailer blocked this request.",
      status,
    );
  }
  if (status === 404 || status === 410) {
    return new ProviderError("INVALID_INPUT", false, "That product page doesn't exist.", status);
  }
  if (status >= 500) {
    return new ProviderError(
      "PROVIDER_UNAVAILABLE",
      true,
      "That retailer's site is having trouble right now.",
      status,
    );
  }
  return new ProviderError(
    "PROVIDER_UNAVAILABLE",
    false,
    `Unexpected response (${status}) fetching that page.`,
    status,
  );
}

/**
 * Merges JSON-LD `Product` data (preferred, higher confidence — a
 * retailer that bothered to emit structured data is asserting it as fact
 * for search engines) with Open Graph meta tags (fallback, medium
 * confidence) and the bare `<title>` (name of last resort, low
 * confidence). A field neither source has is left `null`, never guessed.
 */
function buildResultFromHtml(canonicalUrl: string, html: string): ProductExtractionResult {
  const meta = extractMetaTags(html);
  const jsonLdProducts = extractJsonLdProducts(html);
  const product = jsonLdProducts[0] ?? null;
  const offer = product ? firstOffer(product) : null;
  const unreadFields: string[] = [];

  // ── name ──
  const jsonLdName = product && typeof product["name"] === "string"
    ? (product["name"] as string)
    : null;
  const ogTitle = meta.get("og:title") ?? null;
  const titleTag = extractTitleTag(html);
  const name = jsonLdName
    ? field(jsonLdName, 0.85)
    : ogTitle
    ? field(ogTitle, 0.65)
    : titleTag
    ? field(titleTag, 0.3)
    : null;
  if (!name) unreadFields.push("name");

  // ── brand ──
  const jsonLdBrand = product ? brandNameFrom(product) : null;
  const ogSite = meta.get("og:site_name") ?? null;
  const brand = jsonLdBrand ? field(jsonLdBrand, 0.8) : ogSite ? field(ogSite, 0.5) : null;
  if (!brand) unreadFields.push("brand");

  // ── retailer ──
  let hostname: string | null = null;
  try {
    hostname = new URL(canonicalUrl).hostname.replace(/^www\./, "");
  } catch {
    hostname = null;
  }
  const retailer = ogSite ? field(ogSite, 0.7) : hostname ? field(hostname, 0.4) : null;
  if (!retailer) unreadFields.push("retailer");

  // ── price / currency ──
  const jsonLdPrice = offer ? toFiniteNumber(offer["price"]) : null;
  const ogPriceAmount = toFiniteNumber(
    meta.get("product:price:amount") ?? meta.get("og:price:amount") ?? null,
  );
  const price = jsonLdPrice !== null
    ? field(jsonLdPrice, 0.85)
    : ogPriceAmount !== null
    ? field(ogPriceAmount, 0.65)
    : null;
  if (!price) unreadFields.push("price");

  const jsonLdCurrency = offer && typeof offer["priceCurrency"] === "string"
    ? (offer["priceCurrency"] as string).toUpperCase()
    : null;
  const ogCurrency = (meta.get("product:price:currency") ?? meta.get("og:price:currency") ?? null)
    ?.toUpperCase() ?? null;
  const currency = jsonLdCurrency
    ? field(jsonLdCurrency, 0.85)
    : ogCurrency
    ? field(ogCurrency, 0.65)
    : null;
  if (!currency) unreadFields.push("currency");

  // ── image ──
  const jsonLdImageRaw = product ? product["image"] : null;
  const jsonLdImage = typeof jsonLdImageRaw === "string"
    ? jsonLdImageRaw
    : Array.isArray(jsonLdImageRaw) && typeof jsonLdImageRaw[0] === "string"
    ? (jsonLdImageRaw[0] as string)
    : typeof jsonLdImageRaw === "object" && jsonLdImageRaw !== null &&
        typeof (jsonLdImageRaw as Record<string, unknown>)["url"] === "string"
    ? ((jsonLdImageRaw as Record<string, unknown>)["url"] as string)
    : null;
  const ogImage = meta.get("og:image") ?? null;
  const imageUrl = jsonLdImage ? field(jsonLdImage, 0.85) : ogImage ? field(ogImage, 0.7) : null;
  if (!imageUrl) unreadFields.push("image_url");

  // ── category (best-effort keyword match; products/mapper.ts applies the documented default when this is null) ──
  const jsonLdCategoryText = product && typeof product["category"] === "string"
    ? (product["category"] as string)
    : null;
  const categoryWord = categoryFromText(jsonLdCategoryText) ??
    categoryFromText(name?.value ?? null) ??
    categoryFromText(canonicalUrl);
  const category = categoryWord ? field(categoryWord, jsonLdCategoryText ? 0.75 : 0.5) : null;
  if (!category) unreadFields.push("category");

  return {
    canonicalUrl,
    retailer,
    brand,
    name,
    category,
    price,
    currency,
    imageUrl,
    // No retailer API integration exists on this adapter — see this
    // file's header — so it never resolves its own affiliate link.
    affiliateUrl: null,
    availability: {},
    attributes: product ? { source: "json-ld" } : meta.size > 0 ? { source: "og-tags" } : {},
    unreadFields,
  };
}
