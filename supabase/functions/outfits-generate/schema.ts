// ============================================================================
// outfits-generate/schema.ts
// ============================================================================
// Request-schema validation for `POST /outfits/generate` (spec §14). Shapes
// mirror `GenerateOutfitsBody`/`OutfitGenerationRequest` in
// ios/AstraStyle/Core/Networking/Live/LiveOutfitRepository.swift and
// ios/AstraStyle/Domain/Models/OutfitGenerationRequest.swift exactly,
// including the snake_case wire keys from their `CodingKeys`.
//
// The wire format is `AstraRequestEnvelope<GenerateOutfitsBody>`
// (ios/AstraStyle/Core/Networking/AstraRequestEnvelope.swift):
//   { "request_id": string, "client_version": string, "body": { ... } }
//
// SECURITY: notice there is no `user_id` field anywhere below. The parsers
// in this file read exactly the named keys they expect from `body` and
// ignore everything else — an attacker adding an extra `"user_id": "..."`
// key to the JSON body has literally no code path that reads it. The only
// source of truth for "whose closet" is the verified JWT handled by
// `_shared/jwt.ts`, consumed in `handler.ts`.
// ============================================================================

import { badRequest } from "../_shared/errors.ts";
import {
  isRecord,
  optionalIntInRange,
  optionalString,
  optionalUUID,
  optionalUUIDArray,
} from "../_shared/validation.ts";

export interface GenerateOutfitsRequestBody {
  occasionId?: string;
  naturalLanguageRequest?: string;
  lockedClosetItemIds: string[];
  excludedClosetItemIds: string[];
  desiredCount: number;
}

const MIN_DESIRED_COUNT = 1;
const MAX_DESIRED_COUNT = 6;
const DEFAULT_DESIRED_COUNT = 3;
const MAX_NATURAL_LANGUAGE_LENGTH = 500;
const MAX_ITEM_IDS = 50;

/** Parses and validates the `body` object of the request envelope. */
export function parseGenerateOutfitsBody(rawBody: unknown): GenerateOutfitsRequestBody {
  if (!isRecord(rawBody)) {
    throw badRequest('Request envelope must contain a JSON object at "body".');
  }

  return {
    occasionId: optionalUUID(rawBody["occasion_id"], "body.occasion_id"),
    naturalLanguageRequest: optionalString(
      rawBody["natural_language_request"],
      "body.natural_language_request",
      MAX_NATURAL_LANGUAGE_LENGTH,
    ),
    lockedClosetItemIds: optionalUUIDArray(
      rawBody["locked_closet_item_ids"],
      "body.locked_closet_item_ids",
      MAX_ITEM_IDS,
    ),
    excludedClosetItemIds: optionalUUIDArray(
      rawBody["excluded_closet_item_ids"],
      "body.excluded_closet_item_ids",
      MAX_ITEM_IDS,
    ),
    desiredCount: optionalIntInRange(
      rawBody["desired_count"],
      "body.desired_count",
      MIN_DESIRED_COUNT,
      MAX_DESIRED_COUNT,
      DEFAULT_DESIRED_COUNT,
    ),
  };
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

/** Response DTO for a single element of the `POST /outfits/generate` array response. */
export interface OutfitRecommendationDTO {
  id: string;
  name: string;
  reason: string;
  compatibility_score: number;
  item_ids: string[];
  missing_product_ids: string[];
}
