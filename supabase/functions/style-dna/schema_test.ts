// ============================================================================
// style-dna/schema_test.ts
// ============================================================================
// The response validator, exercised against the outputs a LIVE provider
// realistically produces and today's deterministic one cannot: an invented
// identity, a formality value outside the Postgres enum, a tolerance out of
// range, an empty section, prose wrapped around the JSON.
//
// Today's provider passes every one of these trivially. That is the point —
// these tests are the safety net the first live adapter lands into, written
// while there is no pressure to make a real integration go green.
// ============================================================================

import { assert, assertEquals, assertThrows } from "@std/assert";
import { AppError } from "../_shared/errors.ts";
import {
  ACCESSORY_PREFERENCES,
  FORMALITY_LEVELS,
  parseEnvelope,
  parseGenerateStyleDnaBody,
  parseStyleDnaDocument,
  StyleDnaContractError,
  styleDnaResponseSchema,
} from "./schema.ts";

const IDENTITIES = ["quiet_luxury", "minimalist", "executive"] as const;

function validDocument(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    primary_identity: "quiet_luxury",
    identity_basis: "the identity you ranked first",
    secondary_influences: ["minimalist"],
    palette: {
      preferred_colors: ["charcoal", "ivory"],
      avoided_colors: ["neon brights"],
      rationale: "Neutrals that all sit together.",
    },
    silhouette: { headline: "One unbroken column.", detail: "Tonal dressing does the work." },
    signature_opportunities: [{ title: "A camel crew knit", reason: "The piece it is built on." }],
    wardrobe_priorities: [{ rank: 1, title: "Fewer pieces", reason: "Cloth shows here." }],
    summary: "You are Quiet Luxury.",
    formality_preference: "formal",
    logo_tolerance: 5,
    trend_tolerance: 20,
    accessory_preference: "minimal",
    known_inputs: ["the style identities you picked"],
    open_questions: [],
    measured_dimensions: [],
    ...overrides,
  };
}

Deno.test("formality levels match the formality_preference Postgres enum", () => {
  assertEquals([...FORMALITY_LEVELS], [
    "very_casual",
    "casual",
    "balanced",
    "formal",
    "very_formal",
  ]);
});

Deno.test("accessory preferences match the accessory_preference Postgres enum", () => {
  assertEquals([...ACCESSORY_PREFERENCES], ["minimal", "moderate", "bold"]);
});

Deno.test("a well-formed document validates", () => {
  const document = parseStyleDnaDocument(JSON.stringify(validDocument()), IDENTITIES);
  assertEquals(document.primary_identity, "quiet_luxury");
  assertEquals(document.wardrobe_priorities[0]?.rank, 1);
});

Deno.test("a null primary identity is allowed — it is the honest answer for an empty profile", () => {
  const document = parseStyleDnaDocument(
    JSON.stringify(validDocument({ primary_identity: null, secondary_influences: [] })),
    IDENTITIES,
  );
  assertEquals(document.primary_identity, null);
});

Deno.test("an invented identity is rejected before it can reach the enum column", () => {
  assertThrows(
    () =>
      parseStyleDnaDocument(
        JSON.stringify(validDocument({ primary_identity: "dark_academia" })),
        IDENTITIES,
      ),
    StyleDnaContractError,
  );
});

Deno.test("an invented secondary influence is rejected", () => {
  assertThrows(
    () =>
      parseStyleDnaDocument(
        JSON.stringify(validDocument({ secondary_influences: ["gorpcore"] })),
        IDENTITIES,
      ),
    StyleDnaContractError,
  );
});

Deno.test("repeating the primary identity among the secondaries is rejected", () => {
  // The §6.10 screen would render the same identity twice, which reads as a
  // bug even though every value in it is legal.
  assertThrows(
    () =>
      parseStyleDnaDocument(
        JSON.stringify(validDocument({ secondary_influences: ["quiet_luxury"] })),
        IDENTITIES,
      ),
    StyleDnaContractError,
  );
});

