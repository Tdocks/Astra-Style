// ============================================================================
// profile/handler_test.ts
// ============================================================================
// Covers P2-ONBOARD-12's three acceptance criteria plus the failure paths
// spec §14 requires of every endpoint:
//
//   - "Endpoint validates the JWT"                 -> the three 401 cases.
//   - "and rejects writes to a user_id other than
//      the caller's"                                -> the ownership test:
//     a payload carrying a different user_id in every profile document still
//     writes as the JWT's user, and the repository is never handed anything
//     but the JWT-derived id.
//   - "A successful call sets onboarding_completed_at
//      to a non-null timestamp"                     -> asserted on the response.
//   - "Request schema validation rejects a malformed
//      payload with a 4xx, not a 500"               -> the 400 cases.
//
// Every dependency is mocked at the interface boundary — no network, no
// Supabase project, no real JWT signing.
// ============================================================================

import { assert, assertEquals, assertNotEquals } from "@std/assert";
import type { AuthClient } from "../_shared/jwt.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { serverError } from "../_shared/errors.ts";
import {
  handleCompleteOnboarding,
  type HandlerDeps,
  type OnboardingRepository,
  type OnboardingWrite,
} from "./handler.ts";
import type { ProfileDTO } from "./schema.ts";

const VALID_LOOKING_JWT_A =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWEifQ.dGhpc19pc19ub3RfYV9yZWFsX3NpZ25hdHVyZQ";
const VALID_LOOKING_JWT_B =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWIifQ.YW5vdGhlcl9mYWtlX3NpZ25hdHVyZQ";

const USER_A_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const USER_B_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

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

function profileFor(userId: string): ProfileDTO {
  return {
    id: userId,
    display_name: null,
    avatar_url: null,
    location_name: null,
    timezone: "UTC",
    units: "imperial",
    theme: "system",
    onboarding_completed_at: "2026-07-30T12:00:00Z",
    subscription_tier: "free",
    wardrobe_graph: "menswear_3_role",
    created_at: "2026-07-01T09:00:00Z",
    updated_at: "2026-07-30T12:00:00Z",
  };
}

/**
 * Records every `(userId, write)` pair it is handed, and models what the RPC
 * does: the row it returns belongs to the id it was CALLED with, never to
 * anything inside the payload.
 */
function recordingRepository(): OnboardingRepository & {
  calls: Array<{ userId: string; write: OnboardingWrite }>;
} {
  const calls: Array<{ userId: string; write: OnboardingWrite }> = [];
  return {
    calls,
    complete(userId: string, write: OnboardingWrite) {
      calls.push({ userId, write });
      return Promise.resolve(profileFor(userId));
    },
  };
}

function buildDeps(overrides: Partial<HandlerDeps> = {}): HandlerDeps {
  return {
    authClient: tokenMappedAuthClient(),
    onboardingRepository: recordingRepository(),
    rateLimiter: createRateLimiter({ limit: 1000, windowMs: 60_000 }),
    now: () => new Date("2026-07-30T12:00:00Z"),
    ...overrides,
  };
}

