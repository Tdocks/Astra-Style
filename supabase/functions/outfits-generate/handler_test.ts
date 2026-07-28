// ============================================================================
// outfits-generate/handler_test.ts
// ============================================================================
// Covers, at minimum (per the task spec):
//   - rejects a missing JWT
//   - rejects a malformed JWT
//   - rejects a request whose body fails schema validation
//   - returns a well-formed outfit for a valid request
//   - cannot return another user's garments even when a different user id
//     is supplied in the body
//
// The Supabase client is mocked entirely at the boundary via the
// `AuthClient` and `ClosetRepository` interfaces `handler.ts` depends on —
// no network access, no live database, no real JWT signing.
// ============================================================================

import { assertEquals, assertNotEquals } from "@std/assert";
import type { AuthClient } from "../_shared/jwt.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { type ClosetRepository, handleGenerateOutfits, type HandlerDeps } from "./handler.ts";
import { type ClosetItemRow, LeastRecentlyWornScorer } from "./scorer.ts";

const VALID_LOOKING_JWT_A =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWEifQ.dGhpc19pc19ub3RfYV9yZWFsX3NpZ25hdHVyZQ";
const VALID_LOOKING_JWT_B =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWIifQ.YW5vdGhlcl9mYWtlX3NpZ25hdHVyZQ";

const USER_A_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const USER_B_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ATTACKER_SUPPLIED_UUID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

const USER_A_CLOSET: ClosetItemRow[] = [
  { id: "a-top", category: "top", last_worn_at: null },
  { id: "a-bottom", category: "bottom", last_worn_at: null },
  { id: "a-shoes", category: "shoes", last_worn_at: null },
];

const USER_B_CLOSET: ClosetItemRow[] = [
  { id: "b-top", category: "top", last_worn_at: null },
  { id: "b-bottom", category: "bottom", last_worn_at: null },
  { id: "b-shoes", category: "shoes", last_worn_at: null },
];

/** A fake `AuthClient` that recognizes exactly the two fixture tokens above. */
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
 * A fake `ClosetRepository` that only ever returns items for the `userId`
 * it is called with — modeling what RLS enforces in production. Also
 * records every `userId` it was called with, so tests can assert the
 * handler never passes anything other than the JWT-derived id (in
 * particular, never a value pulled from the request body).
 */
function recordingClosetRepository(): ClosetRepository & { calls: string[] } {
  const calls: string[] = [];
  const closets: Record<string, ClosetItemRow[]> = {
    [USER_A_ID]: USER_A_CLOSET,
    [USER_B_ID]: USER_B_CLOSET,
  };
  return {
    calls,
    listCandidateItems(userId: string) {
      calls.push(userId);
      return Promise.resolve(closets[userId] ?? []);
    },
  };
}

function buildDeps(overrides: Partial<HandlerDeps> = {}): HandlerDeps {
  return {
    authClient: tokenMappedAuthClient(),
    closetRepository: recordingClosetRepository(),
    scorer: new LeastRecentlyWornScorer(),
    rateLimiter: createRateLimiter({ limit: 1000, windowMs: 60_000 }),
    now: () => new Date("2026-07-28T12:00:00Z"),
    ...overrides,
  };
}

function requestFor(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("https://example.com/outfits/generate", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

const VALID_ENVELOPE = {
  request_id: "test-request-id",
  client_version: "ios/1.0.0",
  body: { desired_count: 2 },
};

Deno.test("rejects a request with no Authorization header at all", async () => {
  const req = requestFor(VALID_ENVELOPE);
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 401);
  const json = await response.json();
  assertEquals(json.error.category, "auth");
  assertEquals(json.data, null);
});

Deno.test("rejects a malformed JWT (well-formed header, garbage token)", async () => {
  const req = requestFor(VALID_ENVELOPE, { Authorization: "Bearer this-is-not-a-jwt" });
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 401);
  const json = await response.json();
  assertEquals(json.error.category, "auth");
});

