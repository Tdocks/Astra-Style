import { assert, assertEquals } from "@std/assert";
import {
  colorMatches,
  executeSearchCloset,
  parseSearchClosetArgs,
  type SearchClosetRow,
} from "./searchCloset.ts";

function row(overrides: Partial<SearchClosetRow> & { id: string }): SearchClosetRow {
  return {
    category: "top",
    subcategory: "oxford shirt",
    brand: null,
    primary_color: "navy",
    formality_score: 55,
    fit: "regular",
    availability_state: "available",
    laundry_state: "clean",
    wear_count: 2,
    last_worn_at: "2026-08-01T00:00:00Z",
    ...overrides,
  };
}

const CLOSET: SearchClosetRow[] = [
  row({ id: "00000000-0000-4000-8000-000000000001", category: "top", primary_color: "navy" }),
  row({ id: "00000000-0000-4000-8000-000000000002", category: "top", primary_color: "olive" }),
  row({
    id: "00000000-0000-4000-8000-000000000003",
    category: "bottom",
    subcategory: "chino",
    primary_color: "navy",
  }),
  row({
    id: "00000000-0000-4000-8000-000000000004",
    category: "top",
    primary_color: "light blue",
    laundry_state: "laundry",
  }),
];

Deno.test("P5-KYRA-04: 'blue tops' returns only tops whose color ≈ blue", async () => {
  const result = await executeSearchCloset(
    parseSearchClosetArgs({ category: ["top"], color: ["blue"] }),
    { listClosetItems: () => Promise.resolve(CLOSET) },
  );
  const items = result["items"] as Array<{ id: string }>;
  // Navy is ≈ blue; olive is not; the chino is a bottom; the light-blue top
  // is in the laundry and availability_only defaults to true.
  assertEquals(items.map((item) => item.id), ["00000000-0000-4000-8000-000000000001"]);
  assertEquals(result["total_matched"], 1);
});

Deno.test("availability_only=false surfaces laundry items too", async () => {
  const result = await executeSearchCloset(
    parseSearchClosetArgs({ category: ["top"], color: ["blue"], availability_only: false }),
    { listClosetItems: () => Promise.resolve(CLOSET) },
  );
  const items = result["items"] as Array<{ id: string }>;
  assertEquals(items.length, 2);
  assert(items.some((item) => item.id === "00000000-0000-4000-8000-000000000004"));
});

Deno.test("empty closet is EMPTY_CLOSET, not a query error", async () => {
  const result = await executeSearchCloset(
    parseSearchClosetArgs({}),
    { listClosetItems: () => Promise.resolve([]) },
  );
  assertEquals(result["error"], "EMPTY_CLOSET");
  assertEquals(result["items"], []);
});

Deno.test("formality range and fit filters apply", async () => {
  const result = await executeSearchCloset(
    parseSearchClosetArgs({ formality_min: 50, formality_max: 60, fit: ["regular"] }),
    { listClosetItems: () => Promise.resolve(CLOSET) },
  );
  const items = result["items"] as Array<{ formality_score: number }>;
  assert(items.length > 0);
  for (const item of items) {
    assert(item.formality_score >= 50 && item.formality_score <= 60);
  }
});

Deno.test("colorMatches: exact, substring, hue family — and no match through residual hue", () => {
  assert(colorMatches("navy", "navy"));
  assert(colorMatches("blue", "light blue"));
  assert(colorMatches("blue", "navy")); // hue family in LCh
  assert(!colorMatches("blue", "grey")); // near-zero chroma never hue-matches
  assert(!colorMatches("blue", "olive"));
  assert(!colorMatches("blue", null));
});

Deno.test("malformed model args degrade to defaults instead of throwing", async () => {
  const args = parseSearchClosetArgs({
    category: "top", // should be an array
    limit: "many",
    formality_min: 12.5,
  });
  assertEquals(args.category, []);
  assertEquals(args.limit, 20);
  assertEquals(args.formalityMin, undefined);
  const result = await executeSearchCloset(args, {
    listClosetItems: () => Promise.resolve(CLOSET),
  });
  assertEquals(result["total_matched"], 3); // availability filter only
});
