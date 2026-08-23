/**
 * Women's silhouette module (ADR 0019). Menswear `silhouette.ts` is
 * unchanged and is still the scorer for `menswear_3_role`.
 *
 * Dress is a one-piece volume: it pairs with shoes/outerwear on the base
 * fit table, not the top–bottom directional adjustment. Skirt maps to
 * `bottom` in `roleFor`, so top–skirt still uses the menswear directional
 * table when both exist.
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
import { bodyMultiplier, type FitNote } from "./silhouette.ts";

const FIT_RANK: Record<Fit, number> = {
  slim: 1,
  tailored: 2,
  regular: 3,
  relaxed: 4,
  oversized: 5,
};

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
      return fitA === fitB ? 0.90 : 0.45;
  }
}

function directionalAdjustment(topFit: Fit, bottomFit: Fit): number {
  const d = FIT_RANK[topFit] - FIT_RANK[bottomFit];
  if (d >= 2) return 0.08;
  if (d >= -1) return 0;
  return -0.05 * Math.abs(d);
}

export function silhouetteSubscoreWomenswear(
  items: readonly ScorableItem[],
  fitNotes: readonly FitNote[] = [],
): Subscore {
  const degraded = items
    .filter((i) => i.fit === null)
    .map((i) => `fit of ${i.id} (unrecorded, so its silhouette is unjudged)`);

  const unavailableNotes = new Set<FitNote>();

  const aggregate = aggregatePairs(items, (a, b) => {
    if (a.fit === null || b.fit === null) return 0.75;

    const distance = Math.abs(FIT_RANK[a.fit] - FIT_RANK[b.fit]);
    let score = baseScore(distance, a.fit, b.fit);

    if (rolePairKey(a.role, b.role) === rolePairKey("top", "bottom")) {
      const top = a.role === "top" ? a : b;
      const bottom = a.role === "top" ? b : a;
      score += directionalAdjustment(top.fit!, bottom.fit!);
    }

    const notesFor = (item: ScorableItem): FitNote[] => {
      if (item.role === "dress") {
        return bodyMultiplier({ ...item, role: "top" }, fitNotes).unavailable;
      }
      return bodyMultiplier(item, fitNotes).unavailable;
    };
    const multiplierFor = (item: ScorableItem): number => {
      if (item.role === "dress") {
        return bodyMultiplier({ ...item, role: "top" }, fitNotes).multiplier;
      }
      return bodyMultiplier(item, fitNotes).multiplier;
    };

    const modA = { multiplier: multiplierFor(a), unavailable: notesFor(a) };
    const modB = { multiplier: multiplierFor(b), unavailable: notesFor(b) };
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
