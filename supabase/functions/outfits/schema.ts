// ============================================================================
// outfits/schema.ts
// ============================================================================
// Request-schema validation for both routes this function serves:
// `POST /outfits/generate` and `POST /outfits/rank` (spec §14,
// `P4-OUTFIT-07`/`P4-OUTFIT-08`). `parseGenerateOutfitsBody`'s shape mirrors
// `GenerateOutfitsBody`/`OutfitGenerationRequest` in
// ios/AstraStyle/Core/Networking/Live/LiveOutfitRepository.swift and
// ios/AstraStyle/Domain/Models/OutfitGenerationRequest.swift exactly,
// including the snake_case wire keys from their `CodingKeys`.
// `parseRankOutfitsBody` follows the same shape and validation style, since
// there is no equivalent Swift model to mirror yet — `/rank` is new.
//
// The wire format for both is `AstraRequestEnvelope<...>`
// (ios/AstraStyle/Core/Networking/AstraRequestEnvelope.swift):
//   { "request_id": string, "client_version": string, "body": { ... } }
//
// SECURITY: notice there is no `user_id` field anywhere below, on EITHER
// body. The parsers in this file read exactly the named keys they expect
// from `body` and ignore everything else — an attacker adding an extra
// `"user_id": "..."` key to the JSON body has literally no code path that
// reads it. The only source of truth for "whose closet" is the verified JWT
// handled by `_shared/jwt.ts`, consumed in `handler.ts`.
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

// ============================================================================
// POST /outfits/rank (P4-OUTFIT-08)
// ============================================================================
// A candidate is an item-id GROUP the caller already assembled (e.g. the
// outfit builder's current slot picks) — not a closet item id itself, which
// is why each candidate gets its own optional `id` the caller can supply to
// correlate a specific candidate with its scored result in the response
// (`handler.ts` echoes it back on `ScoredOutfitEnvelope.id` when present,
// rather than minting a fresh one that leaves the caller no way to tell
// which input produced which output).

/** One candidate outfit as submitted for ranking: an item-id group, with an optional caller-supplied id for correlation. */
export interface RankOutfitCandidateInput {
  readonly id?: string;
  readonly itemIds: string[];
}

export interface RankOutfitsRequestBody {
  readonly candidates: RankOutfitCandidateInput[];
  readonly lockedClosetItemIds: string[];
}

const MAX_CANDIDATES = 20;
const MAX_ITEMS_PER_CANDIDATE = 10;

/** Parses and validates the `body` object of `POST /outfits/rank`. */
export function parseRankOutfitsBody(rawBody: unknown): RankOutfitsRequestBody {
  if (!isRecord(rawBody)) {
    throw badRequest('Request envelope must contain a JSON object at "body".');
  }

  const rawCandidates = rawBody["candidates"];
  if (!Array.isArray(rawCandidates) || rawCandidates.length === 0) {
    throw badRequest("body.candidates must be a non-empty array.");
  }
  if (rawCandidates.length > MAX_CANDIDATES) {
    throw badRequest(`body.candidates must contain at most ${MAX_CANDIDATES} items.`);
  }

  const candidates = rawCandidates.map((entry, index) => {
    if (!isRecord(entry)) {
      throw badRequest(`body.candidates[${index}] must be a JSON object.`);
    }
    const id = optionalUUID(entry["id"], `body.candidates[${index}].id`);
    const itemIds = optionalUUIDArray(
      entry["item_ids"],
      `body.candidates[${index}].item_ids`,
      MAX_ITEMS_PER_CANDIDATE,
    );
    if (itemIds.length === 0) {
      throw badRequest(`body.candidates[${index}].item_ids must contain at least one item.`);
    }
    return { id, itemIds };
  });

  const lockedClosetItemIds = optionalUUIDArray(
    rawBody["locked_closet_item_ids"],
    "body.locked_closet_item_ids",
    MAX_ITEM_IDS,
  );

  return { candidates, lockedClosetItemIds };
}
