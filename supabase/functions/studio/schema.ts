// ============================================================================
// studio/schema.ts
// ============================================================================
// Request/response schemas for the `studio` Edge Function:
//   POST /generate       (new generation, or a §21 retry via `retry_of`)
//   GET  /status/:id
//
// Wire shapes mirror `ios/AstraStyle/Domain/Models/StudioGeneration.swift`
// and the request body built in
// `ios/AstraStyle/Core/Networking/Live/LiveStudioRepository.swift`
// (`StudioGenerateBody`), snake_case key for snake_case key. SECURITY:
// there is no `user_id` field anywhere below — parsers ignore unknown
// keys, and the only identity source is the verified JWT in handler.ts.
//
// THE CONSENT BLOCK IS THE §6.17 SAFETY GATE'S WIRE HALF. The client's
// consent store (Features/Studio) records the user's attestation per
// reference image; the request carries `{acknowledged, terms_version}`;
// this schema refuses anything less than an acknowledgment of the CURRENT
// terms. The version constant below must stay equal to
// `StudioConsentTerms.currentVersion` on iOS — a bump on either side
// forces re-attestation everywhere, which is the point: consent to old
// wording is not consent to new wording (docs/08 §8.3).
// ============================================================================

import { badRequest } from "../_shared/errors.ts";
import {
  isRecord,
  isUUID,
  optionalString,
  optionalUUID,
  optionalUUIDArray,
  requireRecord,
} from "../_shared/validation.ts";

/** Keep equal to `StudioConsentTerms.currentVersion` (iOS). */
export const CURRENT_STUDIO_CONSENT_TERMS_VERSION = "2026-08-17";

const MAX_STORAGE_PATH_LENGTH = 512;
const MAX_PALETTE_ENTRIES = 6;
const MAX_PALETTE_ENTRY_LENGTH = 40;
const MAX_AD_HOC_ITEMS = 12;

// The closed vocabularies of the Swift wire enums (`StudioBackground`,
// `StudioPose`, `StudioPromptPreset`, `FormalityLevel`, `Season`). An
// unknown value is a client bug and is rejected rather than silently
// defaulted — the prompt builder's own defaulting exists for the day a
// value is REMOVED server-side, not to launder bad input.
const BACKGROUNDS = new Set(["studio", "editorial_outdoor", "urban", "neutral"]);
const POSES = new Set(["standing_front", "standing_three_quarter", "walking", "seated"]);
const PRESETS = new Set([
  "smart_casual",
  "date_night",
  "wedding",
  "vacation",
  "executive",
  "old_money_inspired",
  "minimalist",
  "night_out",
]);
const FORMALITIES = new Set(["very_casual", "casual", "balanced", "formal", "very_formal"]);
const SEASONS = new Set(["spring", "summer", "fall", "winter", "all_season"]);

export interface StudioConsentBlock {
  readonly acknowledged: boolean;
  readonly termsVersion: string;
}

export interface GenerateRequestBody {
  readonly kind: "generate";
  readonly referenceImagePath: string;
  readonly outfitId?: string;
  readonly adHocItemIds: string[];
  readonly preset?: string;
  readonly preserveFace: boolean;
  readonly preserveBodyProportions: boolean;
  readonly preserveHair: boolean;
  readonly background: string;
  readonly pose: string;
  readonly formality?: string;
  readonly season?: string;
  readonly colorPalette: string[];
  readonly consent: StudioConsentBlock;
}

export interface RetryRequestBody {
  readonly kind: "retry";
  readonly retryOf: string;
}

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

function requireBoolean(value: unknown, field: string, fallback: boolean): boolean {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value !== "boolean") {
    throw badRequest(`${field} must be a boolean.`);
  }
  return value;
}

function optionalEnum(
  value: unknown,
  field: string,
  vocabulary: ReadonlySet<string>,
): string | undefined {
  const parsed = optionalString(value, field, 64);
  if (parsed === undefined) {
    return undefined;
  }
  if (!vocabulary.has(parsed)) {
    throw badRequest(`${field} must be one of: ${[...vocabulary].sort().join(", ")}.`);
  }
  return parsed;
}

function requireEnum(
  value: unknown,
  field: string,
  vocabulary: ReadonlySet<string>,
  fallback: string,
): string {
  return optionalEnum(value, field, vocabulary) ?? fallback;
}

function parsePalette(value: unknown): string[] {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw badRequest("body.color_palette must be an array of strings.");
  }
  if (value.length > MAX_PALETTE_ENTRIES) {
    throw badRequest(`body.color_palette must contain at most ${MAX_PALETTE_ENTRIES} entries.`);
  }
  return value.map((entry, index) => {
    if (
      typeof entry !== "string" || entry.length === 0 || entry.length > MAX_PALETTE_ENTRY_LENGTH
    ) {
      throw badRequest(`body.color_palette[${index}] must be a short colour-mood string.`);
    }
    return entry;
  });
}

function parseConsent(value: unknown): StudioConsentBlock {
  // A missing block and `acknowledged: false` produce the SAME message on
  // purpose: both mean "this photo has not been confirmed", and the fix is
  // identical either way.
  if (value === undefined || value === null) {
    return { acknowledged: false, termsVersion: "" };
  }
  const record = requireRecord(value, "body.consent");
  const acknowledged = record["acknowledged"] === true;
  const termsVersion = optionalString(record["terms_version"], "body.consent.terms_version", 32) ??
    "";
  return { acknowledged, termsVersion };
}

