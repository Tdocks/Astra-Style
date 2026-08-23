// ============================================================================
// closet/schema.ts
// ============================================================================
// Request/response schemas for the `closet` Edge Function:
//   POST /analyze-item
//   POST /batch-analyze
//   GET  /batch-status/:id
//
// Wire shapes mirror
// `ios/AstraStyle/Domain/Models/ClosetItemAnalysisResult.swift` exactly,
// including snake_case CodingKeys. SECURITY: there is no `user_id` field
// anywhere below — parsers ignore unknown keys, and the only identity
// source is the verified JWT in handler.ts.
// ============================================================================

import { badRequest } from "../_shared/errors.ts";
import { isRecord, isUUID, optionalString, requireRecord } from "../_shared/validation.ts";

const MAX_BATCH_ITEMS = 20;
const MAX_STORAGE_PATH_LENGTH = 512;
const MAX_OCR_LINES = 40;
const MAX_OCR_LINE_LENGTH = 200;
const MAX_DOMINANT_COLORS = 8;

const CLOTHING_CATEGORIES = new Set([
  "top",
  "bottom",
  "outerwear",
  "shoes",
  "accessory",
  "watch",
  "fragrance",
  "dress",
  "skirt",
]);

const IMAGE_TYPES = new Set([
  "front",
  "back",
  "label",
  "detail",
  "on_body",
  "other",
]);

export interface DeviceHints {
  dominantColorsRgb: string[];
  detectedText: string[];
  approximateCategory?: string;
}

export interface AnalyzeItemElement {
  requestId: string;
  storagePath: string;
  imageType: string;
  deviceHints?: DeviceHints;
}

export interface AnalyzeItemRequestBody {
  requestId: string;
  storagePath: string;
  imageType: string;
  deviceHints?: DeviceHints;
}

export interface BatchAnalyzeRequestBody {
  items: AnalyzeItemElement[];
}

export interface FieldSuggestionDTO<T> {
  value: T;
  confidence: number;
}

/** Wire DTO matching ClosetItemAnalysisResult CodingKeys. */
export interface ClosetItemAnalysisResultDTO {
  name?: FieldSuggestionDTO<string>;
  brand?: FieldSuggestionDTO<string>;
  category: FieldSuggestionDTO<string>;
  subcategory?: FieldSuggestionDTO<string>;
  primary_color?: FieldSuggestionDTO<string>;
  secondary_colors: FieldSuggestionDTO<string>[];
  pattern?: FieldSuggestionDTO<string>;
  material: FieldSuggestionDTO<string>[];
  size?: FieldSuggestionDTO<string>;
  fit?: FieldSuggestionDTO<string>;
  condition?: FieldSuggestionDTO<string>;
  seasonality: FieldSuggestionDTO<string>[];
  formality_score?: FieldSuggestionDTO<number>;
  warmth_score?: FieldSuggestionDTO<number>;
  water_resistance_score?: FieldSuggestionDTO<number>;
  normalized_image_path?: string;
  ocr_text?: string;
  fields_below_confidence_threshold: string[];
}

export interface ClosetItemAnalysisFailureDTO {
  reason: string;
  message?: string;
}

export interface ClosetItemAnalysisBatchItemDTO {
  request_id: string;
  result?: ClosetItemAnalysisResultDTO;
  error?: ClosetItemAnalysisFailureDTO;
}

export interface ClosetItemAnalysisBatchDTO {
  results: ClosetItemAnalysisBatchItemDTO[];
}

export interface BatchJobEnqueueDTO {
  job_id: string;
  status: "queued" | "generating" | "complete" | "failed";
}

