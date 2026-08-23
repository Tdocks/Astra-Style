// ============================================================================
// packing/plan.ts
// ============================================================================
// The packing brain shared by `POST /packing/generate` and Kyra's
// `create_packing_list`. One scorer, one persist path. A second copy in the
// Kyra function would drift the week strip from the trip bag.
// ============================================================================

import { serverError } from "../_shared/errors.ts";
import type {
  OutfitScorer,
  OutfitScorerRow,
  ScoredOutfit,
} from "../_shared/scoring/outfitScorer.ts";
import {
  type GeneratePackingBody,
  nextDay,
  type PackingDayWire,
  type PackingPlanWire,
} from "./schema.ts";

export interface OccasionRow {
  readonly starts_at: string;
  readonly title: string;
  readonly dress_code: string | null;
}

export interface OutfitDraft {
  readonly compatibilityScore: number;
  readonly reason: string;
  readonly itemIds: readonly string[];
  readonly rolesByItemId: ReadonlyMap<string, string>;
  readonly name: string;
}

export interface BriefRow {
  readonly id: string;
  readonly user_id: string;
  readonly brief_date: string;
  readonly primary_outfit_id: string | null;
  readonly alternative_outfit_ids: unknown;
  readonly schedule_snapshot: Record<string, unknown>;
}

export interface PackingRepository {
  listCandidateItems(userId: string): Promise<OutfitScorerRow[]>;
  listOccasions(userId: string, fromDate: string, toExclusive: string): Promise<OccasionRow[]>;
  findBriefs(userId: string, dates: readonly string[]): Promise<BriefRow[]>;
  createOutfits(userId: string, drafts: readonly OutfitDraft[]): Promise<string[]>;
  upsertBrief(input: {
    userId: string;
    briefDate: string;
    primaryOutfitId: string | null;
    alternativeOutfitIds: readonly string[];
    scheduleSnapshot: Record<string, unknown>;
  }): Promise<BriefRow>;
  listOutfitItemIds(outfitIds: readonly string[]): Promise<string[]>;
}

export interface BuildPlanDeps {
  repository: PackingRepository;
  scorerForDay: (targetOccasion?: string) => OutfitScorer;
}

function occasionsOnDay(rows: readonly OccasionRow[], day: string): OccasionRow[] {
  return rows.filter((row) => row.starts_at.slice(0, 10) === day);
}

function targetOccasion(
  dayOccasions: readonly OccasionRow[],
  dressCodes: readonly string[],
  activities: readonly string[],
): string | undefined {
  const fromRow = dayOccasions[0]?.dress_code ?? dayOccasions[0]?.title;
  if (fromRow && fromRow.length > 0) return fromRow;
  if (dressCodes[0]) return dressCodes[0];
  if (activities[0]) return activities[0];
  return undefined;
}

function outfitName(day: string, dayOccasions: readonly OccasionRow[]): string {
  const title = dayOccasions[0]?.title?.trim();
  if (title) return title;
  return day;
}

export async function buildPlan(
  userId: string,
  body: GeneratePackingBody,
  dates: readonly string[],
  deps: BuildPlanDeps,
): Promise<PackingPlanWire> {
  if (!body.regenerate) {
    const existing = await existingPlan(userId, dates, deps);
    if (existing) return existing;
  }

  const items = await deps.repository.listCandidateItems(userId);
  const rolesByItemId = new Map(items.map((item) => [item.id, item.category as string]));
  const lastExclusive = dates[dates.length - 1] ? nextDay(dates[dates.length - 1]!) : body.endDate;
  const occasions = await deps.repository.listOccasions(userId, body.startDate, lastExclusive);

  const used = new Set<string>();
  const packingList = new Set<string>();
  const daily: PackingDayWire[] = [];
  const missing: string[] = [];

  for (const day of dates) {
    const dayOccasions = occasionsOnDay(occasions, day);
    const occasion = targetOccasion(dayOccasions, body.dressCodes, body.activities);
    const scorer = deps.scorerForDay(occasion);
    const scored = pickOutfit(scorer, items, used);
    if (!scored.outfit) {
      missing.push(`No wearable look for ${day}.`);
      await deps.repository.upsertBrief({
        userId,
        briefDate: day,
        primaryOutfitId: null,
        alternativeOutfitIds: [],
        scheduleSnapshot: {
          event_count: dayOccasions.length,
          headline: dayOccasions[0]?.title ?? null,
        },
      });
      continue;
    }

    const ids = await deps.repository.createOutfits(userId, [{
      compatibilityScore: scored.outfit.compatibilityScore,
      reason: scored.outfit.reason,
      itemIds: scored.outfit.itemIds,
      rolesByItemId,
      name: outfitName(day, dayOccasions),
    }]);
    const outfitId = ids[0];
    if (!outfitId) {
      throw serverError("Couldn't save that day's look.");
    }

    for (const itemId of scored.outfit.itemIds) {
      used.add(itemId);
      packingList.add(itemId);
    }

    await deps.repository.upsertBrief({
      userId,
      briefDate: day,
      primaryOutfitId: outfitId,
      alternativeOutfitIds: [],
      scheduleSnapshot: {
        event_count: dayOccasions.length,
        headline: dayOccasions[0]?.title ?? null,
      },
    });

    daily.push({ date: day, outfit_id: outfitId, is_rewear: scored.isRewear });
    if (scored.isRewear && !body.hasLaundryAccess) {
      missing.push(`No laundry — ${day} rewears a piece from earlier.`);
    }
  }

  const note = body.destination.length > 0
    ? "Pack a rain shell if the forecast shifts. Astra does not invent weather for a city it cannot see."
    : null;

  return {
    packing_list_item_ids: [...packingList],
    daily_outfit_plan: daily,
    missing_essentials: missing,
    weather_contingency_note: note,
  };
}

async function existingPlan(
  userId: string,
  dates: readonly string[],
  deps: BuildPlanDeps,
): Promise<PackingPlanWire | null> {
  const briefs = await deps.repository.findBriefs(userId, dates);
  if (briefs.length < dates.length) return null;
  const byDate = new Map(briefs.map((row) => [row.brief_date, row]));
  const daily: PackingDayWire[] = [];
  const outfitIds: string[] = [];
  for (const day of dates) {
    const brief = byDate.get(day);
    if (!brief?.primary_outfit_id) return null;
    outfitIds.push(brief.primary_outfit_id);
    daily.push({ date: day, outfit_id: brief.primary_outfit_id, is_rewear: false });
  }
  const itemIds = await deps.repository.listOutfitItemIds(outfitIds);
  return {
    packing_list_item_ids: itemIds,
    daily_outfit_plan: daily,
    missing_essentials: [],
    weather_contingency_note: null,
  };
}

function pickOutfit(
  scorer: OutfitScorer,
  items: readonly OutfitScorerRow[],
  used: ReadonlySet<string>,
): { outfit: ScoredOutfit | null; isRewear: boolean } {
  const fresh = scorer.generate(items, {
    desiredCount: 1,
    lockedItemIds: new Set(),
    excludedItemIds: used,
  })[0];
  if (fresh) return { outfit: fresh, isRewear: false };
  if (used.size === 0) return { outfit: null, isRewear: false };
  const reused = scorer.generate(items, {
    desiredCount: 1,
    lockedItemIds: new Set(),
    excludedItemIds: new Set(),
  })[0];
  return { outfit: reused ?? null, isRewear: reused != null };
}
