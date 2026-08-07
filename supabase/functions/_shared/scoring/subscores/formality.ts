/**
 * §2.3 formality alignment — weight 0.20 — and §3.1's outfit-level register.
 *
 * Two different questions that both read `formality_score`, kept in one file
 * because separating them invites the mistake of using one where the other
 * belongs:
 *
 *   `formalitySubscore`  — how well do these garments agree? (§2.3, pairwise)
 *   `outfitFormality`    — what register does the outfit READ as? (§3.1)
 *
 * The second is not an input to the first. §3.1's min-penalty is for describing
 * an outfit ("smart casual"), and using it as a compatibility score would
 * double-count the same disagreement the pairwise term already charges for.
 */

import { aggregatePairs } from "../roleWeights.ts";
import {
  degradedScore,
  type GarmentRole,
  measured,
  type ScorableItem,
  type Subscore,
  unitClamp,
} from "../types.ts";

/**
 * §2.3's category-level defaults for a garment the classifier has not scored.
 *
 * Deliberately clustered in the middle. These are not claims about the garment
 * — they are the least-wrong placeholder, and a wrong guess at either extreme
 * would do more damage than a wrong guess at the centre: a real dress shoe
 * defaulted to 20 would drag a suit's score down harder than a trainer
 * defaulted to 45 lifts it.
 */
const CATEGORY_DEFAULT_FORMALITY: Record<GarmentRole, number> = {
  top: 45,
  bottom: 45,
  outerwear: 50,
  shoes: 45,
  accessory: 45,
};

/** §3.1's aggregation weights. Accessories barely move the register. */
const REGISTER_WEIGHT: Record<GarmentRole, number> = {
  top: 1.0,
  bottom: 1.0,
  shoes: 1.0,
  outerwear: 0.9,
  accessory: 0.4,
};

/** §2.3: the gap at which two garments stop reading as one outfit. */
const ZEROING_GAP = 40;

function formalityOf(item: ScorableItem): number {
  return item.formalityScore ?? CATEGORY_DEFAULT_FORMALITY[item.role];
}

/**
 * §2.3 — `max(0, 1 - (Δf / 40)^1.5)`.
 *
 * The exponent is the whole idea. A linear penalty would charge the same for
 * each point of disagreement, but styling does not work that way: a 10-point
 * gap between a polo and a chino is texture, and a 40-point gap between dress
 * shoes and gym shorts is a mistake. Super-linearising means small gaps cost
 * almost nothing (10 points → 0.875) while large ones fall off a cliff.
 */
export function formalityPairScore(a: number, b: number): number {
  const gap = Math.abs(a - b);
  if (gap >= ZEROING_GAP) return 0;
  return unitClamp(1 - Math.pow(gap / ZEROING_GAP, 1.5));
}

/** The §2.3 outfit-level sub-score. */
export function formalitySubscore(items: readonly ScorableItem[]): Subscore {
  const degraded = items
    .filter((i) => i.formalityScore === null)
    .map((i) => `formality of ${i.id} (unclassified; using the ${i.role} default)`);

  const aggregate = aggregatePairs(
    items,
    (a, b) => formalityPairScore(formalityOf(a), formalityOf(b)),
  );

  if (aggregate === null) {
    // One garment cannot disagree with itself about register.
    return degradedScore(1, "a second garment to compare formality against");
  }
  return degraded.length === 0 ? measured(aggregate) : degradedScore(aggregate, ...degraded);
}

/**
 * §3.1 — the register an outfit reads as, 0–100.
 *
 * NOT A MEAN, and the reason is a real styling rule: an outfit reads as casual
 * as its most casual visible element, tempered by proportion. One trainer drags
 * a tailored outfit down further than one tie lifts a casual one, because the
 * eye finds the outlier and reads the whole from it.
 *
 * The `deviation > 10` gate is what keeps that from over-firing. Real outfits
 * mix registers slightly on purpose — a knit polo at 40 with tailored chinos at
 * 50 is a deliberate casualisation, not an error — so only a genuine outlier is
 * charged for.
 *
 * Accessories are excluded from the minimum. A 20-point woven bracelet should
 * not drag a suit down to shorts; it is not what anyone reads the outfit from.
 */
export function outfitFormality(items: readonly ScorableItem[]): number | null {
  const scored = items.filter((i) => i.role !== "accessory" || i.formalityScore !== null);
  if (scored.length === 0) return null;

  let weightedSum = 0;
  let weightTotal = 0;
  for (const item of scored) {
    const weight = REGISTER_WEIGHT[item.role];
    weightedSum += weight * formalityOf(item);
    weightTotal += weight;
  }
  if (weightTotal === 0) return null;
  const mean = weightedSum / weightTotal;

  const visible = scored.filter((i) => i.role !== "accessory");
  if (visible.length === 0) return Math.round(mean);

  const lowest = Math.min(...visible.map(formalityOf));
  const deviation = mean - lowest;
  const penalty = deviation > 10 ? 0.5 * deviation : 0;

  return Math.round(Math.min(100, Math.max(0, mean - penalty)));
}
