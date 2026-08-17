// ============================================================================
// products/schema.ts
// ============================================================================
// Request/response schemas for the `products` Edge Function:
//   POST /products/extract   (P6-SHOP-03)
//   POST /products/evaluate  (P6-SHOP-04)
//
// Wire shapes mirror `ios/AstraStyle/Domain/Models/ProductCandidate.swift`
// and `ProductEvaluation.swift` EXACTLY on every field those two structs
// declare — same snake_case `CodingKeys`, same optionality. Every field
// this file adds beyond what those two Swift structs decode today
// (`sponsored`, `color_fit`, `lifestyle_fit`, `budget_fit`, `unmeasured`,
// `alternatives`, `fields_below_confidence_threshold`) is additive: Swift's
// `JSONDecoder` ignores unrecognized keys by default, so today's client
// decodes this response unchanged and simply never reads the extra fields.
// See `products/README.md` for the full field-by-field mapping and why
// those extras exist even though nothing consumes them yet.
//
// SECURITY: neither request body below has a `user_id` field, same
// convention as every other `schema.ts` in this project (`outfits/schema.ts`'s
// header explains why) — the only identity source is the verified JWT in
// `handler.ts`.
// ============================================================================

import { badRequest } from "../_shared/errors.ts";
import { isRecord, isUUID, requireRecord } from "../_shared/validation.ts";
import { assertSafeExternalUrl } from "./urlValidation.ts";

/** Parses the outer `AstraRequestEnvelope` and returns its (still-raw) `body`. */
export function parseEnvelope(raw: unknown): { requestId?: string; body: unknown } {
  if (!isRecord(raw)) {
    throw badRequest("Request body must be a JSON object.");
  }
  if (!("body" in raw)) {
    throw badRequest('Request envelope is missing the required "body" field.');
  }
  const requestId = typeof raw["request_id"] === "string" ? raw["request_id"] : undefined;
  return { requestId, body: raw["body"] };
}

// ============================================================================
// POST /products/extract
// ============================================================================
// Wire request matches `LiveShoppingRepository.extractProduct`'s anonymous
// `Body: Encodable { let url: URL }` — `JSONEncoder.keyEncodingStrategy`
// there is `.useDefaultKeys`, so the field name on the wire is the bare
// `"url"`, not `"canonical_url"` or anything else.

export interface ExtractProductRequestBody {
  readonly url: string;
}

const MAX_RAW_URL_LENGTH = 2048;

export function parseExtractProductBody(rawBody: unknown): ExtractProductRequestBody {
  const record = requireRecord(rawBody, "body");
  const url = record["url"];
  if (typeof url !== "string" || url.length === 0) {
    throw badRequest("body.url must be a non-empty string.");
  }
  if (url.length > MAX_RAW_URL_LENGTH) {
    throw badRequest(`body.url must be at most ${MAX_RAW_URL_LENGTH} characters.`);
  }
  // Full SSRF/scheme/shape validation, not just "is this a string" — see
  // urlValidation.ts's header. Done here (schema validation) rather than
  // deferred to the provider, per spec §14's "validate request schema"
  // step running before any provider call.
  assertSafeExternalUrl(url);
  return { url };
}

/**
 * Wire DTO for a successful `POST /products/extract` (and the
 * `product_candidates` row shape `POST /products/evaluate` reads back).
 * Field-for-field match to `ProductCandidate.CodingKeys` — see this file's
 * header for which fields beyond that struct are additive extras.
 *
 * `retailer`, `name` and `category` are NOT optional here, matching
 * `ProductCandidate.retailer: String` / `.name: String` /
 * `.category: ClothingCategory`, which are non-optional in Swift — a
 * missing or null value for any of the three would fail the client's
 * decode outright. `products/mapper.ts` is what guarantees all three are
 * always present (with an honestly-flagged default for `retailer`/
 * `category` when extraction did not read one, and a hard extraction
 * failure — never a fabricated value — when `name` cannot be resolved).
 */
export interface ProductCandidateDTO {
  readonly id: string;
  readonly canonical_url: string;
  readonly retailer: string;
  readonly brand?: string;
  readonly name: string;
  readonly category: string;
  readonly price?: number;
  readonly currency?: string;
  readonly image_url?: string;
  readonly affiliate_url?: string;
  readonly availability: Readonly<Record<string, unknown>>;
  readonly attributes: Readonly<Record<string, unknown>>;
  readonly last_checked_at?: string;
  /** Additive (P6-SHOP-09). Spec §17: labeled, never influencing ranking — see `products/ranking.ts`. */
  readonly sponsored: boolean;
  /** Additive, mirrors `ClosetItemAnalysisResultDTO`'s field of the same name/purpose. */
  readonly fields_below_confidence_threshold: readonly string[];
}

// ============================================================================
// POST /products/evaluate
// ============================================================================
// Wire request matches `LiveShoppingRepository.evaluateProduct`'s anonymous
// `Body: Encodable { let productCandidateID: UUID }` with
// `CodingKeys.productCandidateID = "product_candidate_id"`.

export interface EvaluateProductRequestBody {
  readonly productCandidateId: string;
}

export function parseEvaluateProductBody(rawBody: unknown): EvaluateProductRequestBody {
  const record = requireRecord(rawBody, "body");
  const id = record["product_candidate_id"];
  if (!isUUID(id)) {
    throw badRequest("body.product_candidate_id must be a UUID string.");
  }
  return { productCandidateId: id };
}

/** One alternative surfaced alongside the primary verdict — spec §5.5 step 3's "alternatives," ranked organically per P6-SHOP-09 (see `products/ranking.ts`). Additive: no Swift model consumes this yet. */
export interface AlternativeProductDTO {
  readonly product_candidate_id: string;
  readonly name: string;
  readonly price?: number;
  readonly currency?: string;
  readonly compatibility_score: number;
  readonly sponsored: boolean;
}

/**
 * Wire DTO for a successful `POST /products/evaluate`. Field-for-field
 * match to `ProductEvaluation.CodingKeys` for every field that struct
 * declares; everything after `reasoning`/`created_at` is an additive
 * extra — see this file's header.
 */
export interface ProductEvaluationDTO {
  readonly user_id: string;
  readonly product_candidate_id: string;
  readonly compatibility_score: number;
  readonly redundancy_score: number;
  readonly outfits_unlocked: number;
  /** `null`, never `0`/omitted, when no honest cost-per-wear projection exists (§7.2's own edge case). */
  readonly expected_cost_per_wear: number | null;
  readonly verdict: "buy" | "consider" | "wait_for_sale" | "skip";
  readonly reasoning: string;
  readonly created_at: string;
  /** Additive (spec §6.19's full score set; Swift's `ProductEvaluation` does not decode these yet). */
  /**
   * Nullable, and that is the honest shape. A budget fit of `0` says "this
   * blows the budget you set"; a man who never set one has not blown it, and
   * zero-filling would report a failure he cannot have had. Same for a dress
   * code never stated and a colour never extracted.
   */
  readonly color_fit: number | null;
  readonly lifestyle_fit: number | null;
  readonly budget_fit: number | null;
  /** Additive (P6-SHOP-09). The candidate BEING evaluated is never excluded from receiving a verdict for being sponsored — this only labels it. */
  readonly sponsored: boolean;
  readonly unmeasured: readonly string[];
  readonly alternatives: readonly AlternativeProductDTO[];
}
