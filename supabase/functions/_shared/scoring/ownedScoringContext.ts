import type { CoWearStat, Fit, GarmentRole, PreferenceContext, ScoringContext } from "./types.ts";
import { coWearKey } from "./subscores/context.ts";
import { roleFor } from "./types.ts";
import { rolePairKey } from "./roleWeights.ts";

export interface WearHistoryRow {
  readonly outfitId: string;
  readonly rating: number | null;
}

export interface WornItemRow {
  readonly outfitId: string;
  readonly closetItemId: string | null;
  readonly category: string;
}

export interface OwnedScoringContextRepository {
  readPreferences(userId: string): Promise<PreferenceContext | undefined>;
  listWearHistory(userId: string): Promise<readonly WearHistoryRow[]>;
  listWornOutfitItems(
    userId: string,
    outfitIds: readonly string[],
  ): Promise<readonly WornItemRow[]>;
}

const FORMALITY_CENTER: Readonly<Record<string, number>> = {
  very_casual: 0,
  casual: 25,
  balanced: 50,
  formal: 75,
  very_formal: 100,
};

export function formalityCenter(value: unknown): number | null {
  return typeof value === "string" ? FORMALITY_CENTER[value] ?? null : null;
}

export function preferenceContextFromRow(
  row: Record<string, unknown> | null,
): PreferenceContext | undefined {
  if (!row) return undefined;
  const stringArray = (value: unknown): string[] =>
    Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === "string") : [];
  const fit = row.preferred_fit;
  const validFits: readonly Fit[] = ["slim", "tailored", "regular", "relaxed", "oversized"];
  const preferredFit = typeof fit === "string" && validFits.includes(fit as Fit)
    ? fit as Fit
    : null;
  const formalityPreferenceCenter = formalityCenter(row.formality_preference);
  const preferredColors = stringArray(row.preferred_colors);
  const avoidedColors = stringArray(row.avoided_colors);
  if (
    !preferredColors.length && !avoidedColors.length && preferredFit === null &&
    formalityPreferenceCenter === null
  ) {
    return undefined;
  }
  return { preferredColors, avoidedColors, preferredFit, formalityPreferenceCenter };
}

/** Derive exact garment pairs and category-pair fallbacks from caller-owned wear history. */
export function coWearContext(
  candidateItemIds: ReadonlySet<string>,
  wears: readonly WearHistoryRow[],
  outfitItems: readonly WornItemRow[],
): Pick<ScoringContext, "coWear" | "coWearByRole"> {
  const itemsByOutfit = new Map<string, { id: string; role: GarmentRole }[]>();
  for (const item of outfitItems) {
    if (!item.closetItemId) continue;
    const role = roleFor(item.category as Parameters<typeof roleFor>[0]);
    if (!role) continue;
    const list = itemsByOutfit.get(item.outfitId) ?? [];
    if (!list.some((entry) => entry.id === item.closetItemId)) {
      list.push({ id: item.closetItemId, role });
    }
    itemsByOutfit.set(item.outfitId, list);
  }

  const exact = new Map<string, CoWearStat>();
  const byRole = new Map<string, CoWearStat>();
  const increment = (map: Map<string, CoWearStat>, key: string, positive: boolean) => {
    const previous = map.get(key) ?? { totalCoWears: 0, positiveCoWears: 0 };
    map.set(key, {
      totalCoWears: previous.totalCoWears + 1,
      positiveCoWears: previous.positiveCoWears + (positive ? 1 : 0),
    });
  };
  for (const wear of wears) {
    const items = itemsByOutfit.get(wear.outfitId) ?? [];
    for (let i = 0; i < items.length; i++) {
      for (let j = i + 1; j < items.length; j++) {
        const a = items[i]!;
        const b = items[j]!;
        const positive = (wear.rating ?? 0) >= 3;
        increment(byRole, rolePairKey(a.role, b.role), positive);
        if (candidateItemIds.has(a.id) && candidateItemIds.has(b.id)) {
          increment(exact, coWearKey(a.id, b.id), positive);
        }
      }
    }
  }
  return { coWear: exact, coWearByRole: byRole };
}

/** Only caller-scoped repository reads enter the context; no occasion or weather is inferred here. */
export async function loadOwnedPreferenceCoWearContext(
  repository: OwnedScoringContextRepository,
  userId: string,
  itemIds: ReadonlySet<string>,
): Promise<Pick<ScoringContext, "preferences" | "coWear" | "coWearByRole">> {
  const [preferences, wears] = await Promise.all([
    repository.readPreferences(userId),
    repository.listWearHistory(userId),
  ]);
  const outfitIds = [...new Set(wears.map((wear) => wear.outfitId))];
  const outfitItems = outfitIds.length
    ? await repository.listWornOutfitItems(userId, outfitIds)
    : [];
  return {
    ...(preferences ? { preferences } : {}),
    ...coWearContext(itemIds, wears, outfitItems),
  };
}
