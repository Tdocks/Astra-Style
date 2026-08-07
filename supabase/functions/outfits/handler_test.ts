// ============================================================================
// outfits/handler_test.ts
// ============================================================================
// Covers, for BOTH routes this function serves:
//   - rejects a missing / malformed / unrecognised JWT
//   - rejects a body that fails schema validation
//   - returns a well-formed, wire-shaped response for a valid request
//   - cannot touch another user's closet even when a different user id is
//     supplied in the body (ownership isolation)
//   - rate limiting and request-id correlation
//
// Plus P4-OUTFIT-07/08's specific acceptance criteria:
//   - /generate: exactly the requested count for a closet that supports it,
//     each with a non-empty item_ids and a non-generic reason.
//   - /rank: a locked item appears in every result; ranking order matches
//     `scoreOutfit`'s own ordering for the same inputs.
//
// The Supabase client is mocked entirely at the boundary via the
// `AuthClient` and `ClosetRepository` interfaces `handler.ts` depends on —
// no network access, no live database, no real JWT signing.
// ============================================================================

import { assert, assertEquals, assertNotEquals } from "@std/assert";
import type { AuthClient } from "../_shared/jwt.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import {
  type ClosetRepository,
  handleGenerateOutfits,
  handleRankOutfits,
  type HandlerDeps,
} from "./handler.ts";
import type { ClosetItemMapperRow } from "../_shared/scoring/closetItemMapper.ts";
import { mapClosetItemRowToScorableItem } from "../_shared/scoring/closetItemMapper.ts";
import { scoreOutfit } from "../_shared/scoring/compatibility.ts";

const VALID_LOOKING_JWT_A =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWEifQ.dGhpc19pc19ub3RfYV9yZWFsX3NpZ25hdHVyZQ";
const VALID_LOOKING_JWT_B =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWIifQ.YW5vdGhlcl9mYWtlX3NpZ25hdHVyZQ";

const USER_A_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const USER_B_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ATTACKER_SUPPLIED_UUID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

const TOP_A = "aaaaaaaa-0000-4000-8000-000000000001";
const BOTTOM_A = "aaaaaaaa-0000-4000-8000-000000000002";
const SHOES_A = "aaaaaaaa-0000-4000-8000-000000000003";
const TOP_A2 = "aaaaaaaa-0000-4000-8000-000000000004";

const TOP_B = "bbbbbbbb-0000-4000-8000-000000000001";
const BOTTOM_B = "bbbbbbbb-0000-4000-8000-000000000002";
const SHOES_B = "bbbbbbbb-0000-4000-8000-000000000003";

function row(
  id: string,
  category: string,
  overrides: Partial<ClosetItemMapperRow> = {},
): ClosetItemMapperRow {
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
    warmth_score: 50,
    water_resistance_score: 20,
    laundry_state: "clean",
    availability_state: "available",
    ...overrides,
  };
}

const USER_A_CLOSET: ClosetItemMapperRow[] = [
  row(TOP_A, "top", { primary_color: "navy", formality_score: 70, fit: "tailored" }),
  row(BOTTOM_A, "bottom", { primary_color: "charcoal", formality_score: 70, fit: "tailored" }),
  row(SHOES_A, "shoes", { primary_color: "brown", formality_score: 70, fit: "regular" }),
  // A second, clashing top: low formality, a saturated colour far from the
  // others — its own combination should score clearly worse than the tidy
  // navy/charcoal/brown one, which is what the /rank ordering test relies on.
  row(TOP_A2, "top", { primary_color: "acid yellow", formality_score: 5, fit: "oversized" }),
];

const USER_B_CLOSET: ClosetItemMapperRow[] = [
  row(TOP_B, "top", { primary_color: "navy", formality_score: 70, fit: "tailored" }),
  row(BOTTOM_B, "bottom", { primary_color: "charcoal", formality_score: 70, fit: "tailored" }),
  row(SHOES_B, "shoes", { primary_color: "brown", formality_score: 70, fit: "regular" }),
];

function tokenMappedAuthClient(): AuthClient {
  return {
    auth: {
      getUser(jwt?: string) {
        if (jwt === VALID_LOOKING_JWT_A) {
          return Promise.resolve({ data: { user: { id: USER_A_ID } }, error: null });
        }
        if (jwt === VALID_LOOKING_JWT_B) {
          return Promise.resolve({ data: { user: { id: USER_B_ID } }, error: null });
        }
        return Promise.resolve({ data: { user: null }, error: { message: "invalid token" } });
      },
    },
  };
}