/**
 * The consent gate itself (spec §6.17 Safety, docs/08 §8.3 step 4) —
 * checked on every generation, enforced server-side so no client bug or
 * cached job resubmission can reach a provider without it. Fails as
 * `validation` (400) with a specific, actionable message; it never
 * consumes quota because nothing has been enqueued yet.
 */
export function assertConsentCurrent(consent: StudioConsentBlock): void {
  if (!consent.acknowledged) {
    throw badRequest(
      "This reference photo hasn't been confirmed yet. Confirm it's a photo of you, or of someone who gave you permission, before generating a preview.",
    );
  }
  if (consent.termsVersion !== CURRENT_STUDIO_CONSENT_TERMS_VERSION) {
    throw badRequest(
      "The consent terms have changed since you confirmed this photo. Please confirm the updated terms and try again.",
    );
  }
}

/**
 * Reference images live under `users/{uid}/references/` (spec §15, and
 * the P6-STUDIO-02 acceptance criterion verbatim). Stricter than the
 * closet's own-folder check on purpose: a path under the caller's folder
 * but outside `references/` (say, a closet photo) is not a consented
 * reference image and must not become one by path traversal.
 */
export function assertOwnedReferencePath(storagePath: string, userId: string): void {
  if (
    storagePath.length === 0 ||
    storagePath.length > MAX_STORAGE_PATH_LENGTH ||
    storagePath.includes("..") ||
    storagePath.startsWith("/")
  ) {
    throw badRequest("reference_image_path must be a relative private storage path.");
  }
  const expectedPrefix = `users/${userId.toLowerCase()}/references/`;
  if (!storagePath.toLowerCase().startsWith(expectedPrefix)) {
    throw badRequest(
      "reference_image_path must point at a reference photo in your own private folder.",
    );
  }
}

/** Parses the body of `POST /studio/generate` — either a new job or a retry. */
export function parseGenerateBody(rawBody: unknown): GenerateRequestBody | RetryRequestBody {
  const record = requireRecord(rawBody, "body");

  const retryOf = record["retry_of"];
  if (retryOf !== undefined && retryOf !== null) {
    if (!isUUID(retryOf)) {
      throw badRequest("body.retry_of must be a UUID string.");
    }
    return { kind: "retry", retryOf };
  }

  const referenceImagePath = record["reference_image_path"];
  if (typeof referenceImagePath !== "string" || referenceImagePath.length === 0) {
    throw badRequest("body.reference_image_path must be a non-empty string.");
  }

  const outfitId = optionalUUID(record["outfit_id"], "body.outfit_id");
  const adHocItemIds = optionalUUIDArray(
    record["ad_hoc_item_ids"],
    "body.ad_hoc_item_ids",
    MAX_AD_HOC_ITEMS,
  );
  if (outfitId === undefined && adHocItemIds.length === 0) {
    throw badRequest("Select an outfit or at least one closet item to visualize.");
  }

  return {
    kind: "generate",
    referenceImagePath,
    outfitId,
    adHocItemIds,
    preset: optionalEnum(record["preset"], "body.preset", PRESETS),
    preserveFace: requireBoolean(record["preserve_face"], "body.preserve_face", true),
    preserveBodyProportions: requireBoolean(
      record["preserve_body_proportions"],
      "body.preserve_body_proportions",
      true,
    ),
    preserveHair: requireBoolean(record["preserve_hair"], "body.preserve_hair", true),
    background: requireEnum(record["background"], "body.background", BACKGROUNDS, "studio"),
    pose: requireEnum(record["pose"], "body.pose", POSES, "standing_front"),
    formality: optionalEnum(record["formality"], "body.formality", FORMALITIES),
    season: optionalEnum(record["season"], "body.season", SEASONS),
    colorPalette: parsePalette(record["color_palette"]),
    consent: parseConsent(record["consent"]),
  };
}

/**
 * Wire DTO matching `StudioGeneration`'s CodingKeys exactly. Decoded by
 * `AstraAPIClient`'s `.iso8601` date strategy, which does NOT accept
 * fractional seconds — hence `toWireTimestamp` below.
 */
export interface StudioGenerationDTO {
  readonly id: string;
  readonly user_id: string;
  readonly reference_image_path: string;
  readonly outfit_id: string | null;
  readonly prompt_payload: Record<string, unknown>;
  readonly status: "queued" | "generating" | "complete" | "failed";
  readonly result_image_path: string | null;
  readonly provider: string | null;
  readonly error_message: string | null;
  readonly deleted_at: string | null;
  readonly created_at: string;
  readonly updated_at: string;
}

/**
 * Postgres renders timestamptz with fractional seconds and a `+00:00`
 * offset; Swift's `JSONDecoder.DateDecodingStrategy.iso8601`
 * (ISO8601DateFormatter, default options) rejects fractional seconds
 * outright. Second precision is plenty for job rows, so the wire carries
 * `yyyy-MM-ddTHH:mm:ssZ` and nothing more.
 */
export function toWireTimestamp(value: string | Date): string {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw badRequest("Encountered an invalid timestamp on a generation row.");
  }
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}
