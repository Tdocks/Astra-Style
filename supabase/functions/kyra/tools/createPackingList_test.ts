import { assert, assertEquals } from "@std/assert";
import type {
  OutfitScorer,
  OutfitScorerOptions,
  OutfitScorerRow,
} from "../../_shared/scoring/outfitScorer.ts";
import type { BriefRow, OccasionRow, OutfitDraft, PackingRepository } from "../../packing/plan.ts";
import {
  createPackingListDefinition,
  type CreatePackingListDeps,
  executeCreatePackingList,
  mapKyraLuggage,
  parseCreatePackingListArgs,
} from "./createPackingList.ts";
import { executePhase6Stub, PHASE6_STUB_DEFINITIONS } from "./phase6Stubs.ts";
import { buildToolRegistry, type ToolRegistryDeps } from "./registry.ts";

const USER = "aaaaaaaa-0000-4000-8000-000000000001";

function closetRow(id: string, category: string): OutfitScorerRow {
  return {
    id,
    category,
    last_worn_at: null,
    primary_color: category === "top" ? "navy" : "stone",
    secondary_colors: [],
    pattern: null,
    material: null,
    fit: null,
    seasonality: null,
    formality_score: null,
    warmth_score: null,
    water_resistance_score: null,
    laundry_state: "clean",
    availability_state: "available",
  };
}

const TWO_LOOKS: OutfitScorerRow[] = [
  closetRow("top-1", "top"),
  closetRow("top-2", "top"),
  closetRow("bottom-1", "bottom"),
  closetRow("bottom-2", "bottom"),
  closetRow("shoes-1", "shoes"),
  closetRow("shoes-2", "shoes"),
];

class RotationStubScorer implements OutfitScorer {
  generate(items: readonly OutfitScorerRow[], options: OutfitScorerOptions) {
    const available = items.filter((item) => !options.excludedItemIds.has(item.id));
    const top = available.find((item) => item.category === "top");
    const bottom = available.find((item) => item.category === "bottom");
    const shoes = available.find((item) => item.category === "shoes");
    if (!top || !bottom || !shoes) return [];
    return [{
      itemIds: [top.id, bottom.id, shoes.id],
      compatibilityScore: 0.8,
      reason: "Navy and Stone work together.",
    }];
  }
}

interface MemoryRepository extends PackingRepository {
  readonly created: OutfitDraft[];
}

function memoryRepository(
  closet: OutfitScorerRow[],
  occasions: OccasionRow[] = [],
): MemoryRepository {
  const briefs = new Map<string, BriefRow>();
  const created: OutfitDraft[] = [];
  const itemsByOutfit = new Map<string, string[]>();
  let sequence = 0;

  return {
    created,
    listCandidateItems() {
      return Promise.resolve(closet);
    },
    readWardrobeGraph() {
      return Promise.resolve("menswear_3_role" as const);
    },
    listOccasions() {
      return Promise.resolve(occasions);
    },
    findBriefs(_userId, dates) {
      return Promise.resolve(
        dates.flatMap((day) => {
          const row = briefs.get(day);
          return row ? [row] : [];
        }),
      );
    },
    createOutfits(_userId, drafts) {
      const ids = drafts.map((draft) => {
        created.push(draft);
        const id = `outfit-${++sequence}`;
        itemsByOutfit.set(id, [...draft.itemIds]);
        return id;
      });
      return Promise.resolve(ids);
    },
    upsertBrief(input) {
      const row: BriefRow = {
        id: `brief-${input.briefDate}`,
        user_id: input.userId,
        brief_date: input.briefDate,
        primary_outfit_id: input.primaryOutfitId,
        alternative_outfit_ids: [...input.alternativeOutfitIds],
        schedule_snapshot: input.scheduleSnapshot,
      };
      briefs.set(input.briefDate, row);
      return Promise.resolve(row);
    },
    listOutfitItemIds(outfitIds) {
      const ids = outfitIds.flatMap((id) => itemsByOutfit.get(id) ?? []);
      return Promise.resolve([...new Set(ids)]);
    },
  };
}

function packingDeps(
  repository: PackingRepository = memoryRepository(TWO_LOOKS),
): CreatePackingListDeps {
  return {
    userId: USER,
    repository,
    scorerForDay: () => new RotationStubScorer(),
  };
}

