// ============================================================================
// kyra/schema.ts
// ============================================================================
// Request parsing and response-contract validation for `POST /kyra/respond`
// (P5-KYRA-02). Mirrors `outfits/schema.ts`'s conventions: snake_case wire
// keys, camelCase internal names, every parser reads exactly the keys it
// expects and ignores the rest, and there is no `user_id` field anywhere —
// the verified JWT (`_shared/jwt.ts`) is the only identity source.
//
// THE WIRE CONTRACT IS THE SWIFT CLIENT, NOT `docs/06` §4 — AND THEY
// DISAGREE. `docs/06` §4 specifies rich cards (`card_type`, full item
// payloads, an `EducationCard`), `action_id` keys, and `wear_this`-style
// action kinds. The shipped decoders — `KyraResponse.swift`,
// `KyraMessage.swift`, `LiveKyraRepository.swift` — decode something
// different and stricter:
//
//   - The card discriminator key is `type` (not `card_type`), with exactly
//     five values: `outfit` | `product` | `closet_item` | `comparison_table`
//     | `action`. There is no education card; an unknown `type` makes the
//     WHOLE response fail to decode on device.
//   - Card payloads are id references (`outfit_id`, `product_candidate_id`,
//     `closet_item_id`) or, for `comparison_table`, a nested `table` object
//     with `title` / `column_headers` / `rows` (rows of STRINGS).
//   - Suggested actions are `{id, label, kind}` (not `action_id`), and
//     `kind` is `KyraSuggestedAction.Kind`'s seven values.
//   - Memory proposals are `{memory_type, content, confidence}` where
//     `memory_type` is the Postgres `memory_type` enum — NOT §3.9's
//     `fit_preference`-style vocabulary, which exists nowhere in the schema.
//
// Emitting §4's shape would produce a response the app cannot decode; the
// client is in users' hands and the doc is not, so the client wins. Extra
// keys are safe (Codable ignores them), so where §4 asks for information the
// Swift shape lacks (an outfit card's reason and score), it rides along as
// additive fields. This file is the single place that contract lives.
// ============================================================================

import { badRequest } from "../_shared/errors.ts";
import { isRecord, isUUID, optionalString, optionalUUID } from "../_shared/validation.ts";

// ---------------------------------------------------------------------------
// Request envelope + body
// ---------------------------------------------------------------------------

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

export type KyraAttachmentType = "photo" | "product_link" | "closet_item" | "outfit";

export interface KyraAttachment {
  readonly type: KyraAttachmentType;
  readonly value: string;
}

export interface KyraRespondRequestBody {
  /** Absent for a new conversation; the handler creates the thread. */
  readonly threadId?: string;
  readonly text: string;
  readonly attachments: KyraAttachment[];
  /**
   * The client's own WeatherKit reading, in iOS's Fahrenheit wire convention,
   * and the same shape `daily-brief` accepts
   * (`temperature_high` / `temperature_low` numbers + a known `condition`).
   * There is no server-side weather provider by design (see
   * `daily-brief/README.md`); when this is null the `get_weather` tool says
   * so instead of inventing a forecast. `LiveKyraRepository` sends it only
   * after location is already authorized; neither Kyra nor this parser can
   * trigger a permission prompt.
   */
  readonly weatherSnapshot: WeatherSnapshot | null;
}

export interface WeatherSnapshot {
  readonly temperatureHigh: number;
  readonly temperatureLow: number;
  readonly condition: string;
}

const MAX_TEXT_LENGTH = 2_000;
const MAX_ATTACHMENTS = 10;
const ATTACHMENT_TYPES: ReadonlySet<string> = new Set([
  "photo",
  "product_link",
  "closet_item",
  "outfit",
]);

/**
 * Same closed vocabulary `daily-brief/schema.ts` validates against —
 * duplicated rather than imported so this function's deploy bundle does not
 * depend on a sibling function's schema file for three strings.
 */
const KNOWN_WEATHER_CONDITIONS: ReadonlySet<string> = new Set([
  "clear",
  "partly_cloudy",
  "cloudy",
  "fog",
  "drizzle",
  "rain",
  "heavy_rain",
  "thunderstorm",
  "snow",
  "sleet",
  "windy",
]);

