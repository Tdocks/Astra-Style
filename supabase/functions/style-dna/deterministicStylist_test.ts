// ============================================================================
// style-dna/deterministicStylist_test.ts
// ============================================================================
// P2-CORE-02's third acceptance criterion — "A profile with only required
// fields filled produces a coherent, non-empty result (graceful degradation
// with sparse input)" — is the one this file exists for, and it is tested as
// a claim about CONTENT, not only about shape. A result can satisfy every
// type in schema.ts and still be the generic filler
// `docs/01-build-roadmap.md`'s Phase 2 risks warn about.
//
// So the assertions here are, deliberately, about what the output SAYS:
//   - two different identities produce two different palettes, silhouettes
//     and signature lists (not one template with a name substituted),
//   - a sparse profile still names concrete garments,
//   - a sparse profile SAYS it is sparse, in `open_questions`,
//   - a richer profile's advice quotes the inputs that produced it,
//   - and the four summary scalars move with everything, not with the quiz
//     alone.
// ============================================================================

import { assert, assertEquals, assertNotEquals } from "@std/assert";
import { buildStyleDnaContext, type StyleDnaContext } from "./context.ts";
import {
  composeStyleDna,
  DETERMINISTIC_STYLIST_VERSION,
  DeterministicStylistProvider,
} from "./deterministicStylist.ts";
import { IDENTITY_PLAYBOOK } from "./identityPlaybook.ts";
import { parseStyleDnaDocument } from "./schema.ts";
import { STYLE_IDENTITIES } from "./handler.ts";
import { ProviderError } from "../_shared/providers/types.ts";

function contextWith(
  style: Record<string, unknown> | null,
  body: Record<string, unknown> | null = null,
  lifestyle: Record<string, unknown> | null = null,
): StyleDnaContext {
  return buildStyleDnaContext(style, body, lifestyle);
}

/** The sparsest profile the onboarding flow can actually produce: §6.5 only. */
const IDENTITY_ONLY = contextWith({
  primary_identity: "quiet_luxury",
  secondary_identities: [],
  style_goals: [],
  preference_vector: {},
});

// ---------------------------------------------------------------------------
// Every identity is covered, and covered differently
// ---------------------------------------------------------------------------

Deno.test("every style_identity enum value has a playbook", () => {
  // A missing entry would silently degrade that identity's users to the
  // no-direction path, which reads as the app not recognising a choice it
  // offered them.
  for (const identity of STYLE_IDENTITIES) {
    assert(
      IDENTITY_PLAYBOOK[identity] !== undefined,
      `no playbook for style identity '${identity}'`,
    );
  }
  assertEquals(Object.keys(IDENTITY_PLAYBOOK).length, STYLE_IDENTITIES.length);
});

Deno.test("each identity produces a distinct palette, silhouette and signature set", () => {
  const palettes = new Set<string>();
  const headlines = new Set<string>();
  const signatures = new Set<string>();

  for (const identity of STYLE_IDENTITIES) {
    const document = composeStyleDna(contextWith({ primary_identity: identity }));
    palettes.add(document.palette.preferred_colors.join("|"));
    headlines.add(document.silhouette.headline);
    signatures.add(document.signature_opportunities.map((item) => item.title).join("|"));
  }

  // Ten identities, ten of each. Any collision means two identities are
  // returning the same advice under different names, which is the
  // "repetitive output" failure mode by another route.
  assertEquals(palettes.size, STYLE_IDENTITIES.length);
  assertEquals(headlines.size, STYLE_IDENTITIES.length);
  assertEquals(signatures.size, STYLE_IDENTITIES.length);
});

Deno.test("every identity's output passes the response validator", () => {
  for (const identity of STYLE_IDENTITIES) {
    const document = composeStyleDna(contextWith({ primary_identity: identity }));
    parseStyleDnaDocument(JSON.stringify(document), STYLE_IDENTITIES);
  }
});

// ---------------------------------------------------------------------------
// Sparse input: specific, and honest about being sparse
// ---------------------------------------------------------------------------

Deno.test("an identity alone still produces concrete, non-empty advice", () => {
  const document = composeStyleDna(IDENTITY_ONLY);

  assertEquals(document.primary_identity, "quiet_luxury");
  assert(document.palette.preferred_colors.length >= 4);
  assert(document.silhouette.headline.length > 0);
  assert(document.signature_opportunities.length >= 3);
  assert(document.wardrobe_priorities.length >= 3);
  assert(document.summary.length > 0);

  // Concrete means naming garments a man could shop for, not adjectives.
  const titles = document.signature_opportunities.map((item) => item.title).join(" ").toLowerCase();
  assert(titles.includes("knit"), `expected a named garment, got: ${titles}`);
  assert(titles.includes("loafer") || titles.includes("blazer"));
});

