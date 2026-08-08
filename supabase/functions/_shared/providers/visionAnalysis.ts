// ============================================================================
// _shared/providers/visionAnalysis.ts
// ============================================================================
// `VisionAnalysisProvider` — the second of spec §8's five provider
// protocols, specified in `docs/08-provider-abstraction.md` §2. This file
// is the interface ONLY. It contains no vendor SDK, no API key handling,
// and no HTTP: a mock lives beside it (`mockVisionAnalysis.ts`); a live
// OpenAI adapter lives in `openaiVisionAnalysis.ts` and is constructed
// exclusively in `closet/index.ts` when enabled by env — never from a
// handler, never from iOS.
//
// WHY THE PROTOCOL IS SERVER-SIDE ONLY, AND HAS NO SWIFT COUNTERPART.
//
// ADR 0004 decision 3: the iOS client never holds a provider API key and
// never constructs a request to a model vendor. The client's seam for this
// capability is `ClosetRepository.analyzeItem` /
// `batchAnalyzeItems` — repository methods in front of
// `POST /closet/analyze-item` and `POST /closet/batch-analyze`.
//
// The wire response the Edge Function returns to iOS is
// `ClosetItemAnalysisResult` (see `closet/schema.ts` / the Swift twin), NOT
// `GarmentAnalysisResult` below. The provider result is Astra-shaped for
// the server leg; the handler maps it onto the storable/reviewable wire
// DTO (colour names rather than LCh, fit/size/seasonality the master spec
// requires, etc.). That mapping is the handler's job so a vendor swap
// never forces a client release.
// ============================================================================

import type { ProviderRequestContext } from "./types.ts";

/** `docs/08-provider-abstraction.md` §2 — request side. */
export interface GarmentAnalysisRequest {
  /** Private Supabase Storage path — never a public URL. */
  readonly imageStoragePath: string;
  readonly deviceHints?: {
    readonly dominantColorsRgb: string[];
    readonly detectedText: string[];
    readonly approximateCategory?: string;
  };
}

/** Pattern vocabulary from `docs/08` §2. Mapped to the wire `GarmentPattern` in the handler. */
export type ProviderPattern =
  | "solid"
  | "stripe"
  | "check"
  | "herringbone"
  | "print"
  | "texture-only";

/** Condition vocabulary from `docs/08` §2. Mapped to the wire `ItemCondition` in the handler. */
export type ProviderCondition = "excellent" | "good" | "fair" | "worn" | "damaged";

export interface FormalityAnchor {
  readonly label: string;
  readonly score: number;
}

export interface LchColor {
  readonly l: number;
  readonly c: number;
  readonly h: number;
}

/** `docs/08-provider-abstraction.md` §2 — provider result. */
export interface GarmentAnalysisResult {
  readonly category: string;
  readonly subcategory: string;
  readonly confidence: number;
  /**
   * Optional because a provider that reads colour as a *word* has not measured
   * one. The live adapter asks the model for `primary_color_name`, which is
   * also the only colour `closet/mapper.ts` reads — these two fields have no
   * consumer at all today. Before they were optional the OpenAI adapter filled
   * them with a literal `{ l: 50, c: 20, h: 240 }` for every garment scanned,
   * which is a mid blue: a brown shirt carried a measurement saying blue.
   * Harmless while unread, and exactly the kind of thing that stops being
   * harmless the day someone wires it to the §10 colour subscore — the
   * heaviest term in the whole engine at 25%.
   *
   * Absent is honest. A confounded reading is not.
   */
  readonly colorLch?: LchColor;
  readonly secondaryColorsLch?: readonly LchColor[];
  readonly pattern: ProviderPattern;
  readonly patternScale?: "micro" | "small" | "medium" | "large";
  readonly material: readonly string[];
  readonly formalityAnchorLow: FormalityAnchor;
  readonly formalityAnchorHigh: FormalityAnchor;
  readonly formalityBlendFraction: number;
  readonly formalityScore: number;
  readonly brandGuess: { readonly name: string; readonly confidence: number } | null;
  readonly normalizedTitle: string;
  readonly condition: ProviderCondition;
  readonly conditionConfidence: number;
  readonly fieldsBelowConfidenceThreshold: readonly string[];
  /** Optional extras the mock/live adapters may fill; used by the wire mapper. */
  readonly fitGuess?: { readonly value: string; readonly confidence: number };
  readonly sizeGuess?: { readonly value: string; readonly confidence: number };
  readonly seasonality?: ReadonlyArray<{ readonly value: string; readonly confidence: number }>;
  readonly warmthScore?: { readonly value: number; readonly confidence: number };
  readonly waterResistanceScore?: { readonly value: number; readonly confidence: number };
  readonly primaryColorName?: { readonly value: string; readonly confidence: number };
  readonly secondaryColorNames?: ReadonlyArray<
    { readonly value: string; readonly confidence: number }
  >;
}

export interface VisionAnalysisProvider {
  analyzeGarment(
    request: GarmentAnalysisRequest,
    ctx: ProviderRequestContext,
  ): Promise<GarmentAnalysisResult>;

  /** Fallback background removal when the on-device pass is inadequate (§12). */
  removeBackground(
    imageStoragePath: string,
    ctx: ProviderRequestContext,
  ): Promise<{ resultStoragePath: string }>;
}