function parseWeatherSnapshot(raw: unknown): WeatherSnapshot | null {
  if (raw === undefined || raw === null) {
    return null;
  }
  if (!isRecord(raw)) {
    throw badRequest("body.weather_snapshot must be a JSON object when present.");
  }
  const high = raw["temperature_high"];
  const low = raw["temperature_low"];
  if (typeof high !== "number" || typeof low !== "number") {
    throw badRequest(
      "body.weather_snapshot.temperature_high/temperature_low must be numbers.",
    );
  }
  const condition = raw["condition"];
  if (typeof condition !== "string" || !KNOWN_WEATHER_CONDITIONS.has(condition)) {
    throw badRequest("body.weather_snapshot.condition must be a known weather condition.");
  }
  return { temperatureHigh: high, temperatureLow: low, condition };
}

function parseAttachments(raw: unknown): KyraAttachment[] {
  if (raw === undefined || raw === null) {
    return [];
  }
  if (!Array.isArray(raw)) {
    throw badRequest("body.attachments must be an array.");
  }
  if (raw.length > MAX_ATTACHMENTS) {
    throw badRequest(`body.attachments must contain at most ${MAX_ATTACHMENTS} items.`);
  }
  return raw.map((entry, index) => {
    if (!isRecord(entry)) {
      throw badRequest(`body.attachments[${index}] must be a JSON object.`);
    }
    const type = entry["type"];
    if (typeof type !== "string" || !ATTACHMENT_TYPES.has(type)) {
      throw badRequest(
        `body.attachments[${index}].type must be one of photo, product_link, closet_item, outfit.`,
      );
    }
    const value = entry["value"];
    if (typeof value !== "string" || value.trim().length === 0) {
      throw badRequest(`body.attachments[${index}].value must be a non-empty string.`);
    }
    // Closet-item / outfit references must be resolvable ids; a photo path
    // or product URL is opaque here and validated where it is used.
    if ((type === "closet_item" || type === "outfit") && !isUUID(value)) {
      throw badRequest(`body.attachments[${index}].value must be a UUID for type ${type}.`);
    }
    return { type: type as KyraAttachmentType, value };
  });
}

/** Parses and validates the `body` object of `POST /kyra/respond`. */
export function parseKyraRespondBody(rawBody: unknown): KyraRespondRequestBody {
  if (!isRecord(rawBody)) {
    throw badRequest('Request envelope must contain a JSON object at "body".');
  }
  const text = optionalString(rawBody["text"], "body.text", MAX_TEXT_LENGTH);
  if (text === undefined || text.trim().length === 0) {
    throw badRequest("body.text must be a non-empty string.");
  }
  return {
    threadId: optionalUUID(rawBody["thread_id"], "body.thread_id"),
    text: text.trim(),
    attachments: parseAttachments(rawBody["attachments"]),
    weatherSnapshot: parseWeatherSnapshot(rawBody["weather_snapshot"]),
  };
}

// ---------------------------------------------------------------------------
// Structured response — the exact shape `KyraStructuredResponse` decodes
// ---------------------------------------------------------------------------

export const KYRA_INTENTS = [
  "daily_outfit",
  "product_advice",
  "outfit_review",
  "packing",
  "education",
  "general",
] as const;
export type KyraIntent = typeof KYRA_INTENTS[number];

/** `KyraSuggestedAction.Kind` in Swift — the only kinds the client decodes. */
export const SUGGESTED_ACTION_KINDS = [
  "wear_outfit",
  "view_alternatives",
  "open_product",
  "save_outfit",
  "schedule_outfit",
  "start_studio_generation",
  "add_occasion",
] as const;
export type SuggestedActionKind = typeof SUGGESTED_ACTION_KINDS[number];

/** The Postgres `memory_type` enum = Swift `StyleMemoryType`, verbatim. */
export const MEMORY_TYPES = [
  "preference",
  "dislike",
  "fit_note",
  "brand_affinity",
  "budget_note",
  "sizing_note",
  "general",
] as const;
export type MemoryType = typeof MEMORY_TYPES[number];