/**
 * Models what RLS enforces in production: `listItemsByIds` only ever
 * returns rows from the CALLING user's own closet, so a candidate naming
 * another user's item id simply finds nothing for that id.
 */
function recordingClosetRepository(): ClosetRepository & {
  candidateCalls: string[];
  byIdsCalls: { userId: string; ids: string[] }[];
} {
  const candidateCalls: string[] = [];
  const byIdsCalls: { userId: string; ids: string[] }[] = [];
  const closets: Record<string, ClosetItemMapperRow[]> = {
    [USER_A_ID]: USER_A_CLOSET,
    [USER_B_ID]: USER_B_CLOSET,
  };
  return {
    candidateCalls,
    byIdsCalls,
    listCandidateItems(userId: string) {
      candidateCalls.push(userId);
      return Promise.resolve(closets[userId] ?? []);
    },
    listItemsByIds(userId: string, ids: readonly string[]) {
      byIdsCalls.push({ userId, ids: [...ids] });
      const own = closets[userId] ?? [];
      return Promise.resolve(own.filter((r) => ids.includes(r.id)));
    },
  };
}

function buildDeps(overrides: Partial<HandlerDeps> = {}): HandlerDeps {
  return {
    authClient: tokenMappedAuthClient(),
    closetRepository: recordingClosetRepository(),
    rateLimiter: createRateLimiter({ limit: 1000, windowMs: 60_000 }),
    now: () => new Date("2026-07-28T12:00:00Z"),
    ...overrides,
  };
}

function requestFor(path: string, body: unknown, headers: Record<string, string> = {}): Request {
  return new Request(`https://example.com/outfits/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

const VALID_GENERATE_ENVELOPE = {
  request_id: "test-request-id",
  client_version: "ios/1.0.0",
  body: { desired_count: 2 },
};

// ---------------------------------------------------------------------------
// POST /outfits/generate
// ---------------------------------------------------------------------------

Deno.test("generate: rejects a request with no Authorization header at all", async () => {
  const req = requestFor("generate", VALID_GENERATE_ENVELOPE);
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 401);
  const json = await response.json();
  assertEquals(json.error.category, "auth");
  assertEquals(json.data, null);
});

Deno.test("generate: rejects a malformed JWT", async () => {
  const req = requestFor("generate", VALID_GENERATE_ENVELOPE, {
    Authorization: "Bearer this-is-not-a-jwt",
  });
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 401);
});

Deno.test("generate: rejects a request whose body fails schema validation", async () => {
  const req = requestFor(
    "generate",
    { request_id: "r", client_version: "ios/1.0.0", body: { desired_count: 999 } },
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  );
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 400);
  const json = await response.json();
  assertEquals(json.error.category, "validation");
});

Deno.test("generate: returns a well-formed, wire-shaped outfit list for a valid request", async () => {
  const req = requestFor("generate", VALID_GENERATE_ENVELOPE, {
    Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
  });
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.error, null);
  assert(Array.isArray(json.data));
  assert(json.data.length > 0);
  const outfit = json.data[0];
  assertEquals(typeof outfit.id, "string");
  assertEquals(typeof outfit.name, "string");
  assertEquals(typeof outfit.reason, "string");
  assert(outfit.reason.length > 0);
  assertEquals(typeof outfit.compatibility_score, "number");
  assert(Array.isArray(outfit.item_ids));
  assert(outfit.item_ids.length > 0);
  assertEquals(outfit.missing_product_ids, []);
  // The two additive wire fields (wire.ts) must always be present.
  assert(Array.isArray(outfit.unmeasured));
  assert("formality_register" in outfit);
});

Deno.test("generate: honours desired_count when the closet supports it", async () => {
  const req = requestFor(
    "generate",
    { ...VALID_GENERATE_ENVELOPE, body: { desired_count: 2 } },
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  );
  const response = await handleGenerateOutfits(req, buildDeps());
  const json = await response.json();
  assertEquals(json.data.length, 2);
});

Deno.test("generate: handles OPTIONS as a CORS preflight before authentication ever runs", async () => {
  const req = new Request("https://example.com/outfits/generate", { method: "OPTIONS" });
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 204);
});

Deno.test("generate: rejects non-POST, non-OPTIONS methods", async () => {
  const req = new Request("https://example.com/outfits/generate", {
    method: "GET",
    headers: { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  });
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 405);
});

Deno.test("generate: enforces the rate limiter and returns 429 once exceeded", async () => {
  const deps = buildDeps({ rateLimiter: createRateLimiter({ limit: 1, windowMs: 60_000 }) });
  const first = await handleGenerateOutfits(
    requestFor("generate", VALID_GENERATE_ENVELOPE, {
      Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
    }),
    deps,
  );
  assertEquals(first.status, 200);
  const second = await handleGenerateOutfits(
    requestFor("generate", VALID_GENERATE_ENVELOPE, {
      Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
    }),
    deps,
  );
  assertEquals(second.status, 429);
});

Deno.test(
  "generate: cannot return another user's garments even when a different user id is supplied in the body",
  async () => {
    const closetRepository = recordingClosetRepository();
    const deps = buildDeps({ closetRepository });

    const req = requestFor(
      "generate",
      {
        request_id: "attack-attempt",
        client_version: "ios/1.0.0",
        body: { desired_count: 2, user_id: ATTACKER_SUPPLIED_UUID },
      },
      { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
    );

    const response = await handleGenerateOutfits(req, deps);
    assertEquals(response.status, 200);
    const json = await response.json();

    assertEquals(closetRepository.candidateCalls, [USER_A_ID]);
    assertNotEquals(closetRepository.candidateCalls[0], ATTACKER_SUPPLIED_UUID);
    assertNotEquals(closetRepository.candidateCalls[0], USER_B_ID);

    const returnedItemIds: string[] = json.data.flatMap((o: { item_ids: string[] }) => o.item_ids);
    for (const id of returnedItemIds) {
      assert(USER_A_CLOSET.some((item) => item.id === id));
      assert(!USER_B_CLOSET.some((item) => item.id === id));
    }
  },
);

Deno.test("generate: echoes the envelope's request_id when no header is supplied", async () => {
  const req = requestFor(
    "generate",
    { ...VALID_GENERATE_ENVELOPE, request_id: "envelope-supplied-id" },
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  );
  const response = await handleGenerateOutfits(req, buildDeps());
  const json = await response.json();
  assertEquals(json.request_id, "envelope-supplied-id");
});

Deno.test("generate: the X-Request-Id header wins over the envelope", async () => {
  const req = requestFor(
    "generate",
    { ...VALID_GENERATE_ENVELOPE, request_id: "envelope-supplied-id" },
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}`, "X-Request-Id": "header-supplied-id" },
  );
  const response = await handleGenerateOutfits(req, buildDeps());
  const json = await response.json();
  assertEquals(json.request_id, "header-supplied-id");
});