Deno.test("an identity alone says out loud what it does not know", () => {
  const document = composeStyleDna(IDENTITY_ONLY);

  assertEquals(document.known_inputs.length, 1);
  assert(document.open_questions.length >= 4);
  const questions = document.open_questions.join(" ").toLowerCase();
  assert(questions.includes("work"), "should ask about the dress code");
  assert(questions.includes("measurement"), "should ask for a measurement");
  assert(questions.includes("goals"), "should ask about goals");
  // Nothing was measured, so nothing may be claimed as measured.
  assertEquals(document.measured_dimensions, []);
});

Deno.test("the silhouette says its advice is the direction's, not the user's, when nothing was measured", () => {
  const document = composeStyleDna(IDENTITY_ONLY);
  assert(
    document.silhouette.detail.includes("specific to you"),
    "a silhouette derived from no measurement must not read as measured",
  );
});

Deno.test("no identity and no dress code produces a null identity rather than an invented one", () => {
  const document = composeStyleDna(contextWith(null, null, null));

  // The alternative — picking a plausible identity — would put a fabricated
  // answer in the most prominent field on the §6.10 screen.
  assertEquals(document.primary_identity, null);
  assertEquals(document.secondary_influences, []);
  assertEquals(document.palette.preferred_colors, []);
  assertEquals(document.signature_opportunities, []);
  assertEquals(document.wardrobe_priorities, []);
  assert(document.summary.length > 0);
  assert(document.open_questions.length > 0);
  // Still a valid document — a thin result, not a broken one.
  parseStyleDnaDocument(JSON.stringify(document), STYLE_IDENTITIES);
});

Deno.test("a dress code alone infers an identity and labels it as inferred", () => {
  const document = composeStyleDna(contextWith(null, null, { dress_code: "business_formal" }));

  assertEquals(document.primary_identity, "executive");
  assert(document.identity_basis.includes("dress code"));
  assert(
    document.identity_basis.includes("starting point"),
    "an inferred identity must not be presented in the same voice as a chosen one",
  );
  // And it still asks the question that would settle it.
  assert(document.open_questions.some((q) => q.toLowerCase().includes("identities")));
});

// ---------------------------------------------------------------------------
// Richer input: the advice quotes the inputs that produced it
// ---------------------------------------------------------------------------

const RICH = contextWith(
  {
    primary_identity: "modern_heritage",
    secondary_identities: ["rugged_utility"],
    style_goals: ["build_complete_wardrobe", "shop_more_intelligently"],
    preferred_fit: "tailored",
    preference_vector: {
      comparisons_answered: 3,
      comparisons_offered: 3,
      dimensions: {
        formality: { score: 0.7, confidence: "moderate", observations: 2, agreement: 1 },
        colour_tolerance: { score: 0.8, confidence: "low", observations: 1, agreement: 1 },
        silhouette: { score: 0.6, confidence: "low", observations: 1, agreement: 1 },
      },
    },
  },
  {
    chest_cm: "104.00",
    waist_cm: "88.00",
    frame_scale: "tall",
    frame_scale_confidence: 0.8,
    appearance: { skin_undertone: "Warm" },
  },
  {
    dress_code: "business_casual",
    typical_week: "Mostly in an office",
    common_occasions: ["Client dinners"],
    travel_frequency: "A few times a year",
  },
);

Deno.test("a richer profile produces a longer, more specific result than a sparse one", () => {
  const sparse = composeStyleDna(IDENTITY_ONLY);
  const rich = composeStyleDna(RICH);

  assert(rich.known_inputs.length > sparse.known_inputs.length);
  assert(rich.open_questions.length < sparse.open_questions.length);
  assert(rich.silhouette.detail.length > sparse.silhouette.detail.length);
});

Deno.test("stated inputs are named back to the user in the advice", () => {
  const document = composeStyleDna(RICH);

  assert(document.silhouette.detail.includes("tailored fit"));
  const priorities = document.wardrobe_priorities.map((item) => item.reason).join(" ");
  assert(priorities.includes("Mostly in an office"));
  assert(priorities.includes("business casual"));
  assert(document.palette.rationale.includes("warm undertone"));
});

