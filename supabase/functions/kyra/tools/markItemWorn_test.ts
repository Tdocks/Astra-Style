import { assert, assertEquals } from "@std/assert";
import {
  executeMarkItemWorn,
  type MarkItemWornDeps,
  messageContainsWearEvidence,
} from "./markItemWorn.ts";

const BLAZER = "00000000-0000-4000-8000-000000000001";
const TROUSERS = "00000000-0000-4000-8000-000000000002";
const OUTFIT = "11111111-0000-4000-8000-000000000001";
const WRAPPER_OUTFIT = "11111111-0000-4000-8000-000000000002";
const WEAR = "44444444-0000-4000-8000-000000000001";

const NOW = () => new Date("2026-08-16T09:00:00Z");

interface Recorded {
  wornOutfits: Array<{ itemIds: readonly string[]; date: string }>;
  wears: Array<{ outfitId: string; wornAtIso: string; occasion: string | null }>;
}

function deps(
  triggeringUserText: string,
  recorded: Recorded,
  overrides: Partial<MarkItemWornDeps> = {},
): MarkItemWornDeps {
  return {
    triggeringUserText,
    now: NOW,
    listOwnedItemIds: (ids) =>
      Promise.resolve(ids.filter((id) => id === BLAZER || id === TROUSERS)),
    getOutfitItemIds: (outfitId) =>
      Promise.resolve(outfitId === OUTFIT ? [BLAZER, TROUSERS] : null),
    insertWornOutfit: (itemIds, date) => {
      recorded.wornOutfits.push({ itemIds, date });
      return Promise.resolve(WRAPPER_OUTFIT);
    },
    findWearOnDate: () => Promise.resolve(null),
    insertWear: (record) => {
      recorded.wears.push(record);
      return Promise.resolve(WEAR);
    },
    readWearCounts: (ids) => Promise.resolve(new Map(ids.map((id) => [id, 5]))),
    ...overrides,
  };
}

function emptyRecorded(): Recorded {
  return { wornOutfits: [], wears: [] };
}

Deno.test("the confirmation gate: no wear evidence in the user message -> nothing is written", async () => {
  const recorded = emptyRecorded();
  const result = await executeMarkItemWorn(
    { item_ids: [BLAZER] },
    deps("What should I wear tomorrow?", recorded),
  );
  assertEquals(result["error"], "CONFIRMATION_REQUIRED");
  assertEquals(recorded.wears.length, 0);
  assertEquals(recorded.wornOutfits.length, 0);
});

Deno.test("wear-evidence predicate: direct statements and affirmative replies pass, speculation fails", () => {
  assert(messageContainsWearEvidence("I wore the navy blazer today"));
  assert(messageContainsWearEvidence("wore this to the dinner last night"));
  assert(messageContainsWearEvidence("yes, mark it worn"));
  assert(messageContainsWearEvidence("Yep, that's what I ended up wearing"));
  assert(!messageContainsWearEvidence("I might wear the blazer tomorrow"));
  assert(!messageContainsWearEvidence("should I wear the blazer?"));
  // "Acceptance of a recommendation is not evidence of wear" (§3.2).
  assert(!messageContainsWearEvidence("sounds good, I like that outfit"));
});

Deno.test("item-only wear creates a real wrapper outfit, then records the wear", async () => {
  const recorded = emptyRecorded();
  const result = await executeMarkItemWorn(
    { item_ids: [BLAZER, TROUSERS] },
    deps("I wore the navy blazer and grey trousers today", recorded),
  );
  assertEquals(result["recorded"], true);
  assertEquals(result["outfit_id"], WRAPPER_OUTFIT);
  assertEquals(result["worn_at"], "2026-08-16");
  assertEquals(recorded.wornOutfits[0]?.itemIds, [BLAZER, TROUSERS]);
  assertEquals(recorded.wears[0]?.outfitId, WRAPPER_OUTFIT);
  // Counts come from a re-read of what the DB trigger did — not app math.
  assertEquals(result["updated_wear_counts"], { [BLAZER]: 5, [TROUSERS]: 5 });
});

Deno.test("outfit wear records against the existing outfit without a wrapper", async () => {
  const recorded = emptyRecorded();
  const result = await executeMarkItemWorn(
    { item_ids: [], outfit_id: OUTFIT, occasion: "dinner" },
    deps("yes, mark it worn", recorded),
  );
  assertEquals(result["recorded"], true);
  assertEquals(result["outfit_id"], OUTFIT);
  assertEquals(recorded.wornOutfits.length, 0);
  assertEquals(recorded.wears[0]?.occasion, "dinner");
});

Deno.test("§3.10 idempotency: a same-day duplicate returns the existing record, no insert", async () => {
  const recorded = emptyRecorded();
  const result = await executeMarkItemWorn(
    { item_ids: [], outfit_id: OUTFIT },
    deps("I wore that today", recorded, {
      findWearOnDate: () => Promise.resolve({ id: WEAR }),
    }),
  );
  assertEquals(result["error"], "DUPLICATE_ENTRY_SAME_DAY");
  assertEquals(result["duplicate_of"], WEAR);
  assertEquals(recorded.wears.length, 0); // the trigger never re-fires
});

Deno.test("an unowned item refuses rather than recording a smaller claim", async () => {
  const recorded = emptyRecorded();
  const missing = "00000000-0000-4000-8000-00000000dead";
  const result = await executeMarkItemWorn(
    { item_ids: [BLAZER, missing] },
    deps("I wore these today", recorded),
  );
  assertEquals(result["error"], "ITEM_NOT_FOUND");
  assertEquals(result["missing_item_ids"], [missing]);
  assertEquals(recorded.wears.length, 0);
});

Deno.test("a future worn_at is refused — the future has not been worn", async () => {
  const recorded = emptyRecorded();
  const result = await executeMarkItemWorn(
    { item_ids: [BLAZER], worn_at: "2027-01-01" },
    deps("I wore it", recorded),
  );
  assertEquals(result["error"], "INVALID_DATE");
});
