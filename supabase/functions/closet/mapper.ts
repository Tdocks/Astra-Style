// ============================================================================
// closet/mapper.ts
// ============================================================================
// Maps `GarmentAnalysisResult` (docs/08 §2, provider-shaped) onto the wire
// `ClosetItemAnalysisResultDTO` the iOS review screen decodes. Kept out of
// handler.ts so the provider-swap test can assert identical wire shapes
// across two unrelated providers without caring about their internals.
//
// Deliberate divergences from docs/08 (see ClosetItemAnalysisResult.swift
// Decisions 1–3): LCh → colour names; patternScale dropped; formality
// anchors collapsed to the resolved score; fit/size/seasonality/warmth/
// water-resistance added because the master spec and closet_items columns
// require them.
// ============================================================================

import type { GarmentAnalysisResult } from "../_shared/providers/visionAnalysis.ts";
import type { ClosetItemAnalysisResultDTO, DeviceHints, FieldSuggestionDTO } from "./schema.ts";

export const CATEGORIES = new Set([
  "top",
  "bottom",
  "outerwear",
  "shoes",
  "accessory",
  "watch",
  "fragrance",
]);

const PATTERNS: Record<string, string> = {
  solid: "solid",
  stripe: "stripe",
  check: "check",
  herringbone: "textured",
  print: "print",
  "texture-only": "textured",
};

const CONDITIONS: Record<string, string> = {
  excellent: "like_new",
  good: "good",
  fair: "fair",
  worn: "worn",
  damaged: "worn",
};

export const FITS = new Set(["slim", "tailored", "regular", "relaxed", "oversized"]);
export const SEASONS = new Set(["spring", "summer", "fall", "winter", "all_season"]);

function suggestion<T>(value: T, confidence: number): FieldSuggestionDTO<T> {
  return { value, confidence };
}

function resolveCategory(
  providerCategory: string,
  providerConfidence: number,
  hints?: DeviceHints,
): FieldSuggestionDTO<string> {
  const lower = providerCategory.toLowerCase();
  if (CATEGORIES.has(lower)) {
    // The provider's own number, not a constant. This used to be a
    // hardcoded 0.91, which meant a category the provider had *guessed* was
    // presented to the user as one it had read — the mock defaults to "top"
    // whenever device hints carry no category, which on a real deploy is
    // every single request, and the live OpenAI adapter's measured
    // confidence was being flattened the same way. `flags.add("category")`
    // below can only fire if this number is allowed through.
    return suggestion(lower, providerConfidence);
  }
  const approx = hints?.approximateCategory?.toLowerCase();
  if (approx && CATEGORIES.has(approx)) {
    // docs/08 §2.2 degraded path: promote the device hint.
    return suggestion(approx, 0.4);
  }
  return suggestion("top", 0.3);
}

/**
 * Builds the wire DTO. `ocrText` is echoed from device hints so the review
 * screen can show what brand/size guesses were derived from.
 */
export function mapProviderResultToWire(
  result: GarmentAnalysisResult,
  opts: { deviceHints?: DeviceHints; normalizedImagePath?: string },
): ClosetItemAnalysisResultDTO {
  const category = resolveCategory(result.category, result.confidence, opts.deviceHints);
  const flags = new Set(result.fieldsBelowConfidenceThreshold);

  const brand = result.brandGuess
    ? suggestion(result.brandGuess.name, result.brandGuess.confidence)
    : undefined;
  if (brand && brand.confidence < 0.6) {
    flags.add("brand");
  }

  const patternRaw = PATTERNS[result.pattern] ?? "other";
  const conditionRaw = CONDITIONS[result.condition] ?? "good";

  const primaryColor = result.primaryColorName
    ? suggestion(result.primaryColorName.value, result.primaryColorName.confidence)
    : suggestion("navy", 0.4);

  const secondaryColors = (result.secondaryColorNames ?? []).map((entry) =>
    suggestion(entry.value, entry.confidence)
  );

  const material = result.material.map((value, index) =>
    suggestion(value, index === 0 ? 0.85 : 0.55)
  );
  for (const entry of material) {
    if (entry.confidence < 0.6) {
      flags.add("material");
    }
  }

  const fitValue = result.fitGuess?.value.toLowerCase();
  const fit = fitValue && FITS.has(fitValue)
    ? suggestion(fitValue, result.fitGuess!.confidence)
    : undefined;

  const size = result.sizeGuess
    ? suggestion(result.sizeGuess.value, result.sizeGuess.confidence)
    : undefined;

  const seasonality = (result.seasonality ?? [])
    .filter((entry) => SEASONS.has(entry.value))
    .map((entry) => suggestion(entry.value, entry.confidence));

  const ocrText = opts.deviceHints?.detectedText.length
    ? opts.deviceHints.detectedText.join("\n")
    : undefined;

  if (category.confidence < 0.6) {
    flags.add("category");
  }
  if (result.confidence < 0.6) {
    flags.add("subcategory");
  }
  if (result.conditionConfidence < 0.6) {
    flags.add("condition");
  }

  const dto: ClosetItemAnalysisResultDTO = {
    name: suggestion(result.normalizedTitle, Math.min(0.95, result.confidence + 0.05)),
    brand,
    category,
    subcategory: suggestion(result.subcategory, result.confidence),
    primary_color: primaryColor,
    secondary_colors: secondaryColors,
    pattern: suggestion(patternRaw, 0.9),
    material,
    size,
    fit,
    condition: suggestion(conditionRaw, result.conditionConfidence),
    seasonality,
    formality_score: suggestion(result.formalityScore, 0.75),
    warmth_score: result.warmthScore
      ? suggestion(result.warmthScore.value, result.warmthScore.confidence)
      : undefined,
    water_resistance_score: result.waterResistanceScore
      ? suggestion(
        result.waterResistanceScore.value,
        result.waterResistanceScore.confidence,
      )
      : undefined,
    normalized_image_path: opts.normalizedImagePath,
    ocr_text: ocrText,
    fields_below_confidence_threshold: [...flags].sort(),
  };
  return dto;
}

/**
 * docs/08 §2.2 degraded path: when the provider is exhausted, promote
 * device hints and mark every inferred field low-confidence.
 */
export function degradedResultFromHints(hints?: DeviceHints): ClosetItemAnalysisResultDTO {
  // "unknown" is not a category, so the provider confidence passed here is
  // never read — the hint branch or the "top" default answers instead, and
  // the line below pins the result at the degraded value regardless.
  const category = resolveCategory("unknown", 0.35, hints);
  category.confidence = 0.35;
  const primary = hints?.dominantColorsRgb[0] ? suggestion("navy", 0.35) : suggestion("navy", 0.2);
  return {
    name: suggestion("New garment", 0.2),
    category,
    primary_color: primary,
    secondary_colors: [],
    material: [],
    seasonality: [],
    ocr_text: hints?.detectedText.length ? hints.detectedText.join("\n") : undefined,
    fields_below_confidence_threshold: [
      "name",
      "category",
      "subcategory",
      "primary_color",
      "material",
      "condition",
      "pattern",
      "fit",
      "size",
      "formality_score",
    ],
  };
}
