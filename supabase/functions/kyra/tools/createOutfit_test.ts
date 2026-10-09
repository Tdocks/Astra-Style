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
const COMPETING_TOP = "00000000-0000-4000-8000-000000000004";
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

const ROWS = [
  mapperRow(TOP, "top"),
  mapperRow(BOTTOM, "bottom"),
  mapperRow(SHOES, "shoes"),
  mapperRow(COMPETING_TOP, "top"),
];

function deps(
  captured: NewOutfitRecord[],
  lockedItemIDs: readonly string[] = [],
): CreateOutfitDeps {
  return {
    listItemsByIds: (ids) => Promise.resolve(ROWS.filter((row) => ids.includes(row.id))),
    insertOutfit: (record) => {
      captured.push(record);
      return Promise.resolve(NEW_OUTFIT);
    },
    readWardrobeGraph: () => Promise.resolve("menswear_3_role"),
    lockedItemIDs,
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

Deno.test("free Kyra generations atomically persist and replay the exact committed outfit", async () => {
  const captured: NewOutfitRecord[] = [];
  let reservationCalls = 0;
  let commitCalls = 0;
  const identities: Array<{ requestID: string; fingerprint: string }> = [];
  const original = deps(captured);
  const result = await executeCreateOutfit(
    parseCreateOutfitArgs({
      item_ids: [TOP, BOTTOM, SHOES],
      reason: "A balanced outfit.",
      occasion_tags: ["daily"],
    }),
    {
      ...original,
      quotaUserID: "aaaaaaaa-0000-4000-8000-000000000001",
      outerRequestID: "request-stable-for-replay",
      toolCallID: "call-stable-for-replay",
      generationQuota: {
        isPremium: () => Promise.resolve(false),
        reserve: (_userID, requestID, fingerprint) => {
          identities.push({ requestID, fingerprint });
          reservationCalls++;
          if (reservationCalls === 1) {
            return Promise.resolve({
              allowed: true,
              remaining: 4,
              resetsAt: "2026-10-10T00:00:00Z",
              limitCount: 5,
              reservation_id: "44444444-0000-4000-8000-000000000001",
              replay_payload: null,
              in_flight: false,
            });
          }
          return Promise.resolve({
            allowed: true,
            remaining: 4,
            resetsAt: "2026-10-10T00:00:00Z",
            limitCount: 5,
            reservation_id: "44444444-0000-4000-8000-000000000001",
            replay_payload: [{ outfit_id: NEW_OUTFIT, source: "kyra_suggested" }],
            in_flight: false,
          });
        },
        finish: () => Promise.resolve(),
      },
      commitOutfitGeneration: (input) => {
        commitCalls++;
        captured.push(input.record);
        assertEquals(input.reservationID, "44444444-0000-4000-8000-000000000001");
        return Promise.resolve({ outfit_id: NEW_OUTFIT, source: "kyra_suggested" });
      },
      insertOutfit: () => Promise.reject(new Error("non-atomic insert must not be used")),
    },
  );
  const replay = await executeCreateOutfit(
    parseCreateOutfitArgs({
      item_ids: [TOP, BOTTOM, SHOES],
      reason: "A balanced outfit.",
      occasion_tags: ["daily"],
    }),
    {
      ...original,
      quotaUserID: "aaaaaaaa-0000-4000-8000-000000000001",
      outerRequestID: "request-stable-for-replay",
      toolCallID: "call-stable-for-replay",
      generationQuota: {
        isPremium: () => Promise.resolve(false),
        reserve: (_userID, requestID, fingerprint) => {
          identities.push({ requestID, fingerprint });
          reservationCalls++;
          return Promise.resolve({
            allowed: true,
            remaining: 4,
            resetsAt: "2026-10-10T00:00:00Z",
            limitCount: 5,
            reservation_id: "44444444-0000-4000-8000-000000000001",
            replay_payload: [{ outfit_id: NEW_OUTFIT, source: "kyra_suggested" }],
            in_flight: false,
          });
        },
        finish: () => Promise.resolve(),
      },
      commitOutfitGeneration: (input) => {
        commitCalls++;
        captured.push(input.record);
        return Promise.resolve({ outfit_id: NEW_OUTFIT, source: "kyra_suggested" });
      },
      insertOutfit: () => Promise.reject(new Error("non-atomic insert must not be used")),
    },
  );
  assertEquals(result["outfit_id"], NEW_OUTFIT);
  assertEquals(replay["outfit_id"], NEW_OUTFIT);
  assertEquals(commitCalls, 1);
  assertEquals(captured.length, 1);
  assertEquals(identities.length, 2);
  assertEquals(identities[1], identities[0]);
});

Deno.test("failed atomic outfit persistence releases its reserved generation slot", async () => {
  const captured: NewOutfitRecord[] = [];
  const finishes: boolean[] = [];
  let failed = false;
  try {
    await executeCreateOutfit(
      parseCreateOutfitArgs({ item_ids: [TOP, BOTTOM, SHOES], reason: "A complete look." }),
      {
        ...deps(captured),
        quotaUserID: "aaaaaaaa-0000-4000-8000-000000000001",
        outerRequestID: "failed-atomic-request",
        toolCallID: "failed-atomic-call",
        generationQuota: {
          isPremium: () => Promise.resolve(false),
          reserve: () =>
            Promise.resolve({
              allowed: true,
              remaining: 4,
              resetsAt: "2026-10-10T00:00:00Z",
              limitCount: 5,
              reservation_id: "44444444-0000-4000-8000-000000000002",
              replay_payload: null,
              in_flight: false,
            }),
          finish: (_userID, _reservationID, succeeded) => {
            finishes.push(succeeded);
            return Promise.resolve();
          },
        },
        commitOutfitGeneration: () => Promise.reject(new Error("database unavailable")),
        insertOutfit: () => Promise.reject(new Error("non-atomic insert must not be used")),
      },
    );
  } catch {
    failed = true;
  }
  assert(failed);
  assertEquals(finishes, [false]);
  assertEquals(captured, []);
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
    {
      ...deps(captured),
      listProductCandidateCategories: () => Promise.resolve(new Map([[PRODUCT, "shoes"]])),
    },
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

Deno.test("builder preserves the locked garment over a conflicting model role", async () => {
  const captured: NewOutfitRecord[] = [];
  const result = await executeCreateOutfit(
    parseCreateOutfitArgs({
      item_ids: [COMPETING_TOP, BOTTOM, SHOES],
      reason: "The locked top anchors the look.",
    }),
    { ...deps(captured, [TOP]), allowProductCandidates: false, requireReason: true },
  );
  assertEquals(result["item_ids"], [BOTTOM, SHOES, TOP]);
  assertEquals(
    captured[0]?.items.filter((item) => item.role === "top").map((item) => item.closetItemId),
    [TOP],
  );
});

Deno.test("builder rejects duplicate locked roles, product slots, and missing reasons", async () => {
  const captured: NewOutfitRecord[] = [];
  const duplicateRoles = await executeCreateOutfit(
    parseCreateOutfitArgs({ item_ids: [BOTTOM, SHOES], reason: "Keep the locks." }),
    { ...deps(captured, [TOP, COMPETING_TOP]), requireReason: true },
  );
  const product = await executeCreateOutfit(
    {
      ...parseCreateOutfitArgs({ item_ids: [TOP, BOTTOM, SHOES], reason: "Reason." }),
      productCandidateIds: [PRODUCT],
    },
    { ...deps(captured), allowProductCandidates: false, requireReason: true },
  );
  const noReason = await executeCreateOutfit(
    parseCreateOutfitArgs({ item_ids: [TOP, BOTTOM, SHOES] }),
    { ...deps(captured), allowProductCandidates: false, requireReason: true },
  );
  assertEquals(duplicateRoles["error"], "CONFLICTING_LOCKED_ROLES");
  assertEquals(product["error"], "OWNED_ITEMS_ONLY");
  assertEquals(noReason["error"], "REASON_REQUIRED");
  assertEquals(captured, []);
});