Deno.test("rejects a JWT Supabase Auth itself does not recognize", async () => {
  const fakeButStructurallyValid = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJnaG9zdCJ9.c2lnbmF0dXJl"; // not one of the two fixture tokens
  const req = requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${fakeButStructurallyValid}` });
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 401);
});

Deno.test("rejects a request whose body fails schema validation", async () => {
  const req = requestFor(
    { request_id: "r", client_version: "ios/1.0.0", body: { desired_count: 999 } },
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  );
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 400);
  const json = await response.json();
  assertEquals(json.error.category, "validation");
  assertEquals(json.data, null);
});

Deno.test("rejects a body missing the envelope's required body field", async () => {
  const req = requestFor(
    { request_id: "r", client_version: "ios/1.0.0" },
    { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  );
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 400);
});

Deno.test("rejects a request with an unparsable JSON body", async () => {
  const req = new Request("https://example.com/outfits/generate", {
    method: "POST",
    headers: { Authorization: `Bearer ${VALID_LOOKING_JWT_A}`, "Content-Type": "application/json" },
    body: "{not valid json",
  });
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 400);
});

Deno.test("returns a well-formed outfit list for a valid, authenticated request", async () => {
  const req = requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` });
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.error, null);
  assertEquals(Array.isArray(json.data), true);
  assertEquals(json.data.length, 1); // user A's closet has exactly one top/bottom/shoes each
  const outfit = json.data[0];
  assertEquals(typeof outfit.id, "string");
  assertEquals(typeof outfit.name, "string");
  assertEquals(typeof outfit.reason, "string");
  assertEquals(typeof outfit.compatibility_score, "number");
  assertEquals(Array.isArray(outfit.item_ids), true);
  assertEquals(outfit.item_ids.sort(), ["a-bottom", "a-shoes", "a-top"]);
  assertEquals(outfit.missing_product_ids, []);
});

Deno.test("handles OPTIONS as a CORS preflight before authentication ever runs", async () => {
  const req = new Request("https://example.com/outfits/generate", { method: "OPTIONS" });
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 204);
});

Deno.test("rejects non-POST, non-OPTIONS methods", async () => {
  const req = new Request("https://example.com/outfits/generate", {
    method: "GET",
    headers: { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
  });
  const response = await handleGenerateOutfits(req, buildDeps());
  assertEquals(response.status, 405);
});

Deno.test("enforces the rate limiter and returns 429 once exceeded", async () => {
  const deps = buildDeps({ rateLimiter: createRateLimiter({ limit: 1, windowMs: 60_000 }) });
  const first = await handleGenerateOutfits(
    requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    deps,
  );
  assertEquals(first.status, 200);
  const second = await handleGenerateOutfits(
    requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    deps,
  );
  assertEquals(second.status, 429);
  const json = await second.json();
  assertEquals(json.error.category, "rate_limited");
});

// ---------------------------------------------------------------------------
// The most important test in this file: ownership isolation.
// ---------------------------------------------------------------------------

Deno.test(
  "cannot return another user's garments even when a different user id is supplied in the body",
  async () => {
    const closetRepository = recordingClosetRepository();
    const deps = buildDeps({ closetRepository });

    // User A's real, verified JWT — but the request body claims to be
    // acting on behalf of a different user id (`ATTACKER_SUPPLIED_UUID`,
    // which doesn't even correspond to a real user in this fixture, and
    // separately, User B's actual closet items are present in the fake
    // repository as a second sanity check).
    const req = requestFor(
      {
        request_id: "attack-attempt",
        client_version: "ios/1.0.0",
        body: {
          desired_count: 2,
          // Not a real field in GenerateOutfitsRequestBody — parseGenerateOutfitsBody
          // must ignore this rather than use it to decide whose closet to read.
          user_id: ATTACKER_SUPPLIED_UUID,
        },
      },
      { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
    );

    const response = await handleGenerateOutfits(req, deps);
    assertEquals(response.status, 200);
    const json = await response.json();

    // The repository must have been consulted using User A's JWT-derived
    // id, never the attacker-supplied body field and never User B's id.
    assertEquals(closetRepository.calls, [USER_A_ID]);
    assertNotEquals(closetRepository.calls[0], ATTACKER_SUPPLIED_UUID);
    assertNotEquals(closetRepository.calls[0], USER_B_ID);

    // And the actual returned garments must be exclusively User A's own
    // closet item ids — none of User B's fixture ids ever appear.
    const returnedItemIds: string[] = json.data.flatMap((o: { item_ids: string[] }) => o.item_ids);
    for (const id of returnedItemIds) {
      assertEquals(USER_A_CLOSET.some((item) => item.id === id), true);
      assertEquals(USER_B_CLOSET.some((item) => item.id === id), false);
    }
  },
);

Deno.test("a second user's JWT independently only ever sees that user's own closet", async () => {
  const closetRepository = recordingClosetRepository();
  const deps = buildDeps({ closetRepository });

  const req = requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${VALID_LOOKING_JWT_B}` });
  const response = await handleGenerateOutfits(req, deps);
  assertEquals(response.status, 200);
  const json = await response.json();

  assertEquals(closetRepository.calls, [USER_B_ID]);
  const returnedItemIds: string[] = json.data.flatMap((o: { item_ids: string[] }) => o.item_ids);
  for (const id of returnedItemIds) {
    assertEquals(USER_B_CLOSET.some((item) => item.id === id), true);
    assertEquals(USER_A_CLOSET.some((item) => item.id === id), false);
  }
});
