import { assert, assertEquals } from "@std/assert";
import {
  applyGuardrails,
  containsSensitiveTraitInference,
  type GuardrailInput,
} from "./guardrails.ts";
import type { KyraStructuredResponse } from "./schema.ts";
import type { ToolExecution } from "./tools/registry.ts";

const KNOWN_ITEM = "00000000-0000-4000-8000-000000000001";
const KNOWN_OUTFIT = "11111111-0000-4000-8000-000000000001";
const UNKNOWN_ID = "deadbeef-0000-4000-8000-000000000000";

function response(overrides: Partial<KyraStructuredResponse> = {}): KyraStructuredResponse {
  return {
    message: "I'd wear the olive polo with stone trousers.",
    intent: "daily_outfit",
    cards: [],
    suggested_actions: [],
    memory_proposals: [],
    confidence: 0.8,
    ...overrides,
  };
}

function input(
  overrides: Partial<GuardrailInput> & { response: KyraStructuredResponse },
): GuardrailInput {
  return {
    toolTrace: [],
    knownClosetItemIds: new Set([KNOWN_ITEM]),
    knownOutfitIds: new Set([KNOWN_OUTFIT]),
    knownProductCandidateIds: new Set(),
    ...overrides,
  };
}

// -- Category 1: medical / body-change advice --------------------------------

Deno.test("guardrail: medical body-change advice is replaced with a styling redirect", () => {
  const outcome = applyGuardrails(input({
    response: response({
      message: "To look leaner for the event, try a caloric deficit and drop a few pounds first.",
    }),
  }));
  assertEquals(outcome.violations, ["medical_body_advice"]);
  assert(!outcome.response.message.includes("caloric"));
  assert(outcome.response.message.includes("dress"));
  assertEquals(outcome.response.intent, "general");
  assertEquals(outcome.response.cards, []);
});

Deno.test("guardrail: a proper decline that MENTIONS the topic is not punished", () => {
  const outcome = applyGuardrails(input({
    response: response({
      message: "I can't help with losing weight — that side of it isn't styling. But I can " +
        "make this outfit read sharper as you are right now.",
    }),
  }));
  assertEquals(outcome.violations, []);
});

// -- Category 2: sensitive-trait inference -----------------------------------

Deno.test("guardrail: sensitive-trait inference is replaced entirely", () => {
  const outcome = applyGuardrails(input({
    response: response({
      message: "You seem depressed lately, so I chose brighter colors to cheer you up.",
    }),
  }));
  assertEquals(outcome.violations, ["sensitive_trait_inference"]);
  assert(!outcome.response.message.toLowerCase().includes("depressed"));
});

Deno.test("containsSensitiveTraitInference: statements about the user trip it, topics do not", () => {
  assert(containsSensitiveTraitInference("you might be pregnant"));
  assert(containsSensitiveTraitInference("he is probably muslim"));
  assert(!containsSensitiveTraitInference("church wedding dress codes usually call for a suit"));
  assert(!containsSensitiveTraitInference("I'd wear the navy blazer to the service"));
});

// -- Category 3: fit-certainty claims ----------------------------------------

Deno.test("guardrail: fit-certainty claims are hedged and confidence is capped", () => {
  const outcome = applyGuardrails(input({
    response: response({
      message: "Order the medium — it's guaranteed to fit perfectly.",
      confidence: 0.95,
    }),
  }));
  assertEquals(outcome.violations, ["fit_certainty_claim"]);
  assert(!outcome.response.message.includes("guaranteed to fit"));
  assert(outcome.response.message.includes("can't promise the exact fit"));
  assert(outcome.response.confidence <= 0.5);
});

// -- Category 4: generated-image labelling -----------------------------------

Deno.test("guardrail: a real studio generation without the estimate label gets one appended", () => {
  const trace: ToolExecution[] = [{
    name: "generate_studio_preview",
    args: {},
    result: { generation_id: "55555555-0000-4000-8000-000000000001", status: "queued" },
  }];
  const outcome = applyGuardrails(input({
    response: response({ message: "Your preview is on the way — it'll look sharp." }),
    toolTrace: trace,
  }));
  assertEquals(outcome.violations, ["generated_image_unlabelled"]);
  assert(outcome.response.message.includes("estimate"));

  // Already-labelled responses pass untouched, and the Phase 5 stub (which
  // returns error NOT_BUILT, no generation_id) never triggers the check.
  const labelled = applyGuardrails(input({
    response: response({ message: "Preview queued — remember it's an estimate, not a guarantee." }),
    toolTrace: trace,
  }));
  assertEquals(labelled.violations, []);
});

// -- Category 5: affiliate disclosure ----------------------------------------

Deno.test("guardrail: an affiliate link in tool results forces a plain disclosure", () => {
  const trace: ToolExecution[] = [{
    name: "search_products",
    args: {},
    result: {
      products: [{
        product_candidate_id: "66666666-0000-4000-8000-000000000001",
        affiliate_url: "https://retailer.example/x?aff=astra",
        is_sponsored: false,
        relevance: 80,
      }],
    },
  }];
  const outcome = applyGuardrails(input({
    response: response({ message: "The linen overshirt is the one I'd get." }),
    toolTrace: trace,
  }));
  assertEquals(outcome.violations, ["affiliate_disclosure_missing"]);
  assert(outcome.response.message.toLowerCase().includes("commission"));
});

// -- Category 6: sponsored/organic separation --------------------------------

Deno.test("guardrail: a sponsored item ranked above a better organic match is detected", () => {
  const trace: ToolExecution[] = [{
    name: "search_products",
    args: {},
    result: {
      products: [
        { product_candidate_id: "a", is_sponsored: true, relevance: 40 },
        { product_candidate_id: "b", is_sponsored: false, relevance: 85 },
      ],
    },
  }];
  const outcome = applyGuardrails(input({ response: response(), toolTrace: trace }));
  assert(outcome.violations.includes("sponsored_reordering"));
  assert(outcome.response.confidence <= 0.5);

  // Missing is_sponsored labelling is its own violation.
  const unlabelled = applyGuardrails(input({
    response: response(),
    toolTrace: [{
      name: "search_products",
      args: {},
      result: { products: [{ product_candidate_id: "c", relevance: 50 }] },
    }],
  }));
  assert(unlabelled.violations.includes("sponsored_labelling_missing"));
});

// -- Category 7: hallucinated references -------------------------------------

Deno.test("guardrail: cards naming ids nothing surfaced this turn are dropped", () => {
  const outcome = applyGuardrails(input({
    response: response({
      cards: [
        { type: "closet_item", closet_item_id: KNOWN_ITEM },
        { type: "closet_item", closet_item_id: UNKNOWN_ID },
        { type: "outfit", outfit_id: UNKNOWN_ID },
        { type: "outfit", outfit_id: KNOWN_OUTFIT },
      ],
      confidence: 0.9,
    }),
  }));
  assertEquals(outcome.violations, ["hallucinated_reference"]);
  assertEquals(outcome.response.cards.length, 2);
  assert(outcome.response.confidence <= 0.5);
});

// -- Clean pass --------------------------------------------------------------

Deno.test("guardrail: a clean response passes through byte-identical", () => {
  const clean = response({
    cards: [{ type: "outfit", outfit_id: KNOWN_OUTFIT }],
  });
  const outcome = applyGuardrails(input({ response: clean }));
  assertEquals(outcome.violations, []);
  assertEquals(outcome.response, clean);
});
