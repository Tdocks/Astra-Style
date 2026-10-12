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
import { resolveGarmentPattern } from "./garmentPattern.ts";
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

/**
 * Exported for `openaiVisionAnalysis_test.ts` only. Nothing else should read
 * it — vendor request shapes stay in this file per the header — but the
 * invariants this schema has to satisfy are not checkable any other way, and
 * every one of them was discovered by an HTTP 400 against a live endpoint
 * during the `docs/08` §2.5 pilot gate rather than by anything in CI.
 */
export const RESULT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "construction_evidence",
    "category",
    "subcategory",
    "confidence",
    "primary_color_name",
    "secondary_color_names",
    "pattern_evidence",
    "pattern",
    "material",
    "formality_score",
    "brand_guess",
    "normalized_title",
    "condition",
    "condition_confidence",
    "fields_below_confidence_threshold",
    // The five below are the ones the model is allowed not to know. They are
    // listed here anyway because `strict: true` rejects a schema whose
    // `required` is not every key in `properties` — optionality is expressed
    // by a nullable type, not by omission from this list. Getting that wrong
    // fails the whole request with HTTP 400, not the one field.
    "fit",
    "size",
    "seasonality",
    "warmth_score",
    "water_resistance_score",
  ],
  properties: {
    construction_evidence: {
      type: "string",
      description: "Before category, describe visible collar, closure/placket, cuffs, hem, " +
        "pockets and lining/structure in one short sentence. A shirt has a shirt collar and " +
        "narrow center placket, often sleeve cuffs; a blazer has a tailored lapel/rolled opening " +
        "and jacket structure. An unbuttoned shirt collar is not evidence of blazer lapels. " +
        "Do not infer a blazer from ornate fabric or a hanger; state uncertainty if construction is hidden.",
    },
    // Closed vocabulary, because `closet/mapper.ts` has one and free text does
    // not survive the trip. Asked for a bare string this returned "menswear
    // top" — a better description of the garment than "top", and worthless:
    // it misses `CATEGORIES`, falls to the device-hint branch at confidence
    // 0.4, and trips `flags.add("category")`. The review screen would then ask
    // the user to confirm a category the model had in fact identified with
    // 0.95 confidence. Degradation paths should fire when something is
    // genuinely uncertain, not when two vocabularies disagree about wording.
    category: {
      type: "string",
      enum: [
        "top",
        "bottom",
        "outerwear",
        "shoes",
        "accessory",
        "watch",
        "fragrance",
        "dress",
        "skirt",
      ],
      description: "The garment layer: coats, coatigans, blazers, jackets and long substantial " +
        "belted/open-front outer-layer cardigans are outerwear. Lightweight waist-length " +
        "knit cardigans are top. Classify by construction and length, not knitted material alone.",
    },
    // Free text on purpose — this is the one field where specificity is the
    // point, and nothing downstream matches it against a vocabulary.
    subcategory: { type: "string" },
    // 0-1, and stated explicitly because the sibling attribute scores are
    // 0-100. Naming the 0-100 convention in the system prompt without naming
    // this one moved every confidence in the response onto 0-100 as well —
    // 0.93 became 93 — which silently defeats `mapper.ts`'s `< 0.6` gate,
    // the one check standing between a low-confidence reading and a
    // confidently wrong closet item.
    confidence: {
      type: "number",
      description: "Probability in 0-1 that the category and subcategory are right. Not 0-100.",
    },
    primary_color_name: {
      type: "string",
      description: "Dominant garment BODY color by visible area, excluding shadows/background. " +
        "Use white for neutral off-white; retain ivory/cream for warm yellow-beige whites. Compare " +
        "the garment with nearby neutral white surfaces when available, without using their color as " +
        "the garment color. Black for near-black " +
        "fabric rather than a small green cast. For checks use the largest base area, not the " +
        "brightest stripe. Use a stable everyday color name, not lighting-dependent descriptors.",
    },
    secondary_color_names: { type: "array", items: { type: "string" } },
    pattern_evidence: {
      type: "string",
      description:
        "Before selecting pattern, describe in one short sentence the visible colored motifs " +
        "inside the garment outline: shapes, line directions and repetition, or their absence. " +
        "Ignore motifs outside the garment. Describe observed pixels, not a guessed material " +
        "or the pattern enum label. Distinguish printed color changes from shadows, wrinkles " +
        "and single-color surface texture.",
    },
    pattern: {
      type: "string",
      description:
        "Pattern on the garment itself, excluding the floor, bedding, wall, hanger and other " +
        "objects. Use the dominant garment-body design; a small isolated brand logo does not " +
        "make an otherwise plain garment a print. solid includes plain fabric, plain leather, " +
        "isolated small logos and color-block panels; ignore seams, wrinkles, leather creases " +
        "and lighting highlights. " +
        "stripe: repeated parallel colored lines. check: crossing colored lines, plaid, " +
        "tartan, gingham, houndstooth (broken checks) or buffalo checks. print: camouflage, " +
        "large graphics/lettering, floral " +
        "or geometric colored motifs that are not stripes/checks. herringbone: genuine " +
        "repeated V-shaped weave. texture-only: relief/knit/weave without a colored motif; " +
        "only use it for clearly visible structural ribbing, cable knitting or an identifiable " +
        "weave across the body, not ordinary leather grain or creases. Never use it merely " +
        "because a printed or plaid fabric also has texture.",
      enum: ["solid", "stripe", "check", "herringbone", "print", "texture-only"],
    },
    material: { type: "array", items: { type: "string" } },
    // The scale has to be in the schema, because the model will not guess it.
    // Asked for a bare "formality_score" this returned 3 for a casual camp
    // shirt — correct on an unstated 0-10 scale, and a garment barely more
    // formal than pyjamas on the 0-100 scale that `closet_items.formality_score`
    // actually enforces. The check constraint accepts 3 happily. Nothing would
    // have caught it downstream; it would simply have made every outfit
    // containing a scanned item score badly on the §10 formality subscore.
    //
    // The anchors are `docs/05` §3's table, thinned to the rungs a classifier
    // can actually discriminate. Keep them in sync with that table.
    formality_score: {
      type: "number",
      description: "Formality on a 0-100 scale (integer). Anchors: 0 graphic tee or " +
        "athletic shorts; 20 heavyweight tee or distressed denim; 30 casual " +
        "flannel or dark-wash jeans; 40 knit polo or relaxed chino; 50 casual " +
        "button-down worn untucked; 60 fitted oxford or wool dress trouser; " +
        "70 dress shirt without a tie; 80 dress shirt with a tie or matched " +
        "suit; 100 white-tie formalwear. Not a 0-10 scale.",
    },
    brand_guess: {
      anyOf: [
        {
          type: "object",
          additionalProperties: false,
          required: ["name", "confidence"],
          properties: {
            name: { type: "string" },
            confidence: {
              type: "number",
              description: "Probability in 0-1 that this brand is right. Not 0-100.",
            },
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
    condition_confidence: {
      type: "number",
      description: "Probability in 0-1 that the condition is right. Not 0-100.",
    },
    fields_below_confidence_threshold: { type: "array", items: { type: "string" } },
    // Nullable, and meant to be. A garment photographed folded has no legible
    // fit; a garment with the label turned away has no legible size. `null`
    // here is the model saying so, and the parser below turns it back into an
    // absent field rather than a defaulted one — the same bargain as
    // `brand_guess` above, and the reason the request asks for these at all.
    fit: {
      anyOf: [{
        type: "string",
        enum: ["slim", "tailored", "regular", "relaxed", "oversized"],
      }, { type: "null" }],
      description: "Cut of the garment, or null if the photograph does not show it.",
    },
    size: { anyOf: [{ type: "string" }, { type: "null" }] },
    // Closed for the same reason: `mapper.ts` filters against `SEASONS` and
    // drops anything else silently. "early fall" was a real answer, and it
    // vanished — the item simply came back with one fewer season and no
    // record that a reading had been discarded.
    seasonality: {
      anyOf: [{
        type: "array",
        items: {
          type: "string",
          enum: ["spring", "summer", "fall", "winter", "all_season"],
        },
      }, { type: "null" }],
      description: "Seasons the garment suits. Use all_season only when it genuinely " +
        "suits all four; otherwise list the individual seasons.",
    },
    // Both 0-100, both for the same reason as formality_score, and both got
    // the same 0-10 answer before the scale was stated: warmth 2 and water
    // resistance 0 for a mid-weight cotton shirt. `docs/05` §2.5 pins the
    // meaning of the endpoints — warmth is read as an ideal wearing
    // temperature, so an understated value does not merely rank low, it tells
    // the weather subscore the garment belongs in a heatwave.
    warmth_score: {
      anyOf: [{ type: "number" }, { type: "null" }],
      description: "Insulation on a 0-100 scale (integer), or null if not determinable. " +
        "0 means ideal at about 30C (linen camp shirt); 50 means ideal at " +
        "about 12C (mid-weight knit); 100 means ideal at about -5C (heavy " +
        "down parka). Not a 0-10 scale.",
    },
    water_resistance_score: {
      anyOf: [{ type: "number" }, { type: "null" }],
      description: "Water resistance on a 0-100 scale (integer), or null if not " +
        "determinable. 0 is untreated cotton or suede; 30 is the threshold " +
        "below which a garment is treated as unsuitable for rain; 70 is a " +
        "coated or waxed shell; 100 is a sealed hardshell. Not a 0-10 scale.",
    },
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
      "First identify the main garment's outline and inspect only its fabric area. " +
      "Write construction_evidence before category. Distinguish button-up shirts from blazers " +
      "using closure, collar and cuffs: patterned fabric, an open collar, or hanging shape " +
      "alone does not imply a blazer. Do not hallucinate lapels or suit pockets. " +
      "Write pattern_evidence from that region before selecting the matching pattern enum. " +
      "Exclude patterns/colors on bedding, rugs, floors, walls, hangers and nearby garments. " +
      "Cross-check pattern against the visible garment and your subcategory description: " +
      "a camouflage/graphic garment is print; plaid/checked flannel is check, not texture-only. " +
      "Distinguish colored motifs from tactile fabric texture; a patterned fabric can have both, " +
      "but report the colored motif. Color-block panels alone are solid. If the garment pattern " +
      "is absent across the body, use solid even with a small chest logo, plain leather grain " +
      "or creases. Houndstooth is check; a genuine chevron weave is herringbone. If the pattern " +
      "cannot be distinguished from background or fabric detail, include pattern in " +
      "fields_below_confidence_threshold rather than implying certainty. " +
      "For boots inspect actual repeated colored motifs: seams, panels, leather creases and " +
      "reflections are solid, never print. Small same-color embroidered stitching on the shaft " +
      "does not make a plain leather boot a print; use the dominant body pattern. Ornamental " +
      "repeated colored loops, medallions or paisley on coats are print, not checks. For knit coats inspect whether repeated contrasting " +
      "yarn forms checks/houndstooth rather than calling every knitted motif print. " +
      "Classify menswear finely. Prefer device OCR text for brand/size over re-reading pixels. " +
      "Calibrate confidence honestly — a wrong high-confidence brand is worse than a low guess. " +
      "Two different numeric conventions live in this schema and mixing them is the most " +
      "damaging error you can make: every *confidence* is a probability in 0-1, while the " +
      "attribute scores (formality, warmth, water resistance) are 0-100. Read each field's " +
      "description before answering.";

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
                  image_url: { url: `data:image/jpeg;base64,${base64}`, detail: "high" },
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

      const rawPrimary = asString(body["primary_color_name"], "navy");
      const primary = /^off[- ]white$/i.test(rawPrimary.trim()) ? "white" : rawPrimary;
      const secondary = asStringArray(body["secondary_color_names"]);
      const seasonality = asStringArray(body["seasonality"]);
      const fit = asString(body["fit"]);
      const size = asString(body["size"]);
      const rawCategory = asString(body["category"], hints?.approximateCategory ?? "top");
      const subcategory = asString(body["subcategory"], "Garment");
      const category =
        rawCategory === "top" && /\b(coat|coatigan|blazer|jacket)\b/i.test(subcategory)
          ? "outerwear"
          : rawCategory;
      const pattern = resolveGarmentPattern(
        mapPattern(asString(body["pattern"], "solid")),
        asString(body["pattern_evidence"]),
        category,
      );
      const uncertainFields = new Set(asStringArray(body["fields_below_confidence_threshold"]));
      if (pattern.corrected) uncertainFields.add("pattern");
      if (category !== rawCategory) uncertainFields.add("category");

      return {
        category,
        subcategory,
        confidence: asNumber(body["confidence"], 0.5),
        // No colorLch, deliberately. This adapter never sees a pixel value —
        // it asks the model for a colour *name* and hands that to the mapper,
        // which is the only colour the closet actually stores. What stood here
        // was a hardcoded `{ l: 50, c: 20, h: 240 }`, returned for every
        // garment ever scanned. See the field's comment in `visionAnalysis.ts`.
        pattern: pattern.value,
        material: asStringArray(body["material"]),
        formalityAnchorLow: { label: "casual", score: 20 },
        formalityAnchorHigh: { label: "smart_casual", score: 45 },
        formalityBlendFraction: 0.5,
        formalityScore: Math.round(asNumber(body["formality_score"], 40)),
        brandGuess: brandGuess && brandGuess.name.length > 0 ? brandGuess : null,
        normalizedTitle: asString(body["normalized_title"], "Garment"),
        condition: mapCondition(asString(body["condition"], "good")),
        conditionConfidence: asNumber(body["condition_confidence"], 0.5),
        fieldsBelowConfidenceThreshold: [...uncertainFields],
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
