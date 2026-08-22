/**
 * The contract `daily-brief` asks an outfit scorer to satisfy.
 *
 * WHY THIS MOVED OUT OF `leastRecentlyWorn.ts`. It was declared there because
 * that was the only implementation — the placeholder defined both the job and
 * the only way of doing it. That is fine right up until a second
 * implementation appears, at which point the interface is typed to whatever
 * the placeholder happened to need, and the real engine cannot satisfy it.
 *
 * That is exactly what happened. The placeholder reads three columns because
 * it looks at a calendar rather than at a garment; `CompatibilityOutfitScorer`
 * reads fourteen because "do these go together" is a question about cloth. An
 * interface pinned to the narrow row rejected the wide one outright.
 *
 * So the row type here is the REAL closet row, and the placeholder — which
 * reads a subset of it — still satisfies the contract unchanged. Widening in
 * this direction is safe by construction; the reverse would not have been.
 */

import type { ClosetItemMapperRow } from "./closetItemMapper.ts";

/**
 * A closet row as the scorers now receive it.
 *
 * The mapper's shape plus a required `last_worn_at`. The mapper now reads
 * that column when present (rotation in `generateCandidateOutfits`); it stays
 * required here because the placeholder scorer ranks by it and `daily-brief`
 * always selects it. Optional on `ClosetItemMapperRow` so callers without a
 * wear timestamp can omit it.
 */
export type OutfitScorerRow = ClosetItemMapperRow & {
  readonly last_worn_at: string | null;
};

export interface ScoredOutfit {
  itemIds: string[];
  compatibilityScore: number;
  reason: string;
}

export interface OutfitScorerOptions {
  desiredCount: number;
  lockedItemIds: ReadonlySet<string>;
  excludedItemIds: ReadonlySet<string>;
}

export interface OutfitScorer {
  generate(items: readonly OutfitScorerRow[], options: OutfitScorerOptions): ScoredOutfit[];
}