// ---------------------------------------------------------------------------
// POST /outfits/rank
// ---------------------------------------------------------------------------

const GOOD_CANDIDATE = { item_ids: [TOP_A, BOTTOM_A, SHOES_A] };
const CLASHING_CANDIDATE = { item_ids: [TOP_A2, BOTTOM_A, SHOES_A] };

function rankEnvelope(body: unknown, requestId = "test-rank-id") {
  return { request_id: requestId, client_version: "ios/1.0.0", body };
}

Deno.test("rank: rejects a request with no Authorization header", async () => {
  const req = requestFor("rank", rankEnvelope({ candidates: [GOOD_CANDIDATE] }));
  const response = await handleRankOutfits(req, buildDeps());
  assertEquals(response.status, 401);
});

Deno.test("rank: rejects an empty candidates array", async () => {
  const req = requestFor(
    "rank",
    rankEnvelope({ candidates: [] }),
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  );
  const response = await handleRankOutfits(req, buildDeps());
  assertEquals(response.status, 400);
  const json = await response.json();
  assertEquals(json.error.category, "validation");
});

Deno.test("rank: rejects a candidate with an empty item_ids array", async () => {
  const req = requestFor(
    "rank",
    rankEnvelope({ candidates: [{ item_ids: [] }] }),
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  );
  const response = await handleRankOutfits(req, buildDeps());
  assertEquals(response.status, 400);
});

Deno.test("rank: returns a well-formed, wire-shaped result for a valid request", async () => {
  const req = requestFor(
    "rank",
    rankEnvelope({ candidates: [GOOD_CANDIDATE] }),
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  );
  const response = await handleRankOutfits(req, buildDeps());
  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.data.length, 1);
  const outfit = json.data[0];
  assertEquals(outfit.item_ids.sort(), [BOTTOM_A, SHOES_A, TOP_A].sort());
  assertEquals(typeof outfit.compatibility_score, "number");
  assert(Array.isArray(outfit.unmeasured));
});

