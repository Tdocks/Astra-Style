import { assert, assertEquals } from "@std/assert";
import type { ClosetItemMapperRow } from "../../_shared/scoring/closetItemMapper.ts";
import {
  type CreateOutfitDeps,
  executeCreateOutfit,
  type NewOutfitRecord,
  parseCreateOutfitArgs,
} from "./createOutfit.ts";

const TOP = "00000000-0000-4000-8000-000000000001";
const BOTTOM = "00000000-0000-4000-8000-000000000002";
const SHOES = "00000000-0000-4000-8000-000000000003";
const PRODUCT = "22222222-0000-4000-8000-000000000001";
const NEW_OUTFIT = "33333333-0000-4000-8000-000000000001";

function mapperRow(id: string, category: string): ClosetItemMapperRow {
  return {
    id,
    category,
    primary_color: "navy",
    secondary_colors: [],
    pattern: "solid",
    material: [],
    fit: "regular",
    seasonality: [],
    formality_score: 50,
    warmth_score: 40,
    water_resistance_score: 20,
    laundry_state: "clean",
    availability_state: "available",
  };
}

const ROWS = [mapperRow(TOP, "top"), mapperRow(BOTTOM, "bottom"), mapperRow(SHOES, "shoes")];

function deps(captured: NewOutfitRecord[]): CreateOutfitDeps {
  return {
    listItemsByIds: (ids) => Promise.resolve(ROWS.filter((row) => ids.includes(row.id))),
    insertOutfit: (record) => {
      captured.push(record);
      return Promise.resolve(NEW_OUTFIT);
    },
    readWardrobeGraph: () => Promise.resolve("menswear_3_role"),
  };
}

Deno.test("persists a real outfit with items, score, and kyra_suggested source", async () => {
  const captured: NewOutfitRecord[] = [];
  const result = await executeCreateOutfit(
    parseCreateOutfitArgs({
      item_ids: [TOP, BOTTOM, SHOES],
      name: "Dinner look",
      occasion_tags: ["dinner"],
      reason: "Moves cleanly from work to dinner.",
    }),
    deps(captured),
  );
  assertEquals(result["outfit_id"], NEW_OUTFIT);
  // The enum has no "kyra_draft"; the row and the response say what was written.
  assertEquals(result["source"], "kyra_suggested");
  assertEquals(result["reason"], "Moves cleanly from work to dinner.");
  assert(typeof result["compatibility_score"] === "number");

  assertEquals(captured.length, 1);
  const record = captured[0]!;
  assertEquals(record.source, "kyra_suggested");
  assertEquals(record.items.length, 3);
  assertEquals(record.items[0]?.closetItemId, TOP);
  assertEquals(record.items[0]?.role, "top");
  assertEquals(record.compatibilityScore, result["compatibility_score"]);
});

Deno.test("an unowned/unknown item id fails with ITEM_NOT_FOUND, nothing persisted", async () => {
  const captured: NewOutfitRecord[] = [];
  const missing = "00000000-0000-4000-8000-00000000dead";
  const result = await executeCreateOutfit(
    parseCreateOutfitArgs({ item_ids: [TOP, missing] }),
    deps(captured),
  );
  assertEquals(result["error"], "ITEM_NOT_FOUND");
  assertEquals(result["missing_item_ids"], [missing]);
  assertEquals(captured.length, 0);
});

Deno.test("top+bottom without shoes is MINIMUM_ROLES_NOT_MET", async () => {
  const captured: NewOutfitRecord[] = [];
  const result = await executeCreateOutfit(
    parseCreateOutfitArgs({ item_ids: [TOP, BOTTOM] }),
    deps(captured),
  );
  assertEquals(result["error"], "MINIMUM_ROLES_NOT_MET");
  assertEquals(captured.length, 0);
});

Deno.test("a product-candidate slot may cover a missing role (complete-the-look)", async () => {
  const captured: NewOutfitRecord[] = [];
  const result = await executeCreateOutfit(
    parseCreateOutfitArgs({ item_ids: [TOP, BOTTOM], product_candidate_ids: [PRODUCT] }),
    deps(captured),
  );
  assertEquals(result["outfit_id"], NEW_OUTFIT);
  const record = captured[0]!;
  assertEquals(record.items.length, 3);
  const productSlot = record.items[2]!;
  assertEquals(productSlot.closetItemId, null);
  assertEquals(productSlot.productCandidateId, PRODUCT);
});

Deno.test("empty item_ids is rejected before any read", async () => {
  const captured: NewOutfitRecord[] = [];
  const result = await executeCreateOutfit(parseCreateOutfitArgs({}), deps(captured));
  assertEquals(result["error"], "ITEM_NOT_FOUND");
});