export interface BatchJobStatusDTO {
  job_id: string;
  status: "queued" | "generating" | "complete" | "failed";
  results: ClosetItemAnalysisBatchItemDTO[];
  error_message?: string;
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

function parseDeviceHints(raw: unknown, field: string): DeviceHints | undefined {
  if (raw === undefined || raw === null) {
    return undefined;
  }
  const record = requireRecord(raw, field);
  const colorsRaw = record["dominant_colors_rgb"];
  const textRaw = record["detected_text"];
  const colors: string[] = [];
  if (colorsRaw !== undefined && colorsRaw !== null) {
    if (!Array.isArray(colorsRaw)) {
      throw badRequest(`${field}.dominant_colors_rgb must be an array of strings.`);
    }
    if (colorsRaw.length > MAX_DOMINANT_COLORS) {
      throw badRequest(
        `${field}.dominant_colors_rgb must contain at most ${MAX_DOMINANT_COLORS} colours.`,
      );
    }
    for (let i = 0; i < colorsRaw.length; i++) {
      const entry = colorsRaw[i];
      if (typeof entry !== "string" || entry.length === 0 || entry.length > 32) {
        throw badRequest(`${field}.dominant_colors_rgb[${i}] must be a short colour string.`);
      }
      colors.push(entry);
    }
  }
  const detectedText: string[] = [];
  if (textRaw !== undefined && textRaw !== null) {
    if (!Array.isArray(textRaw)) {
      throw badRequest(`${field}.detected_text must be an array of strings.`);
    }
    if (textRaw.length > MAX_OCR_LINES) {
      throw badRequest(`${field}.detected_text must contain at most ${MAX_OCR_LINES} lines.`);
    }
    for (let i = 0; i < textRaw.length; i++) {
      const entry = textRaw[i];
      if (typeof entry !== "string" || entry.length > MAX_OCR_LINE_LENGTH) {
        throw badRequest(
          `${field}.detected_text[${i}] must be a string of at most ${MAX_OCR_LINE_LENGTH} characters.`,
        );
      }
      detectedText.push(entry);
    }
  }
  const approx = optionalString(
    record["approximate_category"],
    `${field}.approximate_category`,
    32,
  );
  if (approx !== undefined && !CLOTHING_CATEGORIES.has(approx)) {
    throw badRequest(
      `${field}.approximate_category must be a known clothing_category value.`,
    );
  }
  return {
    dominantColorsRgb: colors,
    detectedText,
    approximateCategory: approx,
  };
}

function parseAnalyzeElement(raw: unknown, field: string): AnalyzeItemElement {
  const record = requireRecord(raw, field);
  const requestId = record["request_id"];
  if (!isUUID(requestId)) {
    throw badRequest(`${field}.request_id must be a UUID string.`);
  }
  const storagePath = record["storage_path"];
  if (typeof storagePath !== "string" || storagePath.length === 0) {
    throw badRequest(`${field}.storage_path must be a non-empty string.`);
  }
  if (storagePath.length > MAX_STORAGE_PATH_LENGTH) {
    throw badRequest(
      `${field}.storage_path must be at most ${MAX_STORAGE_PATH_LENGTH} characters.`,
    );
  }
  if (storagePath.includes("..") || storagePath.startsWith("/")) {
    throw badRequest(`${field}.storage_path must be a relative private storage path.`);
  }
  const imageTypeRaw = record["image_type"];
  const imageType = typeof imageTypeRaw === "string" ? imageTypeRaw : "front";
  if (!IMAGE_TYPES.has(imageType)) {
    throw badRequest(`${field}.image_type must be a known image_type value.`);
  }
  return {
    requestId,
    storagePath,
    imageType,
    deviceHints: parseDeviceHints(record["device_hints"], `${field}.device_hints`),
  };
}

/** Parses the body of `POST /closet/analyze-item` (one element, not wrapped). */
export function parseAnalyzeItemBody(rawBody: unknown): AnalyzeItemRequestBody {
  const element = parseAnalyzeElement(rawBody, "body");
  return {
    requestId: element.requestId,
    storagePath: element.storagePath,
    imageType: element.imageType,
    deviceHints: element.deviceHints,
  };
}

/** Parses the body of `POST /closet/batch-analyze`. */
export function parseBatchAnalyzeBody(rawBody: unknown): BatchAnalyzeRequestBody {
  const record = requireRecord(rawBody, "body");
  const itemsRaw = record["items"];
  if (!Array.isArray(itemsRaw)) {
    throw badRequest("body.items must be an array.");
  }
  if (itemsRaw.length === 0) {
    throw badRequest("body.items must contain at least one item.");
  }
  if (itemsRaw.length > MAX_BATCH_ITEMS) {
    throw badRequest(`body.items must contain at most ${MAX_BATCH_ITEMS} items.`);
  }
  const seen = new Set<string>();
  const items = itemsRaw.map((entry, index) => {
    const element = parseAnalyzeElement(entry, `body.items[${index}]`);
    if (seen.has(element.requestId)) {
      throw badRequest(`body.items[${index}].request_id must be unique within the batch.`);
    }
    seen.add(element.requestId);
    return element;
  });
  return { items };
}

/**
 * Asserts a storage path is under the caller's own folder.
 * Paths are compared lowercased because Postgres `auth.uid()::text` is
 * lowercase while some clients mint uppercase UUID strings (HANDOFF §5.3).
 */
export function assertOwnsStoragePath(storagePath: string, userId: string): void {
  const expectedPrefix = `users/${userId.toLowerCase()}/`;
  if (!storagePath.toLowerCase().startsWith(expectedPrefix)) {
    throw badRequest("storage_path must point at an object in your own private folder.");
  }
}

export function parseIdempotencyKey(headerValue: string | null): string {
  if (headerValue === null || headerValue.trim().length === 0) {
    throw badRequest("Idempotency-Key header is required for this endpoint.");
  }
  const key = headerValue.trim();
  if (key.length > 128) {
    throw badRequest("Idempotency-Key must be at most 128 characters.");
  }
  return key;
}
