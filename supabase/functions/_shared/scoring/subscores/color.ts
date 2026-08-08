/**
 * §2.2 colour compatibility — weight 0.25, the heaviest single component.
 *
 * Harmony rules from §1.4, pattern interaction from §1.5, aggregated through
 * §2.1's role pairs.
 *
 * WHAT THIS DOES WHEN IT DOES NOT KNOW A COLOUR. §2.2 sets a 0.6 neutral prior
 * for an unanalysed colour, and it is important that 0.6 is neither 0 nor 1: a
 * data gap must not tank an outfit (which would bury every garment the vision
 * pipeline has not seen) nor inflate one (which would rank unknowns to the
 * top). It is also important that the prior is REPORTED. A 0.6 that reaches the
 * outfit card as "these colours work together" is the confounded reading
 * CLAUDE.md forbids — so every pair that falls back names the garment it could
 * not read, and the copy layer is required to drop the colour sentence.
 */

import { classifyNeutral, hueDistance, type LCh } from "../colorSpace.ts";
import { aggregatePairs } from "../roleWeights.ts";
import { degradedScore, measured, type ScorableItem, type Subscore, unitClamp } from "../types.ts";

/** §2.2's prior for a garment whose colour was never analysed. */
export const UNKNOWN_COLOR_PRIOR = 0.6;

/** §1.4's zone boundaries, in degrees of hue separation. */
const ANALOGOUS_MAX = 60;
const COMPLEMENTARY_MIN = 150;
const MONOCHROME_MAX = 15;

/**
 * §1.4 — how two chromatic hues read together.
 *
 * The shape worth knowing: harmony is NOT monotonic in hue distance. Very close
 * is good, adjacent is good, opposite is good, and the trouble is in between —
 * around 105° apart, where two colours are neither obviously related nor
 * obviously contrasting and the eye reads the result as a mistake rather than a
 * choice. That is why this is a table of zones and not a curve.
 */
function chromaticHarmony(a: LCh, b: LCh): number {
  const dh = hueDistance(a.h, b.h);

  if (dh <= MONOCHROME_MAX) {
    // Same hue family. Good only if something separates the two — a navy
    // jacket over a navy shirt in the same value reads accidental, like a suit
    // whose halves do not match, while charcoal over pale grey reads deliberate.
    const separated = Math.abs(a.l - b.l) >= 20 || Math.abs(a.c - b.c) >= 15;
    return separated ? 0.95 : 0.55;
  }

  if (dh <= ANALOGOUS_MAX) {
    // 0.95 at 15°, sliding to 0.80 at 60°.
    return 0.95 - 0.15 * ((dh - MONOCHROME_MAX) / (ANALOGOUS_MAX - MONOCHROME_MAX));
  }

  if (dh < COMPLEMENTARY_MIN) {
    // The clash zone. Worst at its centre (~105°), recovering toward either
    // edge as the pair starts reading as analogous or as complementary.
    const distanceFromEdge = Math.min(dh - ANALOGOUS_MAX, COMPLEMENTARY_MIN - dh);
    return 0.55 - 0.20 * (distanceFromEdge / 45);
  }

  // Opposite hues. Rewards one muted against one saturated — the "pop of
  // colour" — and penalises two fully saturated complements, which fight.
  const chromaSpread = unitClamp(Math.abs(a.c - b.c) / 100);
  return 0.60 + 0.30 * (1 - chromaSpread);
}

/** §1.4's neutral cases. */
function harmonyWithNeutrals(a: LCh, aNeutral: boolean, b: LCh, bNeutral: boolean): number {
  if (aNeutral && bNeutral) {
    // Neutral on neutral is safe but can read flat. Visible value contrast —
    // charcoal trousers under a white shirt — is what makes it look chosen.
    const bonus = Math.abs(a.l - b.l) >= 30 ? 0.03 : 0;
    return Math.min(0.98, 0.95 + bonus);
  }
  if (aNeutral || bNeutral) {
    // A neutral anchors any hue. The only deduction is for a chromatic partner
    // so saturated it still shouts against a quiet ground.
    const chromatic = aNeutral ? b : a;
    return chromatic.c > 55 ? 0.85 : 0.90;
  }
  return chromaticHarmony(a, b);
}

