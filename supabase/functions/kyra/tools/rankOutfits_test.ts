import { assert, assertEquals } from "@std/assert";
import type { ClosetItemMapperRow } from "../../_shared/scoring/closetItemMapper.ts";
import { executeRankOutfits, parseRankOutfitsArgs, type RankOutfitsDeps } from "./rankOutfits.ts";

const TOP = "00000000-0000-4000-8000-000000000001";
const BOTTOM = "00000000-0000-4000-8000-000000000002";
const SHOES = "00000000-0000-4000-8000-000000000003";
const CLASHING_TOP = "00000000-0000-4000-8000-000000000004";
const MISSING = "00000000-0000-4000-8000-00000000dead";
const OUTFIT_ID = "11111111-0000-4000-8000-000000000001";

function mapperRow(
  id: string,
  category: string,
  color: string,
  formality: number,
): ClosetItemMapperRow {
  return {
    id,
    category,
    primary_color: color,
    secondary_colors: [],
    pattern: "solid",
    material: [],
    fit: "regular",
    seasonality: [],
    formality_score: formality,
    warmth_score: 40,
    water_resistance_score: 20,
    laundry_state: "clean",
    availability_state: "available",
  };
}

const ROWS: ClosetItemMapperRow[] = [
  mapperRow(TOP, "top", "navy", 50),
  mapperRow(BOTTOM, "bottom", "stone", 50),
  mapperRow(SHOES, "shoes", "white", 45),
  mapperRow(CLASHING_TOP, "top", "orange", 5),
];

function deps(overrides: Partial<RankOutfitsDeps> = {}): RankOutfitsDeps {
  return {
    listItemsByIds: (ids) => Promise.resolve(ROWS.filter((row) => ids.includes(row.id))),
    listOutfitItemIds: () => Promise.resolve(new Map([[OUTFIT_ID, [TOP, BOTTOM, SHOES]]])),
    getOccasionTitle: () => Promise.resolve(null),
    readWardrobeGraph: () => Promise.resolve("menswear_3_role"),
    ...overrides,
  };
}

Deno.test("no candidates is NO_CANDIDATES_PROVIDED", async () => {
  const result = await executeRankOutfits(parseRankOutfitsArgs({}), deps());
  assertEquals(result["error"], "NO_CANDIDATES_PROVIDED");
});

Deno.test("ranks ad-hoc combinations by the shared §10 engine, best first", async () => {
  const result = await executeRankOutfits(
    parseRankOutfitsArgs({
      candidate_item_combinations: [[CLASHING_TOP, BOTTOM, SHOES], [TOP, BOTTOM, SHOES]],
    }),
    deps(),
  );
  const ranked = result["ranked"] as Array<Record<string, unknown>>;
  assertEquals(ranked.length, 2);
  const first = ranked[0]!;
  const second = ranked[1]!;
  assert((first["compatibility_score"] as number) >= (second["compatibility_score"] as number));
  // The coherent navy/stone/white set must beat the clashing orange/formality-5 set.
  assertEquals(first["outfit_ref"], "combination_2");
  assert(first["component_breakdown"] !== undefined);
});

Deno.test("saved outfit ids resolve through outfit_items and rank under their real id", async () => {
  const result = await executeRankOutfits(
    parseRankOutfitsArgs({ candidate_outfit_ids: [OUTFIT_ID] }),
    deps(),
  );
  const ranked = result["ranked"] as Array<Record<string, unknown>>;
  assertEquals(ranked.length, 1);
  assertEquals(ranked[0]!["outfit_ref"], OUTFIT_ID);
});

Deno.test("a candidate with an unresolvable item is dropped, not partially scored", async () => {
  const result = await executeRankOutfits(
    parseRankOutfitsArgs({
      candidate_item_combinations: [[TOP, MISSING], [TOP, BOTTOM, SHOES]],
    }),
    deps(),
  );
  const ranked = result["ranked"] as Array<Record<string, unknown>>;
  assertEquals(ranked.length, 1);
  assertEquals(result["dropped_candidates"], ["combination_1"]);
});

Deno.test("every candidate unresolvable is ITEM_NOT_FOUND", async () => {
  const result = await executeRankOutfits(
    parseRankOutfitsArgs({ candidate_item_combinations: [[MISSING]] }),
    deps(),
  );
  assertEquals(result["error"], "ITEM_NOT_FOUND");
});

Deno.test("target_formality yields a measured distance, omitted when unmeasurable", async () => {
  const result = await executeRankOutfits(
    parseRankOutfitsArgs({
      candidate_item_combinations: [[TOP, BOTTOM, SHOES]],
      target_formality: 80,
    }),
    deps(),
  );
  const ranked = result["ranked"] as Array<Record<string, unknown>>;
  // Items sit at 50/50/45 → mean distance from 80 is about 31-32.
  const distance = ranked[0]!["target_formality_distance"] as number;
  assert(distance >= 30 && distance <= 32);
});
