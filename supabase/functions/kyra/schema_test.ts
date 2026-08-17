import { assertEquals, assertThrows } from "@std/assert";
import { AppError } from "../_shared/errors.ts";
import {
  KyraContractError,
  kyraResponseSchema,
  parseEnvelope,
  parseKyraRespondBody,
  parseKyraStructuredResponse,
} from "./schema.ts";

const VALID_UUID = "550e8400-e29b-41d4-a716-446655440000";
const OTHER_UUID = "11111111-2222-4333-8444-555555555555";

Deno.test("parseEnvelope requires a JSON object with a body field", () => {
  assertThrows(() => parseEnvelope("nope"), AppError);
  assertThrows(() => parseEnvelope({}), AppError);
});

Deno.test("parseKyraRespondBody requires non-empty text", () => {
  assertThrows(() => parseKyraRespondBody({}), AppError);
  assertThrows(() => parseKyraRespondBody({ text: "   " }), AppError);
  assertThrows(() => parseKyraRespondBody("nope"), AppError);
});

Deno.test("parseKyraRespondBody parses a minimal body", () => {
  const parsed = parseKyraRespondBody({ text: "What should I wear tonight?" });
  assertEquals(parsed.threadId, undefined);
  assertEquals(parsed.text, "What should I wear tonight?");
  assertEquals(parsed.attachments, []);
  assertEquals(parsed.weatherSnapshot, null);
});

Deno.test("parseKyraRespondBody parses thread, attachments, weather", () => {
  const parsed = parseKyraRespondBody({
    thread_id: VALID_UUID,
    text: "Rank these",
    attachments: [
      { type: "closet_item", value: OTHER_UUID },
      { type: "product_link", value: "https://example.com/shirt" },
    ],
    weather_snapshot: { temperature_high: 21, temperature_low: 12, condition: "rain" },
  });
  assertEquals(parsed.threadId, VALID_UUID);
  assertEquals(parsed.attachments.length, 2);
  assertEquals(parsed.weatherSnapshot, {
    temperatureHigh: 21,
    temperatureLow: 12,
    condition: "rain",
  });
});

Deno.test("parseKyraRespondBody rejects a non-UUID closet_item attachment", () => {
  assertThrows(
    () =>
      parseKyraRespondBody({
        text: "hi",
        attachments: [{ type: "closet_item", value: "not-a-uuid" }],
      }),
    AppError,
  );
});

Deno.test("parseKyraRespondBody rejects a malformed weather snapshot", () => {
  assertThrows(
    () =>
      parseKyraRespondBody({
        text: "hi",
        weather_snapshot: { temperature_high: "21", temperature_low: 12, condition: "rain" },
      }),
    AppError,
  );
  assertThrows(
    () =>
      parseKyraRespondBody({
        text: "hi",
        weather_snapshot: { temperature_high: 21, temperature_low: 12, condition: "meteors" },
      }),
    AppError,
  );
});

// ---------------------------------------------------------------------------
// Structured response validation
// ---------------------------------------------------------------------------

function validResponse(): Record<string, unknown> {
  return {
    message: "I'd wear the olive polo.",
    intent: "daily_outfit",
    cards: [
      { type: "outfit", outfit_id: VALID_UUID, reason: "clean and easy", compatibility_score: 82 },
      { type: "closet_item", closet_item_id: OTHER_UUID },
      {
        type: "comparison_table",
        table: { title: "Options", column_headers: ["Price"], rows: [["$40"], ["$85"]] },
      },
      { type: "action", action: { id: "a1", label: "Save this", kind: "save_outfit" } },
    ],
    suggested_actions: [{ id: "s1", label: "Wear this", kind: "wear_outfit" }],
    memory_proposals: [{
      memory_type: "fit_note",
      content: "Relaxed through the chest",
      confidence: 0.8,
    }],
    confidence: 0.74,
  };
}

Deno.test("parseKyraStructuredResponse accepts the client-decodable shape", () => {
  const { response, droppedEntries } = parseKyraStructuredResponse(
    JSON.stringify(validResponse()),
  );
  assertEquals(droppedEntries, 0);
  assertEquals(response.intent, "daily_outfit");
  assertEquals(response.cards.length, 4);
  assertEquals(response.suggested_actions[0]?.kind, "wear_outfit");
  assertEquals(response.memory_proposals[0]?.memory_type, "fit_note");
});

Deno.test("parseKyraStructuredResponse hard-fails on top-level defects", () => {
  assertThrows(() => parseKyraStructuredResponse("not json"), KyraContractError);
  assertThrows(() => parseKyraStructuredResponse('"a string"'), KyraContractError);
  const noMessage = { ...validResponse(), message: "" };
  assertThrows(() => parseKyraStructuredResponse(JSON.stringify(noMessage)), KyraContractError);
  const badIntent = { ...validResponse(), intent: "styling" };
  assertThrows(() => parseKyraStructuredResponse(JSON.stringify(badIntent)), KyraContractError);
  const badConfidence = { ...validResponse(), confidence: "high" };
  assertThrows(
    () => parseKyraStructuredResponse(JSON.stringify(badConfidence)),
    KyraContractError,
  );
});

Deno.test("intent only ever parses to one of the six documented values", () => {
  // P5-KYRA-02 acceptance: every documented intent round-trips; nothing else.
  for (
    const intent of [
      "daily_outfit",
      "product_advice",
      "outfit_review",
      "packing",
      "education",
      "general",
    ]
  ) {
    const { response } = parseKyraStructuredResponse(
      JSON.stringify({ ...validResponse(), intent }),
    );
    assertEquals(response.intent, intent);
  }
});

Deno.test("per-entry defects are dropped, not fatal — the Swift decoder would throw on them", () => {
  const raw = validResponse();
  (raw["cards"] as unknown[]).push({ type: "education", title: "Nope" }); // no such card type
  (raw["suggested_actions"] as unknown[]).push({ id: "x", label: "Bad", kind: "wear_this" }); // docs/06 kind, not a Swift kind
  (raw["memory_proposals"] as unknown[]).push({
    memory_type: "fit_preference", // docs/06 §3.9 vocabulary, not the DB enum
    content: "x",
    confidence: 0.9,
  });
  const { response, droppedEntries } = parseKyraStructuredResponse(JSON.stringify(raw));
  assertEquals(droppedEntries, 3);
  assertEquals(response.cards.length, 4);
  assertEquals(response.suggested_actions.length, 1);
  assertEquals(response.memory_proposals.length, 1);
});

Deno.test("out-of-range confidence is clamped, not rejected", () => {
  const { response } = parseKyraStructuredResponse(
    JSON.stringify({ ...validResponse(), confidence: 1.4 }),
  );
  assertEquals(response.confidence, 1);
});

Deno.test("kyraResponseSchema names every required top-level field", () => {
  const schema = kyraResponseSchema();
  assertEquals(schema["required"], [
    "message",
    "intent",
    "cards",
    "suggested_actions",
    "memory_proposals",
    "confidence",
  ]);
});
