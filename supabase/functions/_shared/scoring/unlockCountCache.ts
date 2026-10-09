import type { ScorableItem, ScoringContext } from "./types.ts";
import type { ComponentWeights } from "./compatibility.ts";
import type { UnlockCountResult } from "./unlockCount.ts";

/** Stable, versioned SHA-256 identity for every scoring input outside the DB version counters. */
export async function unlockCountCacheKey(input: {
  readonly userId: string;
  readonly candidate: ScorableItem;
  readonly closetStateVersion: number;
  readonly compatibilityWeightsVersion: number;
  readonly scoringContext?: ScoringContext;
  readonly occasion?: string;
  readonly weights?: ComponentWeights;
}): Promise<string> {
  const canonical = canonicalJson({
    schema: "unlock-count-v2",
    userId: input.userId,
    candidate: hypothetical(input.candidate),
    closetStateVersion: input.closetStateVersion,
    compatibilityWeightsVersion: input.compatibilityWeightsVersion,
    scoringContext: input.scoringContext ?? {},
    occasion: input.occasion ?? null,
    weights: input.weights ?? null,
  });
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** Candidate ID and wear state are not scoring attributes for hypothetical ownership. */
function hypothetical(item: ScorableItem): unknown {
  const {
    id: _id,
    laundryState: _laundry,
    availabilityState: _availability,
    lastWornAt: _lastWorn,
    ...scoring
  } = item;
  return scoring;
}

/** A purchase-unlock calculation models a hypothetical wardrobe, not today's wearability. */
export function asHypotheticalOwnership(item: ScorableItem): ScorableItem {
  return { ...item, laundryState: "clean", availabilityState: "available", lastWornAt: null };
}

function canonicalJson(value: unknown): string {
  return JSON.stringify(canonicalize(value));
}

function canonicalize(value: unknown): unknown {
  if (value instanceof Map) {
    return [...value.entries()]
      .map(([key, entry]) => [canonicalize(key), canonicalize(entry)])
      .sort((a, b) => JSON.stringify(a[0]).localeCompare(JSON.stringify(b[0])));
  }
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .filter(([, entry]) => entry !== undefined)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([key, entry]) => [key, canonicalize(entry)]),
    );
  }
  if (typeof value === "number" && !Number.isFinite(value)) {
    throw new TypeError("Unlock cache inputs must contain only finite numbers.");
  }
  return value;
}

export function isUnlockCountResult(value: unknown): value is UnlockCountResult {
  if (value === null || typeof value !== "object") return false;
  const row = value as Record<string, unknown>;
  const unlockCount = row["unlockCount"];
  const combinationsScored = row["combinationsScored"];
  const gaps = row["gapsFilled"];
  const degraded = row["degraded"];
  if (
    !Number.isSafeInteger(unlockCount) || (unlockCount as number) < 0 ||
    !Number.isSafeInteger(combinationsScored) || (combinationsScored as number) < 0 ||
    (unlockCount as number) > (combinationsScored as number) ||
    typeof row["novel"] !== "boolean" || !Array.isArray(gaps) || gaps.length > 11 ||
    !Array.isArray(degraded) || degraded.length > 32 ||
    !degraded.every((entry) => typeof entry === "string" && entry.length <= 500)
  ) {
    return false;
  }
  return gaps.every((entry) => {
    if (entry === null || typeof entry !== "object") return false;
    const gap = entry as Record<string, unknown>;
    return typeof gap["occasion"] === "string" && gap["occasion"].length <= 100 &&
      Number.isInteger(gap["formalityBucket"]) && (gap["formalityBucket"] as number) >= 0 &&
      (gap["formalityBucket"] as number) <= 10 &&
      Number.isSafeInteger(gap["qualifyingBefore"]) && (gap["qualifyingBefore"] as number) >= 0 &&
      Number.isSafeInteger(gap["qualifyingAfter"]) && (gap["qualifyingAfter"] as number) >= 0 &&
      typeof gap["fillsGap"] === "boolean";
  });
}
