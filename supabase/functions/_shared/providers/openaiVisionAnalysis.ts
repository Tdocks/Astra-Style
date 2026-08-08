// ============================================================================
// _shared/providers/openaiVisionAnalysis.ts
// ============================================================================
// Optional live `VisionAnalysisProvider` adapter (docs/08 §2.5 — OpenAI
// GPT-5.6 Luna). Constructed ONLY from `closet/index.ts` when
// `VISION_ANALYSIS_PROVIDER=openai` and `VISION_PROVIDER_API_KEY` are set.
// Never imported by handlers or tests that should stay offline.
//
// That key used to be read as `OPENAI_API_KEY` — a name in neither spec
// §25's per-capability scheme nor ADR 0004's vocabulary, and never set on
// the project, so this adapter had never once been constructed. See
// `closet/index.ts`'s header for the whole diagnosis.
//
// The pre-launch menswear-subcategory accuracy pilot (docs/08 §2.5) is a
// hard gate before this adapter serves real users — enabling it in a
// deploy does not satisfy that gate by itself.
//
// Vendor concepts (model ids, response shapes, finish reasons) stay inside
// this file. The handler only ever sees `GarmentAnalysisResult`.
// ============================================================================

import { ProviderError, type ProviderRequestContext } from "./types.ts";
import type {
  GarmentAnalysisRequest,
  GarmentAnalysisResult,
  ProviderCondition,
  ProviderPattern,
  VisionAnalysisProvider,
} from "./visionAnalysis.ts";

export interface OpenAIVisionAnalysisDeps {
  readonly apiKey: string;
  readonly model: string;
  /** Resolves a private storage path to image bytes the vendor can read. */
  readonly loadImageBytes: (storagePath: string) => Promise<Uint8Array>;
  readonly fetchImpl?: typeof fetch;
}

const RESULT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "category",
    "subcategory",
    "confidence",
    "primary_color_name",
    "secondary_color_names",
    "pattern",
    "material",
    "formality_score",
    "brand_guess",
    "normalized_title",
    "condition",
    "condition_confidence",
    "fields_below_confidence_threshold",
  ],
  properties: {
    category: { type: "string" },
    subcategory: { type: "string" },
    confidence: { type: "number" },
    primary_color_name: { type: "string" },
    secondary_color_names: { type: "array", items: { type: "string" } },
    pattern: {
      type: "string",
      enum: ["solid", "stripe", "check", "herringbone", "print", "texture-only"],
    },
    material: { type: "array", items: { type: "string" } },
    formality_score: { type: "number" },
    brand_guess: {
      anyOf: [
        {
          type: "object",
          additionalProperties: false,
          required: ["name", "confidence"],
          properties: {
            name: { type: "string" },
            confidence: { type: "number" },
          },
        },
        { type: "null" },
      ],
    },
    normalized_title: { type: "string" },
    condition: {
      type: "string",
      enum: ["excellent", "good", "fair", "worn", "damaged"],
    },
    condition_confidence: { type: "number" },
    fields_below_confidence_threshold: { type: "array", items: { type: "string" } },
    fit: { type: "string" },
    size: { type: "string" },
    seasonality: { type: "array", items: { type: "string" } },
    warmth_score: { type: "number" },
    water_resistance_score: { type: "number" },
  },
} as const;

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]!);
  }
  return btoa(binary);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function asString(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function asNumber(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is string => typeof entry === "string");
}

function mapPattern(raw: string): ProviderPattern {
  const allowed: ProviderPattern[] = [
    "solid",
    "stripe",
    "check",
    "herringbone",
    "print",
    "texture-only",
  ];
  return (allowed.includes(raw as ProviderPattern) ? raw : "solid") as ProviderPattern;
}

function mapCondition(raw: string): ProviderCondition {
  const allowed: ProviderCondition[] = ["excellent", "good", "fair", "worn", "damaged"];
  return (allowed.includes(raw as ProviderCondition) ? raw : "good") as ProviderCondition;
}

export class OpenAIVisionAnalysisProvider implements VisionAnalysisProvider {
  private readonly apiKey: string;
  private readonly model: string;
  private readonly loadImageBytes: (storagePath: string) => Promise<Uint8Array>;
  private readonly fetchImpl: typeof fetch;

  constructor(deps: OpenAIVisionAnalysisDeps) {
    this.apiKey = deps.apiKey;
    this.model = deps.model;
    this.loadImageBytes = deps.loadImageBytes;
    this.fetchImpl = deps.fetchImpl ?? fetch;
  }