const SCALE_RANK: Record<string, number> = { micro: 1, small: 2, medium: 3, large: 4 };

/**
 * §1.5 — the multiplier for two patterned garments worn together.
 *
 * Returns 1 (no penalty) whenever either garment is solid, and ALSO whenever
 * the scales are unknown, which today is always: no `pattern_scale` column
 * exists (see `types.ts`, note 3). The whole rule turns on scale separation, so
 * without it the honest move is to apply nothing and say so — a guessed scale
 * would be inventing the one fact the rule reads.
 */
function patternPenalty(
  a: ScorableItem,
  b: ScorableItem,
): { multiplier: number; degraded?: string } {
  const aPatterned = a.pattern != null && a.pattern !== "solid" && a.pattern !== "texture-only";
  const bPatterned = b.pattern != null && b.pattern !== "solid" && b.pattern !== "texture-only";
  if (!aPatterned || !bPatterned) return { multiplier: 1 };

  const aRank = a.patternScale ? SCALE_RANK[a.patternScale] : undefined;
  const bRank = b.patternScale ? SCALE_RANK[b.patternScale] : undefined;
  if (aRank === undefined || bRank === undefined) {
    return {
      multiplier: 1,
      degraded: "pattern scale (no column stores it, so pattern mixing is unjudged)",
    };
  }

  if (Math.abs(aRank - bRank) <= 1) {
    // Two patterns of similar visual weight compete instead of layering.
    return { multiplier: 0.55 };
  }
  // Scale separation is what makes pattern-on-pattern deliberate; a shared hue
  // family is what makes it look considered rather than merely bold.
  const sharesHue = a.primaryColor && b.primaryColor &&
    hueDistance(a.primaryColor.h, b.primaryColor.h) <= 30;
  return { multiplier: sharesHue ? 0.85 : 0.70 };
}

/** §2.2 step 2 — blend the best secondary cross-pairing in at 20%. */
function pairHarmony(a: ScorableItem, b: ScorableItem): number {
  const primaryA = a.primaryColor!;
  const primaryB = b.primaryColor!;
  const primary = harmonyWithNeutrals(primaryA, a.isNeutral, primaryB, b.isNeutral);

  const crossScores: number[] = [];
  for (const secondary of a.secondaryColors) {
    crossScores.push(
      harmonyWithNeutrals(secondary, classifyNeutral(secondary).isNeutral, primaryB, b.isNeutral),
    );
  }
  for (const secondary of b.secondaryColors) {
    crossScores.push(
      harmonyWithNeutrals(primaryA, a.isNeutral, secondary, classifyNeutral(secondary).isNeutral),
    );
  }
  if (crossScores.length === 0) return primary;

  const bestSecondary = Math.max(...crossScores);
  return 0.8 * primary + 0.2 * bestSecondary;
}

/**
 * The §2.2 outfit-level colour sub-score.
 *
 * Falls back to `UNKNOWN_COLOR_PRIOR` for any pair where either garment has no
 * analysed colour, and names every such garment in `degraded`.
 */
export function colorSubscore(items: readonly ScorableItem[]): Subscore {
  const unreadable = items.filter((i) => i.primaryColor === null);
  const degraded: string[] = [];
  for (const item of unreadable) {
    degraded.push(`colour of ${item.id} (never analysed)`);
  }
  const patternGaps = new Set<string>();

  const aggregate = aggregatePairs(items, (a, b) => {
    if (a.primaryColor === null || b.primaryColor === null) return UNKNOWN_COLOR_PRIOR;
    const { multiplier, degraded: patternGap } = patternPenalty(a, b);
    if (patternGap) patternGaps.add(patternGap);
    // §1.5: the penalty applies to the raw harmony, once per pair, before the
    // pair enters the weighted aggregate.
    return unitClamp(pairHarmony(a, b) * multiplier);
  });

  for (const gap of patternGaps) degraded.push(gap);

  if (aggregate === null) {
    // Fewer than two scoreable garments. Not a clash — nothing to compare.
    return degradedScore(UNKNOWN_COLOR_PRIOR, "a second garment to compare colour against");
  }
  return degraded.length === 0 ? measured(aggregate) : degradedScore(aggregate, ...degraded);
}