Deno.test("a deep complexion is not advised as if the wearer were fair", () => {
  const document = composeStyleDna(
    contextWith({ primary_identity: "quiet_luxury" }, {
      appearance: { skin_tone: "Deep", skin_undertone: "Warm" },
    }),
  );
  assert(document.palette.rationale.includes("deeper complexion"));
  assert(document.known_inputs.includes("your skin tone"));
});

Deno.test("the top priority comes from the week, not from the identity's generic list", () => {
  const document = composeStyleDna(RICH);
  assertEquals(document.wardrobe_priorities[0]?.rank, 1);
  assertEquals(document.wardrobe_priorities[0]?.title, "Cover the days you actually dress for");
});

Deno.test("a dress code adds a signature piece the identity alone would not call for", () => {
  const withoutDressCode = composeStyleDna(contextWith({ primary_identity: "modern_heritage" }));
  const withDressCode = composeStyleDna(
    contextWith({ primary_identity: "modern_heritage" }, null, { dress_code: "black_tie" }),
  );
  assert(
    withDressCode.signature_opportunities.length > withoutDressCode.signature_opportunities.length,
  );
  assert(
    withDressCode.signature_opportunities.some((item) => item.title.includes("dinner jacket")),
  );
});

Deno.test("a confident frame axis produces cut advice about the garment, not the wearer", () => {
  const document = composeStyleDna(RICH);
  assert(document.silhouette.detail.includes("Longer jacket lengths"));
  // Spec §2 and docs/14-frame-fit.md §4: the garment is the subject.
  const prose = [
    document.silhouette.detail,
    document.palette.rationale,
    document.summary,
    ...document.signature_opportunities.map((item) => `${item.title} ${item.reason}`),
    ...document.wardrobe_priorities.map((item) => `${item.title} ${item.reason}`),
  ].join(" ").toLowerCase();
  assert(!prose.includes("flatter"), "'flattering' is banned repo-wide");
  assert(!prose.includes("your build"));
  assert(!prose.includes("body type"));
  assert(!prose.includes("body shape"));
});

Deno.test("a low-confidence frame axis produces no cut advice at all", () => {
  const uncertain = composeStyleDna(contextWith({ primary_identity: "modern_heritage" }, {
    chest_cm: "104.00",
    frame_scale: "tall",
    frame_scale_confidence: 0.2,
  }));
  assert(!uncertain.silhouette.detail.includes("Longer jacket lengths"));
});

Deno.test("a quiz that contradicts the stated fit says so instead of averaging", () => {
  const document = composeStyleDna(contextWith({
    primary_identity: "minimalist",
    preferred_fit: "slim",
    preference_vector: {
      comparisons_answered: 4,
      comparisons_offered: 4,
      dimensions: {
        silhouette: { score: 0.9, confidence: "high", observations: 4, agreement: 1 },
      },
    },
  }));
  assert(document.silhouette.detail.includes("leaned looser than the fit you named"));
  assert(document.silhouette.detail.includes("start from what you said"));
});

// ---------------------------------------------------------------------------
// Colour handling
// ---------------------------------------------------------------------------

Deno.test("a colour-welcoming quiz adds the accents; a colour-averse one moves them to avoided", () => {
  const base = { primary_identity: "smart_casual" };
  const welcoming = composeStyleDna(contextWith({
    ...base,
    preference_vector: {
      dimensions: {
        colour_tolerance: { score: 0.9, confidence: "moderate", observations: 2, agreement: 1 },
      },
    },
  }));
  const averse = composeStyleDna(contextWith({
    ...base,
    preference_vector: {
      dimensions: {
        colour_tolerance: { score: -0.9, confidence: "moderate", observations: 2, agreement: 1 },
      },
    },
  }));

  assert(welcoming.palette.preferred_colors.includes("burgundy"));
  assert(!averse.palette.preferred_colors.includes("burgundy"));
  assert(averse.palette.avoided_colors.includes("burgundy"));
});

Deno.test("a single low-confidence colour answer is phrased as a starting point, not a fact", () => {
  const document = composeStyleDna(contextWith({
    primary_identity: "smart_casual",
    preference_vector: {
      dimensions: {
        colour_tolerance: { score: 1, confidence: "low", observations: 1, agreement: 1 },
      },
    },
  }));
  assert(document.palette.rationale.includes("as a starting point"));
  assert(!document.palette.rationale.includes("showed you welcome colour"));
});

// ---------------------------------------------------------------------------
// The four §6.10 summary scalars
// ---------------------------------------------------------------------------

