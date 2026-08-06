// ============================================================================
// _shared/providers/mockVisionAnalysis.ts
// ============================================================================
// Deterministic `VisionAnalysisProvider` for local development, Deno tests,
// and any deploy that has not flipped on the live OpenAI adapter. Derives
// a plausible menswear classification from device hints (OCR text, dominant
// colours, approximate category) so the review-screen path is exercisable
// without a vendor key and without burning vision quota.
//
// A provider swap must not change handler.ts, the wire DTO, or anything in
// ios/ — constructing this vs. the OpenAI adapter is `closet/index.ts`'s
// only job (ADR 0004).
// ============================================================================

import type { ProviderRequestContext } from "./types.ts";
import type {
  GarmentAnalysisRequest,
  GarmentAnalysisResult,
  VisionAnalysisProvider,
} from "./visionAnalysis.ts";

const CATEGORIES = new Set([
  "top",
  "bottom",
  "outerwear",
  "shoes",
  "accessory",
  "watch",
  "fragrance",
]);

/**
 * Resolve a category from the device hints, and say whether it was actually
 * read or merely defaulted.
 *
 * `isFallback` is not decoration. No production iOS code sets
 * `approximateCategory` — `DeviceHintsExtraction` produces colours and OCR
 * text, and nothing computes a category — so on a real deploy **every**
 * request lands on the `"top"` default. Returning that at the same 0.91
 * confidence as a read category is how a man photographing a pair of shoes
 * gets told, with no hedge anywhere on the screen, that he owns a navy
 * crewneck sweater.
 *
 * This codebase's rule is that absent is honest and a confounded reading is
 * not. A default is not a reading, and the caller marks it as such.
 */
function resolveCategory(
  hints?: GarmentAnalysisRequest["deviceHints"],
): { category: string; isFallback: boolean } {
  const approx = hints?.approximateCategory?.toLowerCase();
  if (approx && CATEGORIES.has(approx)) {
    return { category: approx, isFallback: false };
  }
  return { category: "top", isFallback: true };
}

function hexToLch(hex: string): { l: number; c: number; h: number } {
  // Deterministic stub: we do not need a real colour-science conversion for
  // the mock. The wire mapper prefers `primaryColorName` when present.
  const cleaned = hex.replace("#", "").toLowerCase();
  let hash = 0;
  for (let i = 0; i < cleaned.length; i++) {
    hash = (hash * 31 + cleaned.charCodeAt(i)) >>> 0;
  }
  return {
    l: 30 + (hash % 50),
    c: 10 + (hash % 40),
    h: hash % 360,
  };
}

function guessBrand(detectedText: readonly string[]): { name: string; confidence: number } | null {
  const joined = detectedText.join(" ").toUpperCase();
  const known = ["UNIQLO", "NIKE", "ADIDAS", "J.CREW", "EVERLANE", "A.P.C.", "COS", "ZARA"];
  for (const brand of known) {
    if (joined.includes(brand.replace(".", ""))) {
      return {
        name: brand === "A.P.C." ? "A.P.C." : brand.charAt(0) + brand.slice(1).toLowerCase(),
        confidence: 0.72,
      };
    }
    if (joined.includes(brand)) {
      return { name: brand, confidence: 0.78 };
    }
  }
  // Low-confidence placeholder when OCR exists but matches nothing — the
  // review screen must mark brand as a guess (docs/08 §2.1).
  if (detectedText.length > 0) {
    return { name: detectedText[0]!.slice(0, 24), confidence: 0.35 };
  }
  return null;
}

function guessSize(
  detectedText: readonly string[],
): { value: string; confidence: number } | undefined {
  const joined = detectedText.join(" ");
  const match = joined.match(/\b(XXS|XS|S|M|L|XL|XXL|XXXL|\d{2})\b/i);
  if (!match || match[1] === undefined) {
    return undefined;
  }
  return { value: match[1].toUpperCase(), confidence: 0.74 };
}

function colorNameFromHex(hex: string): string {
  const cleaned = hex.replace("#", "").toLowerCase();
  if (cleaned.length < 6) {
    return "navy";
  }
  const r = parseInt(cleaned.slice(0, 2), 16);
  const g = parseInt(cleaned.slice(2, 4), 16);
  const b = parseInt(cleaned.slice(4, 6), 16);
  if (Number.isNaN(r) || Number.isNaN(g) || Number.isNaN(b)) {
    return "navy";
  }
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  if (max < 40) return "black";
  if (min > 210) return "white";
  if (max - min < 25) {
    if (max < 100) return "charcoal";
    if (max < 170) return "grey";
    return "cream";
  }
  if (b > r && b > g) return "navy";
  if (r > g && r > b) return r > 160 && g > 80 ? "burgundy" : "brown";
  if (g > r && g > b) return "olive";
  return "navy";
}

