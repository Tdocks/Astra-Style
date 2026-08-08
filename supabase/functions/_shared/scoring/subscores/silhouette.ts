/**
 * §4 silhouette compatibility — weight 0.15.
 *
 * Three layers: a fit-pairing base table (§4.1), a directional adjustment that
 * is deliberately asymmetric (§4.2), and body-profile dampeners (§4.3).
 *
 * THE ASYMMETRY IS THE INTERESTING PART. Menswear proportion rules do not
 * commute. A looser top over a tighter bottom reads as a deliberate
 * volume-balance play — an oversized knit over slim trousers is a look someone
 * chose. The same two volumes swapped, a slim top over a much looser bottom,
 * reads as clothes that do not fit. So `d = fitRank(top) - fitRank(bottom)` is
 * signed and the adjustment is not symmetric about zero.
 *
 * The one exception the table carves out is `d = −1`: a regular top with a
 * relaxed bottom is the most ordinary casual combination there is, and
 * penalising it would mark down half of what men actually wear.
 *
 * §4.3 MODIFIERS ONLY EVER DAMPEN. The master spec frames body data as fit
 * ISSUES to manage rather than preferences to optimise toward, so every
 * multiplier is ≤ 1 and none can lift a score. That is a values decision as
 * much as a modelling one: an engine that rewarded garments for a man's chest
 * measurement would be scoring the man.
 */

import { aggregatePairs, rolePairKey } from "../roleWeights.ts";
import {
  degradedScore,
  type Fit,
  measured,
  type ScorableItem,
  type Subscore,
  unitClamp,
} from "../types.ts";

const FIT_RANK: Record<Fit, number> = {
  slim: 1,
  tailored: 2,
  regular: 3,
  relaxed: 4,
  oversized: 5,
};

/**
 * §4.1 — the base score for two fits at distance `|d|`.
 *
 * The `|d| = 0` row is the one that is not a single number: two garments in the
 * same fit are coherent when that fit is tight and shapeless when it is not.
 * Slim on slim is a silhouette; oversized on oversized is a duvet.
 */
function baseScore(distance: number, fitA: Fit, fitB: Fit): number {
  if (distance === 0) {
    switch (fitA) {
      case "slim":
      case "tailored":
        return 0.90;
      case "regular":
        return 0.85;
      case "relaxed":
        return 0.65;
      case "oversized":
        return 0.50;
    }
  }
  switch (distance) {
    case 1:
      return 0.90;
    case 2:
      return 0.75;
    case 3:
      return 0.60;
    default:
      // |d| = 4, slim against oversized.
      return fitA === fitB ? 0.90 : 0.45;
  }
}

/**
 * §4.2 — applied to the top–bottom pair only.
 *
 * Other pairs get the base table untouched, and the doc's reasoning is sound:
 * outerwear is conventionally looser than what it covers regardless of
 * direction, and a shoe's "fit" is not a volume axis in the way a trouser's is.
 */
function directionalAdjustment(topFit: Fit, bottomFit: Fit): number {
  const d = FIT_RANK[topFit] - FIT_RANK[bottomFit];
  if (d >= 2) return 0.08;
  if (d >= -1) return 0;
  return -0.05 * Math.abs(d);
}

/** §4.3's fit issues, as they appear in `body_profiles.fit_notes`. */
export type FitNote = "broad_chest" | "short_torso" | "long_legs" | "large_thighs";

function hasStretch(item: ScorableItem): boolean {
  return item.materials.some((m) => m.toLowerCase().includes("stretch"));
}

/**
 * §4.3 dampeners for one garment.
 *
 * Two of the doc's four rules are computable and two are not, and the split is
 * about columns rather than difficulty:
 *
 *   `broad_chest`  — needs top fit + material. Both exist. Implemented.
 *   `large_thighs` — needs bottom fit + material. Both exist. Implemented.
 *   `short_torso`  — needs a `length: long` garment tag. No column stores one.
 *   `long_legs`    — needs a `break: no-break` tag. No column stores one.
 *
 * The two unimplementable rules return a degradation note rather than being
 * quietly skipped. A man who told onboarding about a short torso and gets no
 * adjustment for it should not have the app behave as though he never said so.
 */
/**
 * Exported for `wardrobeScore.ts`'s §5.2 fit-confidence component, which
 * needs the same dampening: a garment that structurally conflicts with a
 * stated fit issue cannot claim high fit confidence, feedback or not. Kept as
 * one function rather than two copies, per the module header's reasoning
 * about why §4.3 lives in exactly one place.
 */
export function bodyMultiplier(
  item: ScorableItem,
  fitNotes: readonly FitNote[],
): { multiplier: number; unavailable: FitNote[] } {
  let multiplier = 1;
  const unavailable: FitNote[] = [];

  for (const note of fitNotes) {
    switch (note) {
      case "broad_chest":
        if (item.role === "top" && item.fit === "slim" && !hasStretch(item)) {
          multiplier *= 0.85;
        }
        break;
      case "large_thighs":
        if (item.role === "bottom" && item.fit === "slim" && !hasStretch(item)) {
          multiplier *= 0.85;
        }
        break;
      case "short_torso":
      case "long_legs":
        unavailable.push(note);
        break;
    }
  }
  return { multiplier, unavailable };
}

/** The §4 outfit-level silhouette sub-score. */
export function silhouetteSubscore(
  items: readonly ScorableItem[],
  fitNotes: readonly FitNote[] = [],
): Subscore {
  const degraded = items
    .filter((i) => i.fit === null)
    .map((i) => `fit of ${i.id} (unrecorded, so its silhouette is unjudged)`);

  const unavailableNotes = new Set<FitNote>();

  const aggregate = aggregatePairs(items, (a, b) => {
    // A garment with no recorded fit cannot contribute a silhouette reading.
    // 0.75 is the §4.1 table's own "coherent, visible contrast" value — the
    // middle of the road, chosen so a missing fit neither flatters the pair nor
    // condemns it.
    if (a.fit === null || b.fit === null) return 0.75;

    const distance = Math.abs(FIT_RANK[a.fit] - FIT_RANK[b.fit]);
    let score = baseScore(distance, a.fit, b.fit);

    if (rolePairKey(a.role, b.role) === rolePairKey("top", "bottom")) {
      const top = a.role === "top" ? a : b;
      const bottom = a.role === "top" ? b : a;
      score += directionalAdjustment(top.fit!, bottom.fit!);
    }

    // Each garment's own dampeners apply to every pair it appears in, per §4.3.
    const modA = bodyMultiplier(a, fitNotes);
    const modB = bodyMultiplier(b, fitNotes);
    for (const note of [...modA.unavailable, ...modB.unavailable]) unavailableNotes.add(note);

    return unitClamp(score * modA.multiplier * modB.multiplier);
  });

  for (const note of unavailableNotes) {
    degraded.push(
      `the "${note}" fit adjustment (no garment length or break is stored, so it cannot be applied)`,
    );
  }

  if (aggregate === null) {
    return degradedScore(0.75, "a second garment to compare silhouette against");
  }
  return degraded.length === 0 ? measured(aggregate) : degradedScore(aggregate, ...degraded);
}
