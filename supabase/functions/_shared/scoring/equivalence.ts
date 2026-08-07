/**
 * §6.3 near-duplicate detection, plus §5.4's hue-bin clustering — the two
 * share one grouping (`hueBin`) so "which hue family is this in" means the
 * same thing whether the question is "is this wardrobe cohesive" or "are
 * these two outfits the same outfit."
 *
 * `equivalenceClass` answers "would a person call these two garments
 * interchangeable," which is a coarser question than the compatibility
 * scorer's ΔE/hue-angle math (`colorSpace.ts`, `redundancy.ts`) answers. Two
 * white t-shirts are the same equivalence class even if their colours measure
 * ΔE=6 apart — a person does not experience that as "a different outfit."
 */

import { CATEGORY_DEFAULT_FORMALITY } from "./subscores/formality.ts";
import type { ClothingCategory, Fit, ScorableItem } from "./types.ts";

/** §5.4: 12 hue bins of 30° each, indexed 0–11 starting at hue 0. */
export const HUE_BIN_COUNT = 12;
const HUE_BIN_WIDTH = 360 / HUE_BIN_COUNT;

/** Which of §5.4's 12 hue bins a hue angle falls in. Undefined below C* ≈ 2 — see `colorSpace.ts`. */
export function hueBin(hueDegrees: number): number {
  const normalised = ((hueDegrees % 360) + 360) % 360;
  return Math.floor(normalised / HUE_BIN_WIDTH) % HUE_BIN_COUNT;
}

/**
 * §5.4/§6.3's colour cluster: `"neutral"` for a functional neutral (or an
 * unanalysed colour — see the comment below), otherwise `"hue-N"`.
 *
 * UNANALYSED COLOUR FOLDS INTO NEUTRAL, NOT ITS OWN BUCKET. A null
 * `primaryColor` is not "the neutral colour" — it is missing data — but a
 * dedicated "unknown" cluster would make every unanalysed garment in a role
 * near-duplicates of each other purely because none of them were looked at,
 * which is a worse error than the mild inflation of folding them into the
 * biggest, least distinctive bucket. Callers that need to know a colour was
 * guessed already have that from `Subscore.degraded` upstream; this function
 * only has to produce a stable bucket, not re-report the gap.
 */
export function colorClusterId(
  item: { primaryColor: { h: number } | null; isNeutral: boolean },
): string {
  if (item.primaryColor === null || item.isNeutral) return "neutral";
  return `hue-${hueBin(item.primaryColor.h)}`;
}

/** §6.3: `floor(formality_score / 10)`, matching §2.3's own category defaults for an unclassified garment. */
export function formalityBucket(
  item: { formalityScore: number | null; role: keyof typeof CATEGORY_DEFAULT_FORMALITY },
): number {
  const value = item.formalityScore ?? CATEGORY_DEFAULT_FORMALITY[item.role];
  return Math.floor(value / 10);
}

export interface EquivalenceClass {
  readonly category: ClothingCategory;
  readonly colorCluster: string;
  readonly formalityBucket: number;
  readonly fit: Fit | null;
}

/** §6.3's `equivalenceClass(item) = (category, colorClusterId, formalityBucket, fit)`. */
export function equivalenceClass(item: ScorableItem): EquivalenceClass {
  return {
    category: item.category,
    colorCluster: colorClusterId(item),
    formalityBucket: formalityBucket(item),
    fit: item.fit,
  };
}

function equivalenceKey(ec: EquivalenceClass): string {
  return `${ec.category}:${ec.colorCluster}:${ec.formalityBucket}:${ec.fit ?? "unrecorded"}`;
}

/** Are these two garments interchangeable for outfit-counting purposes? */
export function sameEquivalenceClass(a: ScorableItem, b: ScorableItem): boolean {
  return equivalenceKey(equivalenceClass(a)) === equivalenceKey(equivalenceClass(b));
}

/**
 * A small, fast, purely-synchronous string hash (FNV-1a, doubled).
 *
 * §6.3 says "hash it (e.g., SHA-1 truncated to 64 bits)" — the "e.g." is load
 * bearing. Nothing downstream needs collision resistance against an adversary;
 * this hash only has to agree with itself for the same signature and disagree
 * for a different one, at wardrobe-sized combination counts (thousands, not
 * billions). `crypto.subtle.digest` is real SHA-1 but is Promise-based, and
 * every scoring function in this package is synchronous by rule (see
 * `types.ts`'s header) so it can run inline inside a hot enumeration loop
 * without every caller becoming async. Two independent 32-bit FNV-1a passes
 * over the same string give 64 bits of spread, which is what the doc's
 * "truncated to 64 bits" was asking for in the first place.
 */
function fnv1a(input: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

function hashHex(input: string): string {
  const a = fnv1a(input);
  const b = fnv1a(`${input}${a}`);
  return a.toString(16).padStart(8, "0") + b.toString(16).padStart(8, "0");
}

/**
 * §6.3's canonical signature: the sorted tuple of `equivalenceClass()` across
 * every filled role, hashed.
 *
 * Sorted, not role-ordered: two combinations that fill the same roles with
 * equivalence-class-identical garments must hash identically regardless of
 * the order the caller happened to build the items array in.
 */
export function canonicalSignature(items: readonly ScorableItem[]): string {
  const keys = items.map((item) => equivalenceKey(equivalenceClass(item))).sort();
  return hashHex(keys.join("|"));
}
