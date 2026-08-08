/**
 * §2 — the eight weighted components, combined into one 0–100 score.
 *
 * `P4-OUTFIT-02` (the aggregate) and `P4-OUTFIT-03` (server-side weights).
 *
 * THE WEIGHTS ARE A PARAMETER, NOT A CONSTANT. Spec §10 says "weights should be
 * configurable server-side", and the reason is that they are the one part of
 * this engine nobody can be right about in advance. Every formula underneath is
 * defensible from styling rules; the relative importance of colour against
 * formality is a product judgement that will be tuned against what users
 * actually wear. Baking it into a `const` would mean a deploy per experiment.
 *
 * `DEFAULT_WEIGHTS` is the shipped default and matches §10 exactly. A caller
 * that reads a row from the config table passes it here instead.
 *
 * WHY THE RESULT CARRIES ITS PARTS. `CompatibilityScore` returns every
 * component and every degradation, not just the total. Three reasons, in
 * increasing order of importance: the outfit card shows a breakdown; tuning the
 * weights needs the components to tune against; and Kyra must never say "these
 * colours work well together" on the back of a 0.6 prior for a garment nobody
 * analysed. The last one is CLAUDE.md's governing rule, and a bare number makes
 * it impossible to honour.
 */

import {
  isWearable,
  type ScorableItem,
  type ScoringContext,
  type Subscore,
  unitClamp,
} from "./types.ts";
import { colorSubscore } from "./subscores/color.ts";
import { formalitySubscore, outfitFormality } from "./subscores/formality.ts";
import { type FitNote, silhouetteSubscore } from "./subscores/silhouette.ts";
import {
  availabilitySubscore,
  coWearSubscore,
  occasionSubscore,
  seasonWeatherSubscore,
  userPreferenceSubscore,
} from "./subscores/context.ts";

export interface ComponentWeights {
  readonly color: number;
  readonly formality: number;
  readonly silhouette: number;
  readonly seasonWeather: number;
  readonly userPreference: number;
  readonly coWear: number;
  readonly occasion: number;
  readonly availability: number;
}

/** Spec §10's table, verbatim. Sums to 1.0. */
export const DEFAULT_WEIGHTS: ComponentWeights = {
  color: 0.25,
  formality: 0.20,
  silhouette: 0.15,
  seasonWeather: 0.10,
  userPreference: 0.10,
  coWear: 0.10,
  occasion: 0.05,
  availability: 0.05,
};

export type ComponentName = keyof ComponentWeights;

export interface CompatibilityScore {
  /** 0–100, rounded, per §2's final line. */
  readonly score: number;
  /** Every component's raw sub-score and its degradations. */
  readonly components: Readonly<Record<ComponentName, Subscore>>;
  /** The weights this score was computed with, for reproducibility. */
  readonly weights: ComponentWeights;
  /**
   * Every input no component could measure, deduplicated.
   *
   * The copy layer MUST drop any sentence that rests on one of these. An
   * outfit scored with this non-empty is a defensible ranking, not a set of
   * claims about the garments.
   */
  readonly degraded: readonly string[];
  /** The §3.1 register, for describing the outfit. Null if unscoreable. */
  readonly formalityRegister: number | null;
}

export interface ScoreOptions {
  readonly weights?: ComponentWeights;
  readonly fitNotes?: readonly FitNote[];
  readonly outfitOccasionTags?: readonly string[];
  /** Maps a garment to its colour NAME, for §2.6's avoided-colour override. */
  readonly colorNameOf?: (item: ScorableItem) => string | null;
}

/**
 * Normalises any weight table to sum to 1.
 *
 * A config table is editable by a human, and a human editing eight numbers will
 * eventually make them sum to 0.97. Renormalising means that mistake shifts the
 * relative emphasis slightly — which is what they were editing anyway — instead
 * of silently capping every outfit in the product at 97.
 */
function normaliseWeights(weights: ComponentWeights): ComponentWeights {
  const total = Object.values(weights).reduce((sum, w) => sum + w, 0);
  if (total <= 0 || !Number.isFinite(total)) return DEFAULT_WEIGHTS;
  if (Math.abs(total - 1) < 1e-9) return weights;
  const scaled = {} as Record<ComponentName, number>;
  for (const [name, value] of Object.entries(weights) as [ComponentName, number][]) {
    scaled[name] = value / total;
  }
  return scaled as unknown as ComponentWeights;
}

/**
 * Score one candidate outfit.
 *
 * Unwearable garments are NOT filtered here. §2.9 puts that filter in candidate
 * generation, and doing it again in the scorer would hide a generation bug: an
 * outfit that reaches this function containing a shirt in the wash should score
 * and be visibly wrong, not quietly become a different outfit.
 */
export function scoreOutfit(
  items: readonly ScorableItem[],
  context: ScoringContext = {},
  options: ScoreOptions = {},
): CompatibilityScore {
  const weights = normaliseWeights(options.weights ?? DEFAULT_WEIGHTS);

  const components: Record<ComponentName, Subscore> = {
    color: colorSubscore(items),
    formality: formalitySubscore(items),
    silhouette: silhouetteSubscore(items, options.fitNotes ?? []),
    seasonWeather: seasonWeatherSubscore(items, context),
    userPreference: userPreferenceSubscore(items, context, options.colorNameOf),
    coWear: coWearSubscore(items, context),
    occasion: occasionSubscore(context, options.outfitOccasionTags ?? []),
    availability: availabilitySubscore(items),
  };

  let weighted = 0;
  for (const [name, weight] of Object.entries(weights) as [ComponentName, number][]) {
    weighted += weight * unitClamp(components[name].value);
  }

  const degraded = [...new Set(Object.values(components).flatMap((c) => c.degraded))];

  return {
    score: Math.round(100 * unitClamp(weighted)),
    components,
    weights,
    degraded,
    formalityRegister: outfitFormality(items),
  };
}

/**
 * Every garment the user could actually put on today (§2.9's hard filter).
 *
 * Exported for candidate generation to call BEFORE building combinations,
 * which is the only place it belongs — filtering afterwards would waste the
 * combinatorics and, worse, could return an empty ranking with no explanation
 * of why a closet full of clothes produced nothing.
 */
export function wearableItems(items: readonly ScorableItem[]): readonly ScorableItem[] {
  return items.filter(isWearable);
}
