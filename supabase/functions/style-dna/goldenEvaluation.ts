import type { StylistCompletionResult } from "../_shared/providers/stylistReasoning.ts";
import { buildStyleDnaContext, type StyleDnaContext } from "./context.ts";
import {
  STYLE_DNA_SYSTEM_PROMPT,
  STYLE_DNA_SYSTEM_PROMPT_VERSION,
  STYLE_IDENTITIES,
} from "./handler.ts";
import { parseStyleDnaDocument, type StyleDnaDocument, styleDnaResponseSchema } from "./schema.ts";
import type { StylistReasoningProvider } from "../_shared/providers/stylistReasoning.ts";

export interface StyleDnaGoldenCase {
  readonly id: string;
  readonly context: StyleDnaContext;
  readonly expectedIdentity: string | null;
  readonly requiresOpenQuestion: boolean;
  readonly expectedDimension?: string;
}

/** Synthetic profiles used by the live adapter quality check; no user data. */
export const STYLE_DNA_GOLDEN_CASES: readonly StyleDnaGoldenCase[] = [
  {
    id: "identity-only-quiet-luxury",
    context: buildStyleDnaContext(
      {
        primary_identity: "quiet_luxury",
        secondary_identities: [],
        style_goals: [],
        preference_vector: {},
      },
      null,
      null,
      "menswear_3_role",
    ),
    expectedIdentity: "quiet_luxury",
    requiresOpenQuestion: true,
  },
  {
    id: "sparse-no-identity",
    context: buildStyleDnaContext(null, null, null, "menswear_3_role"),
    expectedIdentity: null,
    requiresOpenQuestion: true,
  },
  {
    id: "measured-streetwear",
    context: buildStyleDnaContext(
      {
        primary_identity: "luxury_streetwear",
        secondary_identities: ["creative"],
        style_goals: ["build_a_versatile_wardrobe"],
        preferred_fit: "relaxed",
        preference_vector: {
          comparisons_answered: 2,
          comparisons_offered: 2,
          dimensions: {
            colour_tolerance: { score: 0.8, confidence: "low", observations: 2, agreement: 1 },
            formality: { score: 0.2, confidence: "low", observations: 2, agreement: 1 },
            silhouette: { score: 0.75, confidence: "low", observations: 2, agreement: 1 },
          },
        },
      },
      { height_value_cm: 180, weight_value_kg: 78 },
      {
        dress_code: "casual",
        typical_week: ["creative_work", "weekend"],
        common_occasions: ["casual_dinner"],
      },
      "menswear_3_role",
    ),
    expectedIdentity: "luxury_streetwear",
    requiresOpenQuestion: true,
    expectedDimension: "relaxed",
  },
];

export interface StyleDnaGoldenResult {
  readonly id: string;
  readonly modelIdentifier: string;
  readonly document: StyleDnaDocument | null;
  readonly passed: boolean;
  readonly failures: readonly string[];
}

export function evaluateStyleDnaGoldenOutput(
  testCase: StyleDnaGoldenCase,
  rawDocument: string,
  modelIdentifier: string,
): StyleDnaGoldenResult {
  let document: StyleDnaDocument;
  try {
    document = parseStyleDnaDocument(rawDocument, STYLE_IDENTITIES);
  } catch {
    return {
      id: testCase.id,
      modelIdentifier,
      document: null,
      passed: false,
      failures: ["provider response failed the Style DNA schema validator"],
    };
  }

  const failures: string[] = [];
  if (document.primary_identity !== testCase.expectedIdentity) {
    failures.push("identity did not preserve the supplied evidence");
  }
  if (testCase.requiresOpenQuestion && document.open_questions.length === 0) {
    failures.push("sparse profile did not name an open question");
  }
  if (
    testCase.expectedDimension &&
    !document.measured_dimensions.some((dimension) =>
      dimension.toLowerCase().includes(testCase.expectedDimension!.toLowerCase())
    ) &&
    !document.silhouette.detail.toLowerCase().includes(testCase.expectedDimension.toLowerCase())
  ) {
    failures.push("measured preference was not acknowledged");
  }
  return {
    id: testCase.id,
    modelIdentifier,
    document,
    passed: failures.length === 0,
    failures,
  };
}

/**
 * Runs the same synthetic profile set against any protocol implementation.
 * This can evaluate the real configured adapter; deterministic fixtures are
 * only the local regression baseline, not a substitute for the live pass.
 */
export async function runStyleDnaGoldenEvaluation(
  provider: StylistReasoningProvider,
  options: {
    readonly userId?: string;
    readonly requestIdPrefix?: string;
    readonly timeoutMs?: number;
  } = {},
): Promise<readonly StyleDnaGoldenResult[]> {
  const userId = options.userId ?? "00000000-0000-4000-8000-000000000000";
  const requestIdPrefix = options.requestIdPrefix ?? `style-dna-golden-${crypto.randomUUID()}`;
  const timeoutMs = options.timeoutMs ?? 20_000;
  const results: StyleDnaGoldenResult[] = [];

  for (const testCase of STYLE_DNA_GOLDEN_CASES) {
    const completion: StylistCompletionResult = await provider.complete({
      systemPrompt: STYLE_DNA_SYSTEM_PROMPT,
      contextPacket: testCase.context as unknown as Record<string, unknown>,
      messages: [],
      tools: [],
      responseSchema: styleDnaResponseSchema(STYLE_IDENTITIES),
      strictResponseSchema: true,
      maxOutputTokens: 2_000,
      temperature: 0.4,
      stream: false,
      tier: "terra",
    }, {
      requestId: `${requestIdPrefix}/${STYLE_DNA_SYSTEM_PROMPT_VERSION}/${testCase.id}`,
      userId,
      timeoutMs,
    });

    results.push(
      evaluateStyleDnaGoldenOutput(testCase, completion.message, completion.modelIdentifier),
    );
  }
  return results;
}