function requestFor(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("https://example.com/profile/complete-onboarding", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

const VALID_BODY = {
  style_goals: ["find_signature_style"],
  style_profile: {
    primary_identity: "quiet_luxury",
    secondary_identities: ["minimalist"],
    preferred_fit: "tailored",
    preference_vector: {
      version: 1,
      comparisons_answered: 3,
      comparisons_offered: 3,
      dimensions: {
        formality: { score: 0.6, confidence: "moderate", observations: 2, agreement: 0.9 },
        texture: { score: null, confidence: "insufficient", observations: 0, agreement: null },
      },
    },
  },
  body_profile: { chest_cm: 102, waist_cm: 86 },
  lifestyle_profile: { dress_code: "business_casual", typical_week: "Mostly in an office" },
  quiz_answers: [{ pair_id: "p1", chosen_option_id: "a" }],
};

const VALID_ENVELOPE = {
  request_id: "test-request-id",
  client_version: "ios/1.0.0",
  body: VALID_BODY,
};

// ---------------------------------------------------------------------------
// JWT
// ---------------------------------------------------------------------------

Deno.test("rejects a request with no Authorization header at all", async () => {
  const response = await handleCompleteOnboarding(requestFor(VALID_ENVELOPE), buildDeps());
  assertEquals(response.status, 401);
  const json = await response.json();
  assertEquals(json.error.category, "auth");
  assertEquals(json.data, null);
});

Deno.test("rejects a malformed JWT", async () => {
  const response = await handleCompleteOnboarding(
    requestFor(VALID_ENVELOPE, { Authorization: "Bearer not-a-jwt" }),
    buildDeps(),
  );
  assertEquals(response.status, 401);
});

Deno.test("rejects a JWT Supabase Auth itself does not recognize", async () => {
  const ghost = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJnaG9zdCJ9.c2lnbmF0dXJl";
  const response = await handleCompleteOnboarding(
    requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${ghost}` }),
    buildDeps(),
  );
  assertEquals(response.status, 401);
});

Deno.test("an unauthenticated request never reaches the write", async () => {
  const repository = recordingRepository();
  await handleCompleteOnboarding(
    requestFor(VALID_ENVELOPE),
    buildDeps({ onboardingRepository: repository }),
  );
  assertEquals(repository.calls.length, 0);
});

// ---------------------------------------------------------------------------
// Ownership
// ---------------------------------------------------------------------------

Deno.test("a user_id supplied in the payload cannot redirect the write", async () => {
  const repository = recordingRepository();
  const hostile = structuredClone(VALID_ENVELOPE) as Record<string, unknown>;
  const body = hostile["body"] as Record<string, unknown>;
  // Every document the client's models encode carries a user_id. Set all
  // three to another real user.
  (body["style_profile"] as Record<string, unknown>)["user_id"] = USER_B_ID;
  body["body_profile"] = { ...(body["body_profile"] as object), user_id: USER_B_ID };
  body["lifestyle_profile"] = { ...(body["lifestyle_profile"] as object), user_id: USER_B_ID };
  // ...and add a top-level one for good measure.
  body["user_id"] = USER_B_ID;

  const response = await handleCompleteOnboarding(
    requestFor(hostile, { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    buildDeps({ onboardingRepository: repository }),
  );

  assertEquals(response.status, 200);
  assertEquals(repository.calls.length, 1);
  // The repository saw the JWT's user, never the body's.
  assertEquals(repository.calls[0]?.userId, USER_A_ID);
  assertNotEquals(repository.calls[0]?.userId, USER_B_ID);

  const json = await response.json();
  assertEquals(json.data.id, USER_A_ID);

  // And the write itself carries no user id anywhere — the parsed documents
  // simply have no such field, so there is nothing for the RPC to trust.
  const write = repository.calls[0]?.write;
  assert(write !== undefined);
  assert(!("user_id" in write.styleProfile));
  assert(!("user_id" in write.bodyProfile));
  assert(!("user_id" in write.lifestyleProfile));
});

// ---------------------------------------------------------------------------
// Schema validation — 4xx, never 5xx
// ---------------------------------------------------------------------------

Deno.test("an unparsable body is a 400", async () => {
  const request = new Request("https://example.com/profile/complete-onboarding", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
    body: "{ not json",
  });
  const response = await handleCompleteOnboarding(request, buildDeps());
  assertEquals(response.status, 400);
  assertEquals((await response.json()).error.category, "validation");
});

Deno.test("an envelope with no body is a 400", async () => {
  const response = await handleCompleteOnboarding(
    requestFor({ request_id: "r" }, { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    buildDeps(),
  );
  assertEquals(response.status, 400);
});

Deno.test("an invalid enum value is a 400, not a 500", async () => {
  const response = await handleCompleteOnboarding(
    requestFor(
      { request_id: "r", body: { style_profile: { primary_identity: "dark_academia" } } },
      { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
    ),
    buildDeps(),
  );
  assertEquals(response.status, 400);
  assertEquals((await response.json()).error.category, "validation");
});

Deno.test("a malformed payload never reaches the write", async () => {
  const repository = recordingRepository();
  await handleCompleteOnboarding(
    requestFor(
      { request_id: "r", body: { body_profile: { chest_cm: -1 } } },
      { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
    ),
    buildDeps({ onboardingRepository: repository }),
  );
  assertEquals(repository.calls.length, 0);
});

// ---------------------------------------------------------------------------
// Success
// ---------------------------------------------------------------------------

Deno.test("a valid submission returns the profile with onboarding_completed_at set", async () => {
  const response = await handleCompleteOnboarding(
    requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    buildDeps(),
  );

  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.error, null);
  assertEquals(json.request_id, "test-request-id");
  assertNotEquals(json.data.onboarding_completed_at, null);
  // Whole-second ISO-8601 UTC, which is the only shape the client's
  // `.iso8601` date strategy accepts — see _shared/time.ts.
  assert(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(json.data.onboarding_completed_at));
});

Deno.test("the preference vector reaches the write with absent and zero-observation axes intact", async () => {
  const repository = recordingRepository();
  await handleCompleteOnboarding(
    requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    buildDeps({ onboardingRepository: repository }),
  );

  const dimensions = repository.calls[0]?.write.styleProfile.preference_vector.dimensions ?? {};
  // formality was measured, texture was asked and declined, the other six
  // were never asked. All three states have to survive the round trip.
  assertEquals(dimensions["formality"]?.score, 0.6);
  assertEquals(dimensions["texture"]?.score, null);
  assertEquals(dimensions["texture"]?.observations, 0);
  assertEquals(Object.keys(dimensions).sort(), ["formality", "texture"]);
});

Deno.test("a submission with only an identity succeeds — every other step is skippable", async () => {
  const response = await handleCompleteOnboarding(
    requestFor(
      { request_id: "r", body: { style_profile: { primary_identity: "executive" } } },
      { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
    ),
    buildDeps(),
  );
  assertEquals(response.status, 200);
});

// ---------------------------------------------------------------------------
// Failure modes
// ---------------------------------------------------------------------------

Deno.test("a failed write is a 500 with no partial-success signal to the client", async () => {
  const failing: OnboardingRepository = {
    complete() {
      return Promise.reject(serverError("Couldn't save your answers. Please try again."));
    },
  };
  const response = await handleCompleteOnboarding(
    requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    buildDeps({ onboardingRepository: failing }),
  );
  assertEquals(response.status, 500);
  const json = await response.json();
  // The client keeps its draft on any non-2xx and offers a retry
  // (OnboardingViewModel.submit), so a clean failure costs the user one tap.
  assertEquals(json.data, null);
  assertEquals(json.error.category, "server");
});

Deno.test("an unexpected throw is a generic 500 that leaks nothing", async () => {
  const exploding: OnboardingRepository = {
    complete() {
      throw new Error('relation "style_profiles" violates check constraint chest_cm_check');
    },
  };
  const response = await handleCompleteOnboarding(
    requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    buildDeps({ onboardingRepository: exploding }),
  );
  assertEquals(response.status, 500);
  const json = await response.json();
  assertEquals(json.error.message, "Internal server error.");
});

Deno.test("exceeding the rate limit is a 429 with a Retry-After header", async () => {
  const deps = buildDeps({ rateLimiter: createRateLimiter({ limit: 1, windowMs: 60_000 }) });
  const first = await handleCompleteOnboarding(
    requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    deps,
  );
  assertEquals(first.status, 200);

  const second = await handleCompleteOnboarding(
    requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    deps,
  );
  assertEquals(second.status, 429);
  assertEquals((await second.json()).error.category, "rate_limited");
  assertNotEquals(second.headers.get("Retry-After"), null);
});

Deno.test("the rate limit is per user, not global", async () => {
  const deps = buildDeps({ rateLimiter: createRateLimiter({ limit: 1, windowMs: 60_000 }) });
  await handleCompleteOnboarding(
    requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    deps,
  );
  const other = await handleCompleteOnboarding(
    requestFor(VALID_ENVELOPE, { Authorization: `Bearer ${VALID_LOOKING_JWT_B}` }),
    deps,
  );
  assertEquals(other.status, 200);
});

Deno.test("a CORS preflight is answered without authentication", async () => {
  const response = await handleCompleteOnboarding(
    new Request("https://example.com/profile/complete-onboarding", { method: "OPTIONS" }),
    buildDeps(),
  );
  assertEquals(response.status, 204);
});

Deno.test("a non-POST verb is rejected", async () => {
  const response = await handleCompleteOnboarding(
    new Request("https://example.com/profile/complete-onboarding", { method: "PUT" }),
    buildDeps(),
  );
  assertEquals(response.status, 405);
});