Deno.test("the summary scalars are a read across everything, not the quiz alone", () => {
  const identityOnly = composeStyleDna(contextWith({ primary_identity: "executive" }));
  // Executive's baseline, untouched by anything else.
  assertEquals(identityOnly.formality_preference, "very_formal");
  assertEquals(identityOnly.logo_tolerance, 5);
  assertEquals(identityOnly.accessory_preference, "minimal");

  // The same identity with an ultra-casual dress code lands between the two:
  // what he wants and what the room requires carry equal weight.
  const withCasualWork = composeStyleDna(
    contextWith({ primary_identity: "executive" }, null, { dress_code: "ultra_casual" }),
  );
  assertNotEquals(withCasualWork.formality_preference, "very_formal");
  assertEquals(withCasualWork.formality_preference, "balanced");
});

Deno.test("a high-confidence quiz axis moves a tolerance, a low-confidence one barely does", () => {
  const build = (confidence: string, observations: number) =>
    composeStyleDna(contextWith({
      primary_identity: "smart_casual",
      preference_vector: {
        dimensions: {
          logo_tolerance: { score: 1, confidence, observations, agreement: 1 },
        },
      },
    })).logo_tolerance;

  const baseline =
    composeStyleDna(contextWith({ primary_identity: "smart_casual" })).logo_tolerance;
  const low = build("low", 1);
  const high = build("high", 4);

  assert(low > baseline);
  assert(high > low, "four agreeing comparisons must count for more than one");
  // But not enough to override the direction the user actually chose.
  assert(high < 100);
});

Deno.test("an axis with insufficient confidence moves nothing", () => {
  const baseline = composeStyleDna(contextWith({ primary_identity: "creative" }));
  const declined = composeStyleDna(contextWith({
    primary_identity: "creative",
    preference_vector: {
      dimensions: {
        trend_tolerance: {
          score: null,
          confidence: "insufficient",
          observations: 0,
          agreement: null,
        },
      },
    },
  }));
  assertEquals(declined.trend_tolerance, baseline.trend_tolerance);
  // ...but the axis is still recorded as asked, so it is not re-asked.
  assert(!declined.open_questions.join(" ").includes("how current you like things"));
});

Deno.test("only axes with a score are reported as measured", () => {
  const document = composeStyleDna(contextWith({
    primary_identity: "creative",
    preference_vector: {
      dimensions: {
        formality: { score: 0.4, confidence: "low", observations: 1, agreement: 1 },
        texture: { score: null, confidence: "insufficient", observations: 0, agreement: null },
      },
    },
  }));
  assertEquals(document.measured_dimensions, ["formality"]);
});

// ---------------------------------------------------------------------------
// Determinism and the provider wrapper
// ---------------------------------------------------------------------------

Deno.test("the same context always produces byte-identical output", () => {
  assertEquals(JSON.stringify(composeStyleDna(RICH)), JSON.stringify(composeStyleDna(RICH)));
});

Deno.test("the provider returns a schema-valid document and reports its version", async () => {
  const provider = new DeterministicStylistProvider();
  const result = await provider.complete({
    systemPrompt: "unused",
    contextPacket: RICH as unknown as Record<string, unknown>,
    messages: [],
    tools: [],
    responseSchema: {},
    maxOutputTokens: 2000,
    temperature: 0.4,
    stream: false,
    tier: "terra",
  }, { requestId: "r", userId: "u", timeoutMs: 1000 });

  assertEquals(result.finishReason, "stop");
  assertEquals(result.modelIdentifier, DETERMINISTIC_STYLIST_VERSION);
  assertEquals(result.toolCalls, []);
  parseStyleDnaDocument(result.message, STYLE_IDENTITIES);
});

Deno.test("the provider refuses to stream rather than faking it with one chunk", async () => {
  const provider = new DeterministicStylistProvider();
  let thrown: unknown = null;
  try {
    for await (
      const _chunk of provider.completeStream({
        systemPrompt: "unused",
        contextPacket: {},
        messages: [],
        tools: [],
        responseSchema: {},
        maxOutputTokens: 10,
        temperature: 0,
        stream: true,
        tier: "luna",
      }, { requestId: "r", userId: "u", timeoutMs: 1000 })
    ) {
      // Unreachable — the iterator throws on first pull.
    }
  } catch (err) {
    thrown = err;
  }
  assert(thrown instanceof ProviderError);
  assertEquals((thrown as ProviderError).retryable, false);
});