Deno.test("a formality value outside the enum is rejected", () => {
  assertThrows(
    () =>
      parseStyleDnaDocument(
        JSON.stringify(validDocument({ formality_preference: "quite formal" })),
        IDENTITIES,
      ),
    StyleDnaContractError,
  );
});

Deno.test("a tolerance outside 0-100 is rejected, because the column checks the range", () => {
  assertThrows(
    () => parseStyleDnaDocument(JSON.stringify(validDocument({ logo_tolerance: 140 })), IDENTITIES),
    StyleDnaContractError,
  );
  assertThrows(
    () => parseStyleDnaDocument(JSON.stringify(validDocument({ trend_tolerance: -1 })), IDENTITIES),
    StyleDnaContractError,
  );
});

Deno.test("a fractional tolerance is rounded rather than rejected — smallint takes an integer", () => {
  const document = parseStyleDnaDocument(
    JSON.stringify(validDocument({ logo_tolerance: 42.6 })),
    IDENTITIES,
  );
  assertEquals(document.logo_tolerance, 43);
});

Deno.test("an empty required string is rejected", () => {
  assertThrows(
    () => parseStyleDnaDocument(JSON.stringify(validDocument({ summary: "   " })), IDENTITIES),
    StyleDnaContractError,
  );
});

Deno.test("a missing section is rejected", () => {
  const document = validDocument();
  delete document["palette"];
  assertThrows(
    () => parseStyleDnaDocument(JSON.stringify(document), IDENTITIES),
    StyleDnaContractError,
  );
});

Deno.test("an unbounded list is rejected rather than persisted", () => {
  const many = Array.from({ length: 40 }, (_, index) => ({
    title: `Item ${index}`,
    reason: "Because.",
  }));
  assertThrows(
    () =>
      parseStyleDnaDocument(
        JSON.stringify(validDocument({ signature_opportunities: many })),
        IDENTITIES,
      ),
    StyleDnaContractError,
  );
});

Deno.test("prose wrapped around the JSON is rejected, not salvaged", () => {
  // A model that ignores "reply with JSON only" is a model whose output is
  // not trustworthy for this call; guessing at the JSON inside its prose
  // would hide that.
  assertThrows(
    () =>
      parseStyleDnaDocument(
        `Here is the Style DNA you asked for:\n${JSON.stringify(validDocument())}`,
        IDENTITIES,
      ),
    StyleDnaContractError,
  );
});

Deno.test("open_questions may be empty but must be present", () => {
  const withEmpty = parseStyleDnaDocument(
    JSON.stringify(validDocument({ open_questions: [] })),
    IDENTITIES,
  );
  assertEquals(withEmpty.open_questions, []);

  const document = validDocument();
  delete document["open_questions"];
  assertThrows(
    () => parseStyleDnaDocument(JSON.stringify(document), IDENTITIES),
    StyleDnaContractError,
  );
});

Deno.test("the response schema handed to a provider names every required field", () => {
  const schema = styleDnaResponseSchema(IDENTITIES);
  const required = schema["required"] as string[];
  const document = validDocument();
  for (const key of Object.keys(document)) {
    assert(required.includes(key), `${key} is produced but not required by the schema`);
  }
  assertEquals(required.length, Object.keys(document).length);
});

// ---------------------------------------------------------------------------
// Request
// ---------------------------------------------------------------------------

Deno.test("an empty body is the expected request shape", () => {
  assertEquals(parseGenerateStyleDnaBody({}), {});
  assertEquals(parseGenerateStyleDnaBody(null), {});
});

Deno.test("a non-object body is rejected rather than ignored", () => {
  assertThrows(() => parseGenerateStyleDnaBody("regenerate"), AppError);
  assertThrows(() => parseGenerateStyleDnaBody([1]), AppError);
});

Deno.test("an envelope with no body field is rejected", () => {
  assertThrows(() => parseEnvelope({ request_id: "r" }), AppError);
});
