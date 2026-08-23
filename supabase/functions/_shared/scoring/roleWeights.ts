/**
 * §2.1 — turning pairwise sub-scores into one outfit-level number.
 *
 * Not every pair matters equally. Top-to-bottom is the pairing a man sees in
 * the mirror; a watch against a shoe is a detail. The weights below are the
 * doc's, and the renormalisation is what makes them usable: an outfit with no
 * outerwear and no accessories only has 0.75 of the table present, so each
 * present weight is divided by that 0.75 and the result still sums to 1.
 *
 * WHY A SHARED MODULE RATHER THAN THREE COPIES. Colour, formality and
 * silhouette all aggregate this way, and the failure mode of copying it is
 * silent: three components that disagree by a hundredth about how much a
 * jacket counts, producing a score nobody can derive by hand. One table, one
 * renormalisation, one place to change when the weights are tuned.
 */

import type { GarmentRole } from "./types.ts";

/** An unordered pair of roles, canonicalised so lookup is order-free. */
export type RolePairKey = string;

export function rolePairKey(a: GarmentRole, b: GarmentRole): RolePairKey {
  return a <= b ? `${a}|${b}` : `${b}|${a}`;
}

/**
 * §2.1's table. Keys are canonicalised, so `top|bottom` covers both directions.
 *
 * `accessory` is the one entry that is per-item rather than per-pair: the doc
 * says "0.05 per accessory, capped at 0.10 total", so a man wearing a watch, a
 * belt and a scarf does not let his accessories out-vote his trousers.
 */
const PAIR_WEIGHTS: ReadonlyMap<RolePairKey, number> = new Map([
  [rolePairKey("top", "bottom"), 0.35],
  [rolePairKey("top", "shoes"), 0.20],
  [rolePairKey("bottom", "shoes"), 0.20],
  [rolePairKey("top", "outerwear"), 0.10],
  [rolePairKey("outerwear", "bottom"), 0.05],
  // Dress mirrors top against shoes / outerwear; there is no dress|bottom pair.
  [rolePairKey("dress", "shoes"), 0.40],
  [rolePairKey("dress", "outerwear"), 0.10],
]);

/** Per §2.1: 0.05 for each accessory pairing, and no more than 0.10 in total. */
const ACCESSORY_WEIGHT_EACH = 0.05;
const ACCESSORY_WEIGHT_CAP = 0.10;

export interface WeightedPair<T> {
  readonly a: T;
  readonly b: T;
  readonly weight: number;
}

/**
 * Every pair worth scoring in an outfit, with its §2.1 weight, renormalised to
 * sum to 1.
 *
 * Returns an empty array for an outfit of fewer than two scoreable garments —
 * a single item has nothing to be compatible WITH, and the caller must treat
 * that as "no pairwise reading available" rather than as a score of zero.
 * `aggregatePairs` enforces the same thing.
 */
export function weightedPairs<T extends { readonly role: GarmentRole }>(
  items: readonly T[],
): readonly WeightedPair<T>[] {
  const pairs: { a: T; b: T; raw: number }[] = [];
  let accessoryBudgetSpent = 0;

  for (let i = 0; i < items.length; i++) {
    for (let j = i + 1; j < items.length; j++) {
      const a = items[i]!;
      const b = items[j]!;

      // Two accessories are not a pairing anyone looks at. Skipping them also
      // keeps the cap meaning what it says — otherwise a man with four
      // accessories would spend the whole 0.10 budget on watch-against-belt.
      if (a.role === "accessory" && b.role === "accessory") continue;

      let raw: number;
      if (a.role === "accessory" || b.role === "accessory") {
        const remaining = ACCESSORY_WEIGHT_CAP - accessoryBudgetSpent;
        if (remaining <= 0) continue;
        raw = Math.min(ACCESSORY_WEIGHT_EACH, remaining);
        accessoryBudgetSpent += raw;
      } else {
        const weight = PAIR_WEIGHTS.get(rolePairKey(a.role, b.role));
        // Unlisted combinations — outerwear against shoes is the real one —
        // carry no weight in §2.1 and are dropped rather than given an invented
        // one. A jacket and a shoe are rarely the pair that decides an outfit.
        if (weight === undefined) continue;
        raw = weight;
      }
      pairs.push({ a, b, raw });
    }
  }

  const total = pairs.reduce((sum, p) => sum + p.raw, 0);
  if (total <= 0) return [];
  return pairs.map(({ a, b, raw }) => ({ a, b, weight: raw / total }));
}

/**
 * Weighted mean of a per-pair score.
 *
 * Returns null when there are no weighted pairs, which is the honest answer for
 * a one-garment outfit — distinct from 0, which would say "these clash".
 */
export function aggregatePairs<T extends { readonly role: GarmentRole }>(
  items: readonly T[],
  scoreOf: (a: T, b: T) => number,
): number | null {
  const pairs = weightedPairs(items);
  if (pairs.length === 0) return null;
  return pairs.reduce((sum, p) => sum + p.weight * scoreOf(p.a, p.b), 0);
}