  async analyzeGarment(
    request: GarmentAnalysisRequest,
    ctx: ProviderRequestContext,
  ): Promise<GarmentAnalysisResult> {
    const bytes = await this.loadImageBytes(request.imageStoragePath);
    const base64 = bytesToBase64(bytes);
    const hints = request.deviceHints;
    const system =
      "You are Astra Style's garment classifier. Return ONLY JSON matching the schema. " +
      "Classify menswear finely. Prefer device OCR text for brand/size over re-reading pixels. " +
      "Calibrate confidence honestly — a wrong high-confidence brand is worse than a low guess.";

    const userText = JSON.stringify({
      device_hints: hints ?? null,
      instruction: "Classify the garment in the attached image.",
    });

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), ctx.timeoutMs);
    try {
      const response = await this.fetchImpl("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        signal: controller.signal,
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.apiKey}`,
          ...(ctx.idempotencyKey ? { "Idempotency-Key": ctx.idempotencyKey } : {}),
        },
        body: JSON.stringify({
          model: this.model,
          // No `temperature`. This asked for 0.2 — determinism matters for a
          // classifier, and a reproducible reading is the whole point of the
          // confidence calibration below. The reasoning models reject it
          // outright: HTTP 400, "Unsupported value: 'temperature' does not
          // support 0.2 with this model. Only the default (1) value is
          // supported." Sending it fails the entire request, so the choice is
          // not "less deterministic" versus "more" — it is a working analyser
          // versus none.
          //
          // Determinism is bought elsewhere instead: `strict: true` on the JSON
          // schema pins the shape, and the system prompt pins the calibration.
          // Do not add this back when a future model accepts it again without
          // first checking that the pinned model still does — this failure was
          // invisible from the endpoint, because the adapter degraded honestly
          // and returned "New garment" at 0.2 confidence rather than throwing.
          response_format: {
            type: "json_schema",
            json_schema: {
              name: "garment_analysis",
              strict: true,
              schema: RESULT_SCHEMA,
            },
          },
          messages: [
            { role: "system", content: system },
            {
              role: "user",
              content: [
                { type: "text", text: userText },
                {
                  type: "image_url",
                  image_url: { url: `data:image/jpeg;base64,${base64}` },
                },
              ],
            },
          ],
        }),
      });

      if (response.status === 429) {
        throw new ProviderError("RATE_LIMITED", true, "Vision provider rate limited.", 429);
      }
      if (response.status === 401 || response.status === 403) {
        throw new ProviderError(
          "AUTH_FAILED",
          false,
          "Vision provider auth failed.",
          response.status,
        );
      }
      if (!response.ok) {
        throw new ProviderError(
          "PROVIDER_UNAVAILABLE",
          response.status >= 500,
          `Vision provider returned ${response.status}.`,
          response.status,
        );
      }

      const json: unknown = await response.json();
      const root = asRecord(json);
      const choices = root?.["choices"];
      const firstChoice = Array.isArray(choices) ? asRecord(choices[0]) : null;
      const message = asRecord(firstChoice?.["message"]);
      const content = message?.["content"];
      if (typeof content !== "string") {
        throw new ProviderError("INVALID_INPUT", false, "Vision provider returned no content.");
      }
      let parsed: unknown;
      try {
        parsed = JSON.parse(content);
      } catch {
        throw new ProviderError(
          "INVALID_INPUT",
          false,
          "Vision provider returned non-JSON content.",
        );
      }
      const body = asRecord(parsed);
      if (!body) {
        throw new ProviderError(
          "INVALID_INPUT",
          false,
          "Vision provider returned a non-object payload.",
        );
      }

      const brandRaw = body["brand_guess"];
      const brandObj = asRecord(brandRaw);
      const brandGuess = brandObj
        ? { name: asString(brandObj["name"]), confidence: asNumber(brandObj["confidence"], 0) }
        : null;

      const primary = asString(body["primary_color_name"], "navy");
      const secondary = asStringArray(body["secondary_color_names"]);
      const seasonality = asStringArray(body["seasonality"]);
      const fit = asString(body["fit"]);
      const size = asString(body["size"]);

      return {
        category: asString(body["category"], hints?.approximateCategory ?? "top"),
        subcategory: asString(body["subcategory"], "Garment"),
        confidence: asNumber(body["confidence"], 0.5),
        colorLch: { l: 50, c: 20, h: 240 },
        secondaryColorsLch: [],
        pattern: mapPattern(asString(body["pattern"], "solid")),
        material: asStringArray(body["material"]),
        formalityAnchorLow: { label: "casual", score: 20 },
        formalityAnchorHigh: { label: "smart_casual", score: 45 },
        formalityBlendFraction: 0.5,
        formalityScore: Math.round(asNumber(body["formality_score"], 40)),
        brandGuess: brandGuess && brandGuess.name.length > 0 ? brandGuess : null,
        normalizedTitle: asString(body["normalized_title"], "Garment"),
        condition: mapCondition(asString(body["condition"], "good")),
        conditionConfidence: asNumber(body["condition_confidence"], 0.5),
        fieldsBelowConfidenceThreshold: asStringArray(body["fields_below_confidence_threshold"]),
        fitGuess: fit ? { value: fit, confidence: 0.6 } : undefined,
        sizeGuess: size ? { value: size, confidence: 0.6 } : undefined,
        seasonality: seasonality.map((value) => ({ value, confidence: 0.7 })),
        warmthScore: typeof body["warmth_score"] === "number"
          ? { value: Math.round(body["warmth_score"]), confidence: 0.65 }
          : undefined,
        waterResistanceScore: typeof body["water_resistance_score"] === "number"
          ? { value: Math.round(body["water_resistance_score"]), confidence: 0.65 }
          : undefined,
        primaryColorName: { value: primary, confidence: 0.85 },
        secondaryColorNames: secondary.map((value) => ({ value, confidence: 0.65 })),
      };
    } catch (err) {
      if (err instanceof ProviderError) {
        throw err;
      }
      if (err instanceof DOMException && err.name === "AbortError") {
        throw new ProviderError("TIMEOUT", true, "Vision provider timed out.");
      }
      throw new ProviderError(
        "UNKNOWN",
        true,
        err instanceof Error ? err.message : "Vision provider failed.",
      );
    } finally {
      clearTimeout(timer);
    }
  }

  removeBackground(
    _imageStoragePath: string,
    _ctx: ProviderRequestContext,
  ): Promise<{ resultStoragePath: string }> {
    return Promise.reject(
      new ProviderError(
        "INVALID_INPUT",
        false,
        "Background removal is not implemented on the OpenAI vision adapter (P3-SCAN-10).",
      ),
    );
  }
}