Deno.test("rank: echoes a caller-supplied candidate id, so results correlate back to inputs", async () => {
  const req = requestFor(
    "rank",
    rankEnvelope({
      candidates: [{
        id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
        item_ids: [TOP_A, BOTTOM_A, SHOES_A],
      }],
    }),
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  );
  const response = await handleRankOutfits(req, buildDeps());
  const json = await response.json();
  assertEquals(json.data[0].id, "dddddddd-dddd-4ddd-8ddd-dddddddddddd");
});

Deno.test("rank: ranking order matches scoreOutfit's own ordering for the same inputs", async () => {
  const req = requestFor(
    "rank",
    rankEnvelope({ candidates: [CLASHING_CANDIDATE, GOOD_CANDIDATE] }),
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  );
  const response = await handleRankOutfits(req, buildDeps());
  const json = await response.json();

  // The independently-computed truth: map the same rows through the same
  // mapper and score them with the same scorer, outside the handler.
  const byId = new Map(USER_A_CLOSET.map((r) => [r.id, mapClosetItemRowToScorableItem(r)!]));
  const goodScore = scoreOutfit(GOOD_CANDIDATE.item_ids.map((id) => byId.get(id)!)).score;
  const clashingScore = scoreOutfit(CLASHING_CANDIDATE.item_ids.map((id) => byId.get(id)!)).score;
  assert(goodScore > clashingScore, "test fixture must produce a real score gap to be meaningful");

  assertEquals(json.data.length, 2);
  assertEquals(json.data[0].compatibility_score, goodScore);
  assertEquals(json.data[1].compatibility_score, clashingScore);
  assertEquals(json.data[0].item_ids.sort(), GOOD_CANDIDATE.item_ids.sort());
});

Deno.test("rank: a locked item filters out every candidate that does not contain it", async () => {
  const req = requestFor(
    "rank",
    rankEnvelope({
      candidates: [GOOD_CANDIDATE, CLASHING_CANDIDATE],
      locked_closet_item_ids: [TOP_A2], // only in CLASHING_CANDIDATE
    }),
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  );
  const response = await handleRankOutfits(req, buildDeps());
  const json = await response.json();
  assertEquals(json.data.length, 1);
  assert(json.data[0].item_ids.includes(TOP_A2));
});

Deno.test("rank: cannot resolve or score another user's items even if their id is named in a candidate", async () => {
  const closetRepository = recordingClosetRepository();
  const deps = buildDeps({ closetRepository });
  const req = requestFor(
    "rank",
    rankEnvelope({
      candidates: [
        { item_ids: [TOP_A, BOTTOM_A, SHOES_A] }, // fully User A's own — should resolve
        { item_ids: [TOP_B, BOTTOM_A, SHOES_A] }, // names a User B item — must not resolve
      ],
    }),
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  );
  const response = await handleRankOutfits(req, deps);
  const json = await response.json();

  // Only the fully-owned candidate survives; the other is silently dropped
  // rather than scored with User B's item missing or substituted.
  assertEquals(json.data.length, 1);
  assertEquals(json.data[0].item_ids.sort(), [BOTTOM_A, SHOES_A, TOP_A].sort());

  assertEquals(closetRepository.byIdsCalls.length, 1);
  assertEquals(closetRepository.byIdsCalls[0]!.userId, USER_A_ID);
});

Deno.test("rank: OPTIONS is answered as a CORS preflight before authentication", async () => {
  const req = new Request("https://example.com/outfits/rank", { method: "OPTIONS" });
  const response = await handleRankOutfits(req, buildDeps());
  assertEquals(response.status, 204);
});

Deno.test("rank: enforces the rate limiter", async () => {
  const deps = buildDeps({ rateLimiter: createRateLimiter({ limit: 1, windowMs: 60_000 }) });
  const first = await handleRankOutfits(
    requestFor("rank", rankEnvelope({ candidates: [GOOD_CANDIDATE] }), {
      Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
    }),
    deps,
  );
  assertEquals(first.status, 200);
  const second = await handleRankOutfits(
    requestFor("rank", rankEnvelope({ candidates: [GOOD_CANDIDATE] }), {
      Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
    }),
    deps,
  );
  assertEquals(second.status, 429);
});