export interface SuggestedActionWire {
  readonly id: string;
  readonly label: string;
  readonly kind: SuggestedActionKind;
}

export interface ComparisonTableWire {
  readonly title: string;
  readonly column_headers: string[];
  readonly rows: string[][];
}

export type KyraCardWire =
  | {
    readonly type: "outfit";
    readonly outfit_id: string;
    /** Additive beyond the Swift decode shape; Codable ignores them. */
    readonly reason?: string;
    readonly compatibility_score?: number;
    readonly item_ids?: string[];
  }
  | { readonly type: "product"; readonly product_candidate_id: string }
  | { readonly type: "closet_item"; readonly closet_item_id: string }
  | { readonly type: "comparison_table"; readonly table: ComparisonTableWire }
  | { readonly type: "action"; readonly action: SuggestedActionWire };

export interface MemoryProposalWire {
  readonly memory_type: MemoryType;
  readonly content: string;
  readonly confidence: number;
  /** Additive (docs/06 §4 parity); the Swift decoder reads the three above. */
  readonly memory_id?: string;
  readonly action_taken?: "created" | "updated_existing" | "superseded_conflict";
  readonly supersedes_memory_id?: string | null;
}

export interface KyraStructuredResponse {
  readonly message: string;
  readonly intent: KyraIntent;
  readonly cards: KyraCardWire[];
  readonly suggested_actions: SuggestedActionWire[];
  readonly memory_proposals: MemoryProposalWire[];
  readonly confidence: number;
}

/**
 * Thrown when the model's output does not satisfy the response contract.
 * Carries a machine-usable detail string so the repair retry (docs/06 §6)
 * can tell the model exactly what to fix. Never contains user content.
 */
export class KyraContractError extends Error {
  constructor(detail: string) {
    super(detail);
    this.name = "KyraContractError";
  }
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((entry) => typeof entry === "string");
}

function parseSuggestedAction(raw: unknown): SuggestedActionWire | null {
  if (!isRecord(raw)) return null;
  const id = raw["id"];
  const label = raw["label"];
  const kind = raw["kind"];
  if (typeof id !== "string" || id.length === 0) return null;
  if (typeof label !== "string" || label.length === 0) return null;
  if (typeof kind !== "string" || !SUGGESTED_ACTION_KINDS.includes(kind as SuggestedActionKind)) {
    return null;
  }
  return { id, label, kind: kind as SuggestedActionKind };
}

function parseCard(raw: unknown): KyraCardWire | null {
  if (!isRecord(raw)) return null;
  switch (raw["type"]) {
    case "outfit": {
      const outfitId = raw["outfit_id"];
      if (!isUUID(outfitId)) return null;
      const card: {
        type: "outfit";
        outfit_id: string;
        reason?: string;
        compatibility_score?: number;
        item_ids?: string[];
      } = { type: "outfit", outfit_id: outfitId };
      if (typeof raw["reason"] === "string") card.reason = raw["reason"];
      if (typeof raw["compatibility_score"] === "number") {
        card.compatibility_score = raw["compatibility_score"];
      }
      if (isStringArray(raw["item_ids"])) card.item_ids = raw["item_ids"];
      return card;
    }
    case "product": {
      const productId = raw["product_candidate_id"];
      return isUUID(productId) ? { type: "product", product_candidate_id: productId } : null;
    }
    case "closet_item": {
      const itemId = raw["closet_item_id"];
      return isUUID(itemId) ? { type: "closet_item", closet_item_id: itemId } : null;
    }
    case "comparison_table": {
      const table = raw["table"];
      if (!isRecord(table)) return null;
      const title = table["title"];
      const columnHeaders = table["column_headers"];
      const rows = table["rows"];
      if (typeof title !== "string") return null;
      if (!isStringArray(columnHeaders)) return null;
      if (!Array.isArray(rows) || !rows.every(isStringArray)) return null;
      return {
        type: "comparison_table",
        table: { title, column_headers: columnHeaders, rows: rows as string[][] },
      };
    }
    case "action": {
      const action = parseSuggestedAction(raw["action"]);
      return action === null ? null : { type: "action", action };
    }
    default:
      return null;
  }
}