Deno.test("pinned schema still requires destination, start_date, end_date", () => {
  assertEquals(
    (createPackingListDefinition.parametersSchema as { required: string[] }).required,
    ["destination", "start_date", "end_date"],
  );
  const luggage = (
    createPackingListDefinition.parametersSchema as {
      properties: { luggage_constraint: { enum: string[] } };
    }
  ).properties.luggage_constraint.enum;
  assertEquals(luggage, ["carry_on", "checked", "none"]);
});

Deno.test("pinned luggage maps onto packing's internal constraint names", () => {
  assertEquals(mapKyraLuggage("carry_on"), "carry_on_only");
  assertEquals(mapKyraLuggage("checked"), "checked_bag");
  assertEquals(mapKyraLuggage("none"), "no_constraint");
  assertEquals(mapKyraLuggage(undefined), "no_constraint");
});

Deno.test("create_packing_list is not a Phase-6 stub", () => {
  assertEquals(
    PHASE6_STUB_DEFINITIONS.map((definition) => definition.name).includes("create_packing_list"),
    false,
  );
  const stub = executePhase6Stub("create_packing_list");
  assertEquals(stub["error"], "NOT_BUILT");
  assertEquals(stub["detail"], "Unknown stubbed tool.");
});

Deno.test("JWT-shaped args persist a real plan, not NOT_BUILT", async () => {
  const repo = memoryRepository(TWO_LOOKS);
  const result = await executeCreatePackingList(
    parseCreatePackingListArgs({
      destination: "Lisbon",
      start_date: "2026-08-24",
      end_date: "2026-08-25",
      activities: ["dinner"],
      luggage_constraint: "carry_on",
      laundry_access: true,
    }),
    packingDeps(repo),
  );
  assertEquals(result["available"], true);
  assertEquals(result["error"], undefined);
  const days = result["daily_outfit_plan"] as Array<Record<string, unknown>>;
  assertEquals(days.length, 2);
  assertEquals((result["packing_list_item_ids"] as string[]).length >= 3, true);
  assertEquals(repo.created.length, 2);
});

Deno.test("an invalid date range is a structured error, not an invented list", async () => {
  const repo = memoryRepository(TWO_LOOKS);
  const result = await executeCreatePackingList(
    parseCreatePackingListArgs({
      destination: "Lisbon",
      start_date: "2026-08-26",
      end_date: "2026-08-24",
    }),
    packingDeps(repo),
  );
  assertEquals(result["error"], "DATE_RANGE_INVALID");
  assertEquals(result["available"], undefined);
  assertEquals(result["daily_outfit_plan"], undefined);
  assertEquals(repo.created.length, 0);
});

Deno.test("empty destination fails without calling generate", async () => {
  const repo = memoryRepository(TWO_LOOKS);
  const result = await executeCreatePackingList(
    parseCreatePackingListArgs({
      destination: "  ",
      start_date: "2026-08-24",
      end_date: "2026-08-25",
    }),
    packingDeps(repo),
  );
  assertEquals(result["error"], "VALIDATION");
  assertEquals(repo.created.length, 0);
});

function unusedRegistryDeps(): ToolRegistryDeps {
  const unused = (): never => {
    throw new Error("unused");
  };
  return {
    searchCloset: { listClosetItems: unused },
    rankOutfits: {
      listItemsByIds: unused,
      listOutfitItemIds: unused,
      getOccasionTitle: unused,
      readWardrobeGraph: unused,
    },
    createOutfit: {
      listItemsByIds: unused,
      insertOutfit: unused,
      readWardrobeGraph: unused,
    },
    getWeather: { weatherSnapshot: null, now: () => new Date() },
    getSchedule: { listOccasions: unused, now: () => new Date() },
    savePreference: {
      sourceMessageId: USER,
      minimumConfidence: 0.7,
      listMemoriesByType: unused,
      insertMemory: unused,
      updateMemoryConfidence: unused,
      deleteMemory: unused,
    },
    markItemWorn: {
      triggeringUserText: "",
      now: () => new Date(),
      listOwnedItemIds: unused,
      getOutfitItemIds: unused,
      insertWornOutfit: unused,
      findWearOnDate: unused,
      insertWear: unused,
      readWearCounts: unused,
    },
    createPackingList: packingDeps(),
  };
}

Deno.test("registry routes create_packing_list to the real executor", async () => {
  const registry = buildToolRegistry(unusedRegistryDeps());
  assert(
    registry.definitions.some((definition) => definition.name === "create_packing_list"),
  );
  const result = await registry.execute("create_packing_list", {
    destination: "Lisbon",
    start_date: "2026-08-24",
    end_date: "2026-08-24",
  });
  assertEquals(result["available"], true);
  assertEquals(result["error"], undefined);
});