/**
 * Deterministic mock. Safe to share across requests in one isolate — no
 * mutable state, no network, no clock.
 */
export class MockVisionAnalysisProvider implements VisionAnalysisProvider {
  analyzeGarment(
    request: GarmentAnalysisRequest,
    ctx: ProviderRequestContext,
  ): Promise<GarmentAnalysisResult> {
    void ctx.idempotencyKey;
    const hints = request.deviceHints;
    const { category, isFallback: categoryIsFallback } = resolveCategory(hints);
    const colors = hints?.dominantColorsRgb ?? [];
    const primaryHex = colors[0] ?? "#1B2A4A";
    const secondaryHexes = colors.slice(1, 3);
    const brandGuess = guessBrand(hints?.detectedText ?? []);
    const sizeGuess = guessSize(hints?.detectedText ?? []);
    const primaryName = colorNameFromHex(primaryHex);
    const subcategoryByCategory: Record<string, string> = {
      top: "Crewneck sweater",
      bottom: "Chino",
      outerwear: "Field jacket",
      shoes: "Sneaker",
      accessory: "Belt",
      watch: "Dress watch",
      fragrance: "Eau de parfum",
    };
    const subcategory = subcategoryByCategory[category] ?? "Garment";
    const title = brandGuess
      ? `${brandGuess.name} ${subcategory}`
      : `${primaryName.charAt(0).toUpperCase()}${primaryName.slice(1)} ${subcategory}`;

    const lowFields: string[] = [];
    if (brandGuess && brandGuess.confidence < 0.6) {
      lowFields.push("brand");
    }
    if (sizeGuess && sizeGuess.confidence < 0.6) {
      lowFields.push("size");
    }
    // A defaulted category is a guess about the garment, and `subcategory`
    // is derived from it, so both are marked. `ClosetItemAnalysisResult`
    // unions this list with its own computed one, so marking here can only
    // ever add a hedge — never remove one.
    if (categoryIsFallback) {
      lowFields.push("category", "subcategory");
    }

    const result: GarmentAnalysisResult = {
      category,
      subcategory,
      // Below `AnalysisConfidence.lowConfidenceThreshold` (0.6) when the
      // category was defaulted rather than read, so the review screen shows
      // "Kyra isn't sure — check this" instead of a confident wrong answer.
      confidence: categoryIsFallback ? 0.35 : 0.91,
      colorLch: hexToLch(primaryHex),
      secondaryColorsLch: secondaryHexes.map(hexToLch),
      pattern: "solid",
      material: ["cotton"],
      formalityAnchorLow: { label: "smart_casual", score: 35 },
      formalityAnchorHigh: { label: "business_casual", score: 55 },
      formalityBlendFraction: 0.25,
      formalityScore: 40,
      brandGuess,
      normalizedTitle: title,
      condition: "good",
      conditionConfidence: 0.7,
      fieldsBelowConfidenceThreshold: lowFields,
      fitGuess: { value: "regular", confidence: 0.68 },
      sizeGuess,
      seasonality: [
        { value: "fall", confidence: 0.83 },
        { value: "winter", confidence: 0.79 },
      ],
      warmthScore: { value: 55, confidence: 0.72 },
      waterResistanceScore: { value: 10, confidence: 0.64 },
      primaryColorName: { value: primaryName, confidence: 0.9 },
      secondaryColorNames: secondaryHexes.map((hex) => ({
        value: colorNameFromHex(hex),
        confidence: 0.66,
      })),
    };
    return Promise.resolve(result);
  }

  removeBackground(
    imageStoragePath: string,
    _ctx: ProviderRequestContext,
  ): Promise<{ resultStoragePath: string }> {
    // Mock: claim the cutout lives beside the source. Real removal is
    // P3-SCAN-10 and a live adapter concern.
    const resultStoragePath = imageStoragePath.replace(/(\.[a-z0-9]+)?$/i, "-cutout.png");
    return Promise.resolve({ resultStoragePath });
  }
}
