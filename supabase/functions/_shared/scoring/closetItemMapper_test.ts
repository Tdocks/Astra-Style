import { assertEquals } from "@std/assert";
import { type ClosetItemMapperRow, mapClosetItemRowToScorableItem } from "./closetItemMapper.ts";

function row(overrides: Partial<ClosetItemMapperRow> = {}): ClosetItemMapperRow {
  return {
    id: "item-1",
    category: "top",
    primary_color: "navy",
    secondary_colors: [],
    pattern: "solid",
    material: [],
    fit: "regular",
    seasonality: [],
    formality_score: 50,
    warmth_score: 40,
    water_resistance_score: 10,
    laundry_state: "clean",
    availability_state: "available",
    ...overrides,
  };
}

Deno.test("maps a fully-populated row onto a ScorableItem", () => {
  const item = mapClosetItemRowToScorableItem(row());
  assertEquals(item?.id, "item-1");
  assertEquals(item?.role, "top");
  assertEquals(item?.pattern, "solid");
  assertEquals(item?.fit, "regular");
  assertEquals(item?.formalityScore, 50);
  assertEquals(item?.warmthScore, 40);
  assertEquals(item?.waterResistanceScore, 10);
  assertEquals(item?.laundryState, "clean");
  assertEquals(item?.availabilityState, "available");
  assertEquals(item?.colorName, "navy");
  assertEquals(item?.primaryColor !== null, true);
  assertEquals(item?.isNeutral, true); // navy is a curated neutral band
});

Deno.test("fragrance has no scoring role and maps to null", () => {
  assertEquals(mapClosetItemRowToScorableItem(row({ category: "fragrance" })), null);
});

Deno.test("watch folds into the accessory role", () => {
  const item = mapClosetItemRowToScorableItem(row({ category: "watch" }));
  assertEquals(item?.role, "accessory");
});

Deno.test("an unresolvable primary_color word resolves to null, never a guess", () => {
  const item = mapClosetItemRowToScorableItem(row({ primary_color: "burnt sienna" }));
  assertEquals(item?.primaryColor, null);
  assertEquals(item?.isNeutral, false);
});

Deno.test("a null primary_color resolves the same way as an unknown word", () => {
  const item = mapClosetItemRowToScorableItem(row({ primary_color: null }));
  assertEquals(item?.primaryColor, null);
});

Deno.test("secondary_colors resolves known words and silently drops unknown ones", () => {
  const item = mapClosetItemRowToScorableItem(
    row({ secondary_colors: ["white", "an unrecognised word", "olive"] }),
  );
  assertEquals(item?.secondaryColors.length, 2);
});

Deno.test("a non-array secondary_colors value degrades to an empty list rather than throwing", () => {
  const item = mapClosetItemRowToScorableItem(row({ secondary_colors: { not: "an array" } }));
  assertEquals(item?.secondaryColors, []);
});

Deno.test("pattern 'textured' is not a known Pattern union member and maps to null", () => {
  const item = mapClosetItemRowToScorableItem(row({ pattern: "textured" }));
  assertEquals(item?.pattern, null);
});

Deno.test("every real Pattern union member round-trips exactly", () => {
  for (const p of ["solid", "stripe", "check", "herringbone", "print", "texture-only"]) {
    const item = mapClosetItemRowToScorableItem(row({ pattern: p }));
    assertEquals(item?.pattern, p);
  }
});

Deno.test("an unrecognised fit value maps to null rather than an invented default", () => {
  const item = mapClosetItemRowToScorableItem(row({ fit: "athletic" }));
  assertEquals(item?.fit, null);
});

Deno.test("material fiber objects are extracted and lowercased", () => {
  const item = mapClosetItemRowToScorableItem(
    row({ material: [{ fiber: "Cotton", percentage: 98 }, { fiber: "ELASTANE", percentage: 2 }] }),
  );
  assertEquals(item?.materials, ["cotton", "elastane"]);
});

Deno.test("bare string material entries are also accepted", () => {
  const item = mapClosetItemRowToScorableItem(row({ material: ["Wool"] }));
  assertEquals(item?.materials, ["wool"]);
});

Deno.test("seasonality drops values outside the four-season union, e.g. 'all_season'", () => {
  const item = mapClosetItemRowToScorableItem(
    row({ seasonality: ["spring", "all_season", "winter"] }),
  );
  assertEquals(item?.seasonality, ["spring", "winter"]);
});

Deno.test("null formality/warmth/water-resistance pass through as null, not a default", () => {
  const item = mapClosetItemRowToScorableItem(
    row({ formality_score: null, warmth_score: null, water_resistance_score: null }),
  );
  assertEquals(item?.formalityScore, null);
  assertEquals(item?.warmthScore, null);
  assertEquals(item?.waterResistanceScore, null);
});

Deno.test("last_worn_at parses to a Date when the row has one", () => {
  const item = mapClosetItemRowToScorableItem(
    row({ last_worn_at: "2026-08-22T08:00:00.000Z" }),
  );
  assertEquals(item?.lastWornAt?.toISOString(), "2026-08-22T08:00:00.000Z");
});

Deno.test("a missing last_worn_at is never-worn, not a guess", () => {
  const item = mapClosetItemRowToScorableItem(row());
  assertEquals(item?.lastWornAt, null);
});

Deno.test("an unparseable last_worn_at degrades to never-worn rather than Invalid Date", () => {
  const item = mapClosetItemRowToScorableItem(row({ last_worn_at: "not a timestamp" }));
  assertEquals(item?.lastWornAt, null);
});
