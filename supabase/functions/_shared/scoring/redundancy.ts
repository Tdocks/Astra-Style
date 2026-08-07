/**
 * §7.1 — how similar (not how *harmonious*) two garments are, and the
 * per-item redundancy score that falls out of it.
 *
 * Built for `wardrobeScore.ts`'s §5.7 (10% weight, inverted: low redundancy
 * is good wardrobe health). §7.2's duplicate-risk flag on the product
 * decision page is the same `similarity()` function at a ≥0.85 threshold,
 * which is why it lives here rather than inside `wardrobeScore.ts` — a
 * future `/products/evaluate` caller reuses this file, not a second copy of
 * the formula.
 *
 * WHY THIS IS NOT `colorSpace.ts`'s harmony function. §1.4 asks "do these two
 * colours go together" (navy suits olive; that is not "these are the same
 * colour"). §7.1 asks "are these two garments the same garment" — a literal
 * closeness question — so it reads raw ΔE off `colorDistance`, not the
 * hue-zone harmony table. Reusing the harmony function here would call two
 * navy jackets "similar" for the same reason navy suits olive, which is not
 * why they are redundant; they are redundant because they are the same navy.
 */

import { colorDistance, type Lab, type LCh } from "./colorSpace.ts";
import type { Fit, GarmentRole, Season } from "./types.ts";

/** §7.1's ΔE→identity mapping: 0 apart is identical, 40+ apart shares nothing. */
const IDENTITY_DE_CEILING = 40;

/** The §4.1 fit-rank order, restated here — see `subscores/silhouette.ts`'s copy for why it is not imported. */
const FIT_RANK: Record<Fit, number> = {
  slim: 1,
  tailored: 2,
  regular: 3,
  relaxed: 4,
  oversized: 5,
};

/**
 * §7.1's `colorHarmonyAsIdentity` — raw perceptual closeness, not harmony.
 * Takes LAB rather than LCh because ΔE (CIE76) is defined on LAB's Cartesian
 * axes, same as `colorSpace.ts`'s own `colorDistance`.
 */
export function colorIdentity(a: Lab, b: Lab): number {
  const de = colorDistance(a, b);
  return 1 - Math.min(1, Math.max(0, de / IDENTITY_DE_CEILING));
}

/**
 * §7.1's `silhouetteAdjacency` — the doc names the function but not its body.
 * The rank distance is the same one §4.1 built its base-score table on
 * (`slim..oversized` = 1..5), so "adjacent" here means what it means there:
 * one step is close, the far end of the scale (slim vs. oversized, distance 4)
 * is not. Normalised by the maximum possible distance so the result is a
 * comparable [0,1] contribution to the weighted sum below it, same as every
 * other term in `similarity()`.
 */
export function silhouetteAdjacency(a: Fit, b: Fit): number {
  const distance = Math.abs(FIT_RANK[a] - FIT_RANK[b]);
  return 1 - Math.min(1, distance / 4);
}

export interface RedundancyItem {
  readonly id: string;
  readonly category: string;
  readonly role: GarmentRole;
  readonly primaryColorLab: Lab | null;
  readonly formalityScore: number | null;
  readonly fit: Fit | null;
  readonly materials: readonly string[];
  readonly seasonality: readonly Season[];
}

/** §2.3's category default, restated — see `subscores/formality.ts` for the source of truth. */
const CATEGORY_DEFAULT_FORMALITY: Record<GarmentRole, number> = {
  top: 45,
  bottom: 45,
  outerwear: 50,
  shoes: 45,
  accessory: 45,
};

function formalityOf(item: RedundancyItem): number {
  return item.formalityScore ?? CATEGORY_DEFAULT_FORMALITY[item.role];
}

/**
 * §7.1's weighted sum. All four terms are always computable: colour and
 * formality always resolve (via the null-colour/null-formality priors used
 * elsewhere in this package), fit contributes its neutral 0 when either
 * garment's fit is unrecorded (neither `==` nor an adjacency reading is
 * possible), and material contributes 0 rather than 1 when either list is
 * empty (an unrecorded material must not read as "matches").
 */
export function similarity(a: RedundancyItem, b: RedundancyItem): number {
  const colorTerm = a.primaryColorLab && b.primaryColorLab
    ? colorIdentity(a.primaryColorLab, b.primaryColorLab)
    : 0.6; // §2.2's own unknown-colour prior — neither tanks nor inflates similarity.

  const formalityTerm = 1 - Math.abs(formalityOf(a) - formalityOf(b)) / 100;

  const fitTerm = a.fit === null || b.fit === null
    ? 0
    : a.fit === b.fit
    ? 1
    : silhouetteAdjacency(a.fit, b.fit);

  const materialTerm = a.materials.length > 0 && b.materials.length > 0 &&
      a.materials.some((m) => b.materials.includes(m))
    ? 1
    : 0;

  return 0.4 * colorTerm + 0.3 * formalityTerm + 0.2 * fitTerm + 0.1 * materialTerm;
}

/**
 * §7.1's restriction: two items only compete for the same redundancy
 * comparison if their seasonality overlaps. Empty seasonality (never tagged)
 * is treated as "all seasons" rather than "no seasons" — an untagged item
 * cannot be excluded from every comparison purely because nobody set its
 * seasonality, which would make redundancy scoring silently prefer
 * unclassified items by hiding them from the comparison set entirely.
 */
export function seasonalityOverlaps(a: readonly Season[], b: readonly Season[]): boolean {
  if (a.length === 0 || b.length === 0) return true;
  return a.some((s) => b.includes(s));
}

/**
 * §7.1's `redundancyScore_i` — the highest similarity to any other active,
 * same-category, season-overlapping item. `max`, not mean: a garment is
 * redundant if it duplicates ANY one other item, not "somewhat like the
 * average of its category."
 */
export function redundancyScore(item: RedundancyItem, others: readonly RedundancyItem[]): number {
  let best = 0;
  for (const other of others) {
    if (other.id === item.id) continue;
    if (other.category !== item.category) continue;
    if (!seasonalityOverlaps(item.seasonality, other.seasonality)) continue;
    best = Math.max(best, similarity(item, other));
  }
  return best;
}

/** §7.1's duplicate-risk flag, and the same one §7.2 surfaces on the product decision page. */
export const DUPLICATE_SIMILARITY_THRESHOLD = 0.85;

export function isDuplicateRisk(a: RedundancyItem, b: RedundancyItem): boolean {
  return similarity(a, b) >= DUPLICATE_SIMILARITY_THRESHOLD;
}

/** Convenience: `colorIdentity` from LCh, for callers (like `wardrobeScore.ts`) that only carry LCh. */
export function labFromLCh(lch: LCh): Lab {
  const hRad = (lch.h * Math.PI) / 180;
  return { l: lch.l, a: lch.c * Math.cos(hRad), b: lch.c * Math.sin(hRad) };
}