function parseMemoryProposal(raw: unknown): MemoryProposalWire | null {
  if (!isRecord(raw)) return null;
  const memoryType = raw["memory_type"];
  const content = raw["content"];
  const confidence = raw["confidence"];
  if (typeof memoryType !== "string" || !MEMORY_TYPES.includes(memoryType as MemoryType)) {
    return null;
  }
  if (typeof content !== "string" || content.length === 0) return null;
  if (typeof confidence !== "number" || confidence < 0 || confidence > 1) return null;
  const proposal: {
    memory_type: MemoryType;
    content: string;
    confidence: number;
    memory_id?: string;
    action_taken?: "created" | "updated_existing" | "superseded_conflict";
    supersedes_memory_id?: string | null;
  } = { memory_type: memoryType as MemoryType, content, confidence };
  if (isUUID(raw["memory_id"])) proposal.memory_id = raw["memory_id"];
  const action = raw["action_taken"];
  if (action === "created" || action === "updated_existing" || action === "superseded_conflict") {
    proposal.action_taken = action;
  }
  if (isUUID(raw["supersedes_memory_id"])) {
    proposal.supersedes_memory_id = raw["supersedes_memory_id"];
  }
  return proposal;
}

export interface ParsedKyraResponse {
  readonly response: KyraStructuredResponse;
  /**
   * Entries the model emitted that failed their per-entry shape and were
   * dropped rather than failing the turn. Logged (counts only) so a drifting
   * provider is visible; a dropped card is "absent", which is honest, where
   * a guessed-at repair of it would not be.
   */
  readonly droppedEntries: number;
}

/**
 * Validates the model's textual output against the client contract.
 *
 * Failure policy, deliberately two-tier:
 *  - TOP-LEVEL failures (not JSON, not an object, missing/mistyped
 *    `message`/`intent`/`confidence`, non-array collections) throw
 *    `KyraContractError` and trigger the docs/06 §6 repair retry — the
 *    response as a whole is unusable.
 *  - PER-ENTRY failures (one bad card, an unknown action kind) drop the
 *    entry and keep the response. Failing a whole good answer over one
 *    malformed card punishes the user for a defect the response survives
 *    without; the Swift decoder, by contrast, would throw on it, which is
 *    exactly why the invalid entry must not reach the wire.
 */
export function parseKyraStructuredResponse(text: string): ParsedKyraResponse {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new KyraContractError("Response is not valid JSON.");
  }
  if (!isRecord(raw)) {
    throw new KyraContractError("Response must be a JSON object.");
  }

  const message = raw["message"];
  if (typeof message !== "string" || message.trim().length === 0) {
    throw new KyraContractError("`message` must be a non-empty string.");
  }

  const intent = raw["intent"];
  if (typeof intent !== "string" || !KYRA_INTENTS.includes(intent as KyraIntent)) {
    throw new KyraContractError(
      "`intent` must be one of daily_outfit, product_advice, outfit_review, packing, education, general.",
    );
  }

  const confidence = raw["confidence"];
  if (typeof confidence !== "number" || Number.isNaN(confidence)) {
    throw new KyraContractError("`confidence` must be a number between 0 and 1.");
  }
  const clampedConfidence = Math.min(1, Math.max(0, confidence));

  const rawCards = raw["cards"] ?? [];
  const rawActions = raw["suggested_actions"] ?? [];
  const rawProposals = raw["memory_proposals"] ?? [];
  if (!Array.isArray(rawCards) || !Array.isArray(rawActions) || !Array.isArray(rawProposals)) {
    throw new KyraContractError(
      "`cards`, `suggested_actions` and `memory_proposals` must be arrays.",
    );
  }

  let droppedEntries = 0;
  const cards: KyraCardWire[] = [];
  for (const entry of rawCards) {
    const card = parseCard(entry);
    if (card === null) droppedEntries += 1;
    else cards.push(card);
  }
  const suggestedActions: SuggestedActionWire[] = [];
  for (const entry of rawActions) {
    const action = parseSuggestedAction(entry);
    if (action === null) droppedEntries += 1;
    else suggestedActions.push(action);
  }
  const memoryProposals: MemoryProposalWire[] = [];
  for (const entry of rawProposals) {
    const proposal = parseMemoryProposal(entry);
    if (proposal === null) droppedEntries += 1;
    else memoryProposals.push(proposal);
  }

  return {
    response: {
      message: message.trim(),
      intent: intent as KyraIntent,
      cards,
      suggested_actions: suggestedActions,
      memory_proposals: memoryProposals,
      confidence: clampedConfidence,
    },
    droppedEntries,
  };
}

// ---------------------------------------------------------------------------
// Response JSON Schema, handed to the provider as `responseSchema`
// ---------------------------------------------------------------------------

/**
 * The schema the model is asked to satisfy. It describes the SAME shape
 * `parseKyraStructuredResponse` validates — the Swift decode shape — not
 * docs/06 §4's richer one, for the reasons in this file's header. Kept as a
 * function returning a fresh object (matching `styleDnaResponseSchema`'s
 * convention) rather than a shared mutable constant.
 */
export function kyraResponseSchema(): Record<string, unknown> {
  const suggestedActionSchema = {
    type: "object",
    additionalProperties: false,
    required: ["id", "label", "kind"],
    properties: {
      id: { type: "string" },
      label: { type: "string" },
      kind: { type: "string", enum: [...SUGGESTED_ACTION_KINDS] },
    },
  };
  return {
    type: "object",
    additionalProperties: false,
    required: ["message", "intent", "cards", "suggested_actions", "memory_proposals", "confidence"],
    properties: {
      message: {
        type: "string",
        description: "Kyra's conversational reply. Concise; detail lives in cards.",
      },
      intent: { type: "string", enum: [...KYRA_INTENTS] },
      cards: {
        type: "array",
        items: {
          anyOf: [
            {
              type: "object",
              additionalProperties: false,
              required: ["type", "outfit_id"],
              properties: {
                type: { const: "outfit" },
                outfit_id: {
                  type: "string",
                  description: "An outfit id returned by create_outfit or rank_outfits. " +
                    "Never invent one.",
                },
                reason: { type: "string" },
                compatibility_score: { type: "integer", minimum: 0, maximum: 100 },
                item_ids: { type: "array", items: { type: "string" } },
              },
            },
            {
              type: "object",
              additionalProperties: false,
              required: ["type", "product_candidate_id"],
              properties: {
                type: { const: "product" },
                product_candidate_id: { type: "string" },
              },
            },
            {
              type: "object",
              additionalProperties: false,
              required: ["type", "closet_item_id"],
              properties: {
                type: { const: "closet_item" },
                closet_item_id: {
                  type: "string",
                  description: "A closet item id from the context packet or a search_closet " +
                    "result. Never invent one.",
                },
              },
            },
            {
              type: "object",
              additionalProperties: false,
              required: ["type", "table"],
              properties: {
                type: { const: "comparison_table" },
                table: {
                  type: "object",
                  additionalProperties: false,
                  required: ["title", "column_headers", "rows"],
                  properties: {
                    title: { type: "string" },
                    column_headers: { type: "array", items: { type: "string" } },
                    rows: {
                      type: "array",
                      items: { type: "array", items: { type: "string" } },
                    },
                  },
                },
              },
            },
            {
              type: "object",
              additionalProperties: false,
              required: ["type", "action"],
              properties: {
                type: { const: "action" },
                action: suggestedActionSchema,
              },
            },
          ],
        },
      },
      suggested_actions: { type: "array", items: suggestedActionSchema },
      memory_proposals: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["memory_type", "content", "confidence"],
          properties: {
            memory_type: { type: "string", enum: [...MEMORY_TYPES] },
            content: { type: "string" },
            confidence: { type: "number", minimum: 0, maximum: 1 },
          },
        },
      },
      confidence: {
        type: "number",
        minimum: 0,
        maximum: 1,
        description: "Self-reported confidence given available context. Below 0.5 should " +
          "correlate with hedged language in message. Not 0-100.",
      },
    },
  };
}
