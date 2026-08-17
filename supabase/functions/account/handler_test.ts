// ============================================================================
// account/handler_test.ts
// ============================================================================
// Covers P7-PRIVACY-01's acceptance criteria at the handler level (the
// `account_deletions` row reaching 'completed' and the storage-prefix /
// database-row assertions are exercised against a real Supabase project in
// `README.md`'s manual walkthrough, not here — see that file's own
// "verified / not verified" split, same as `outfits`) plus spec §14's
// per-endpoint requirements and this project's two authorization-bug
// classes:
//
//   - JWT validation                    -> the 401 cases.
//   - Ownership, structurally           -> "a hostile body cannot redirect
//     the deletion" and "two different callers only ever act on their own
//     account", the single most important test in this file per the task.
//   - Idempotency                       -> "already in progress" reuses the
//     existing row and starts no second cascade.
//   - The cascade itself, and its two distinct failure classes           ->
//     storage-scrub failure and post-storage ("auth identity") failure,
//     each asserted to call `markFailed` with a specific reason and to
//     stop rather than run later steps against a state a prior step
//     already gave up on.
//   - Rate limiting, CORS, method/schema validation -> as in every other
//     handler_test.ts in this project.
//
// Every dependency is mocked at the interface boundary — no network, no
// Supabase project, no real JWT signing, matching `profile/handler_test.ts`
// and `closet/handler_test.ts`.
// ============================================================================

import { assert, assertEquals, assertNotEquals } from "@std/assert";
import type { AuthClient } from "../_shared/jwt.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import {
  type AccountDeletionRepository,
  type DeletionRequestResult,
  handleDeleteAccount,
  type HandlerDeps,
} from "./handler.ts";

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

type FailStep = "purgeStorage" | "finalizeMetadata" | "deleteAuthIdentity" | "markComplete";

interface RecordedCalls {
  requestDeletion: string[];
  purgeStorage: string[];
  finalizeMetadata: string[];
  deleteAuthIdentity: string[];
  markComplete: string[];
  markFailed: Array<{ deletionId: string; reason: string }>;
}

/**
 * A fake `AccountDeletionRepository` that records every call it receives
 * (so tests can assert both WHAT was called and WHAT ID it was called
 * with — the ownership tests below depend on the latter) and can be
 * configured to either report an existing in-flight deletion (the
 * idempotency case) or fail at a specific cascade step.
 */
function fakeRepository(
  opts: {
    existingDeletionForUser?: {
      userId: string;
      deletionId: string;
      status: "pending" | "processing";
    };
    failStep?: FailStep;
  } = {},
): AccountDeletionRepository & { calls: RecordedCalls } {
  const calls: RecordedCalls = {
    requestDeletion: [],
    purgeStorage: [],
    finalizeMetadata: [],
    deleteAuthIdentity: [],
    markComplete: [],
    markFailed: [],
  };
  let nextId = 0;

  return {
    calls,
    requestDeletion(userId: string): Promise<DeletionRequestResult> {
      calls.requestDeletion.push(userId);
      if (opts.existingDeletionForUser && opts.existingDeletionForUser.userId === userId) {
        const { deletionId, status } = opts.existingDeletionForUser;
        return Promise.resolve({ deletionId, status, freshlyRequested: false });
      }
      nextId += 1;
      return Promise.resolve({
        deletionId: `deletion-${userId}-${nextId}`,
        status: "pending",
        freshlyRequested: true,
      });
    },
    purgeStorage(userId: string): Promise<void> {
      calls.purgeStorage.push(userId);
      if (opts.failStep === "purgeStorage") {
        return Promise.reject(new Error("Storage API unavailable"));
      }
      return Promise.resolve();
    },
    finalizeMetadata(deletionId: string): Promise<void> {
      calls.finalizeMetadata.push(deletionId);
      if (opts.failStep === "finalizeMetadata") {
        return Promise.reject(new Error("finalize_account_deletion() failed"));
      }
      return Promise.resolve();
    },
    deleteAuthIdentity(userId: string): Promise<void> {
      calls.deleteAuthIdentity.push(userId);
      if (opts.failStep === "deleteAuthIdentity") {
        return Promise.reject(new Error("Auth Admin API unavailable"));
      }
      return Promise.resolve();
    },
    markComplete(deletionId: string): Promise<void> {
      calls.markComplete.push(deletionId);
      if (opts.failStep === "markComplete") {
        return Promise.reject(new Error("mark_account_deletion_complete() failed"));
      }
      return Promise.resolve();
    },
    markFailed(deletionId: string, reason: string): Promise<void> {
      calls.markFailed.push({ deletionId, reason });
      return Promise.resolve();
    },
  };
}

/**
 * A `background` double that runs `task()` immediately (exactly like the
 * default the interface documents) but retains the returned promise so a
 * test can `await drain()` before asserting on the fake repository's
 * recorded calls — otherwise a test would race the (deliberately
 * fire-and-forget) cascade.
 */
function syncBackground(): { background: HandlerDeps["background"]; drain: () => Promise<void> } {
  const tasks: Promise<void>[] = [];
  return {
    background(task: () => Promise<void>) {
      tasks.push(task());
    },
    async drain() {
      await Promise.all(tasks);
    },
  };
}

function buildDeps(overrides: Partial<HandlerDeps> = {}): HandlerDeps {
  return {
    authClient: tokenMappedAuthClient(),
    repository: fakeRepository(),
    rateLimiter: createRateLimiter({ limit: 1000, windowMs: 60_000 }),
    now: () => new Date("2026-08-16T12:00:00Z"),
    background: (task) => {
      void task();
    },
    ...overrides,
  };
}

function deleteRequestFor(
  headers: Record<string, string> = {},
  body?: unknown,
): Request {
  return new Request("https://example.com/account", {
    method: "DELETE",
    headers: { "Content-Type": "application/json", ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

// ---------------------------------------------------------------------------
// JWT
// ---------------------------------------------------------------------------

Deno.test("rejects a request with no Authorization header at all", async () => {
  const response = await handleDeleteAccount(deleteRequestFor(), buildDeps());
  assertEquals(response.status, 401);
  const json = await response.json();
  assertEquals(json.error.category, "auth");
  assertEquals(json.data, null);
});

Deno.test("rejects a malformed JWT", async () => {
  const response = await handleDeleteAccount(
    deleteRequestFor({ Authorization: "Bearer not-a-jwt" }),
    buildDeps(),
  );
  assertEquals(response.status, 401);
});

Deno.test("rejects a JWT Supabase Auth itself does not recognize", async () => {
  const ghost = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJnaG9zdCJ9.c2lnbmF0dXJl";
  const response = await handleDeleteAccount(
    deleteRequestFor({ Authorization: `Bearer ${ghost}` }),
    buildDeps(),
  );
  assertEquals(response.status, 401);
});

Deno.test("an unauthenticated request never calls the repository", async () => {
  const repository = fakeRepository();
  await handleDeleteAccount(deleteRequestFor(), buildDeps({ repository }));
  assertEquals(repository.calls.requestDeletion.length, 0);
});

// ---------------------------------------------------------------------------
// Method / CORS
// ---------------------------------------------------------------------------

Deno.test("a CORS preflight is answered without authentication", async () => {
  const response = await handleDeleteAccount(
    new Request("https://example.com/account", { method: "OPTIONS" }),
    buildDeps(),
  );
  assertEquals(response.status, 204);
});

Deno.test("a non-DELETE verb is rejected", async () => {
  const response = await handleDeleteAccount(
    new Request("https://example.com/account", {
      method: "POST",
      headers: { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
    }),
    buildDeps(),
  );
  assertEquals(response.status, 405);
});

// ---------------------------------------------------------------------------
// Ownership — the most important cases in this file
// ---------------------------------------------------------------------------

Deno.test(
  "a hostile body claiming another user's id has no effect: the deletion targets the JWT's own user",
  async () => {
    const repository = fakeRepository();
    // Nothing in schema.ts reads this field — see its header comment — but
    // the test sends it anyway to prove the absence is structural, not
    // merely untested.
    const response = await handleDeleteAccount(
      deleteRequestFor(
        { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
        { request_id: "r", client_version: "test", body: { user_id: USER_B_ID } },
      ),
      buildDeps({ repository }),
    );

    assertEquals(response.status, 202);
    assertEquals(repository.calls.requestDeletion, [USER_A_ID]);
    assertNotEquals(repository.calls.requestDeletion[0], USER_B_ID);
  },
);

Deno.test(
  "two different callers each act only on their own account, never each other's",
  async () => {
    const repository = fakeRepository();
    const deps = buildDeps({ repository });

    const responseA = await handleDeleteAccount(
      deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
      deps,
    );
    const responseB = await handleDeleteAccount(
      deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_B}` }),
      deps,
    );

    assertEquals(responseA.status, 202);
    assertEquals(responseB.status, 202);
    assertEquals(repository.calls.requestDeletion, [USER_A_ID, USER_B_ID]);

    const jsonA = await responseA.json();
    const jsonB = await responseB.json();
    assertNotEquals(jsonA.data.deletion_id, jsonB.data.deletion_id);
  },
);

// ---------------------------------------------------------------------------
// Happy path — the cascade actually runs, in order, for a fresh request
// ---------------------------------------------------------------------------

Deno.test(
  "a fresh deletion request returns 202 with a pending status and runs the full cascade",
  async () => {
    const repository = fakeRepository();
    const { background, drain } = syncBackground();
    const response = await handleDeleteAccount(
      deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
      buildDeps({ repository, background }),
    );

    assertEquals(response.status, 202);
    const json = await response.json();
    assertEquals(json.error, null);
    assertEquals(json.data.status, "pending");
    assert(typeof json.data.deletion_id === "string" && json.data.deletion_id.length > 0);

    await drain();

    assertEquals(repository.calls.purgeStorage, [USER_A_ID]);
    assertEquals(repository.calls.finalizeMetadata, [json.data.deletion_id]);
    assertEquals(repository.calls.deleteAuthIdentity, [USER_A_ID]);
    assertEquals(repository.calls.markComplete, [json.data.deletion_id]);
    assertEquals(repository.calls.markFailed.length, 0);
  },
);

// ---------------------------------------------------------------------------
// Idempotency — an already-in-progress deletion starts no second cascade
// ---------------------------------------------------------------------------

Deno.test(
  "a second delete request while one is already in progress reuses the existing job and starts no new cascade",
  async () => {
    const repository = fakeRepository({
      existingDeletionForUser: {
        userId: USER_A_ID,
        deletionId: "already-in-flight",
        status: "processing",
      },
    });
    const { background, drain } = syncBackground();
    const response = await handleDeleteAccount(
      deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
      buildDeps({ repository, background }),
    );

    assertEquals(response.status, 202);
    const json = await response.json();
    assertEquals(json.data.deletion_id, "already-in-flight");
    assertEquals(json.data.status, "processing");

    await drain();

    // The whole point: no cascade step ever runs for a replayed request.
    assertEquals(repository.calls.purgeStorage.length, 0);
    assertEquals(repository.calls.finalizeMetadata.length, 0);
    assertEquals(repository.calls.deleteAuthIdentity.length, 0);
    assertEquals(repository.calls.markComplete.length, 0);
  },
);

// ---------------------------------------------------------------------------
// Cascade failures — each stops at its own step and marks failed with a
// specific reason, never silently continuing against a state a prior step
// already gave up on
// ---------------------------------------------------------------------------

Deno.test(
  "a storage-scrub failure marks the deletion failed and never reaches finalize/auth-delete/complete",
  async () => {
    const repository = fakeRepository({ failStep: "purgeStorage" });
    const { background, drain } = syncBackground();
    const response = await handleDeleteAccount(
      deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
      buildDeps({ repository, background }),
    );

    // The response is already 202 — this failure is invisible to the HTTP
    // call itself, by design (see handler.ts's "WHY THE CASCADE RUNS AFTER
    // THE RESPONSE"). Only the account_deletions row (polled separately)
    // shows the failure.
    assertEquals(response.status, 202);
    const deletionId = (await response.json()).data.deletion_id;

    await drain();

    assertEquals(repository.calls.purgeStorage, [USER_A_ID]);
    assertEquals(repository.calls.finalizeMetadata.length, 0);
    assertEquals(repository.calls.deleteAuthIdentity.length, 0);
    assertEquals(repository.calls.markComplete.length, 0);
    assertEquals(repository.calls.markFailed, [
      { deletionId, reason: "storage_purge_failed" },
    ]);
  },
);

Deno.test(
  "an auth-identity cascade failure marks the deletion failed after storage and finalize already ran",
  async () => {
    const repository = fakeRepository({ failStep: "deleteAuthIdentity" });
    const { background, drain } = syncBackground();
    const response = await handleDeleteAccount(
      deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
      buildDeps({ repository, background }),
    );
    const deletionId = (await response.json()).data.deletion_id;

    await drain();

    // The earlier steps DID complete — this is not treated as if nothing
    // happened.
    assertEquals(repository.calls.purgeStorage, [USER_A_ID]);
    assertEquals(repository.calls.finalizeMetadata, [deletionId]);
    assertEquals(repository.calls.deleteAuthIdentity, [USER_A_ID]);
    assertEquals(repository.calls.markComplete.length, 0);
    assertEquals(repository.calls.markFailed, [
      { deletionId, reason: "auth_identity_delete_failed" },
    ]);
  },
);

Deno.test(
  "a finalize-metadata failure stops before auth-identity deletion ever runs",
  async () => {
    const repository = fakeRepository({ failStep: "finalizeMetadata" });
    const { background, drain } = syncBackground();
    const response = await handleDeleteAccount(
      deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
      buildDeps({ repository, background }),
    );
    const deletionId = (await response.json()).data.deletion_id;

    await drain();

    assertEquals(repository.calls.purgeStorage, [USER_A_ID]);
    assertEquals(repository.calls.finalizeMetadata, [deletionId]);
    // The single most important assertion in this test: the auth identity
    // — and every row that cascades from it — must never be deleted after
    // a step upstream of it failed.
    assertEquals(repository.calls.deleteAuthIdentity.length, 0);
    assertEquals(repository.calls.markFailed, [
      { deletionId, reason: "finalize_metadata_failed" },
    ]);
  },
);

Deno.test(
  "a mark-complete failure after a successful cascade does NOT report the deletion as failed",
  async () => {
    // The identity is already gone by this point (see handler.ts's
    // `runCascade` comment on this exact case) — reporting 'failed' here
    // would be a lie about a deletion that succeeded.
    const repository = fakeRepository({ failStep: "markComplete" });
    const { background, drain } = syncBackground();
    await handleDeleteAccount(
      deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
      buildDeps({ repository, background }),
    );

    await drain();

    assertEquals(repository.calls.deleteAuthIdentity, [USER_A_ID]);
    assertEquals(repository.calls.markComplete.length, 1);
    assertEquals(repository.calls.markFailed.length, 0);
  },
);

// ---------------------------------------------------------------------------
// Request-level failures
// ---------------------------------------------------------------------------

Deno.test("a request_account_deletion() failure that isn't 'already in progress' is a 500", async () => {
  const failing: AccountDeletionRepository = {
    requestDeletion() {
      return Promise.reject(new Error('relation "account_deletions" does not exist'));
    },
    purgeStorage: () => Promise.resolve(),
    finalizeMetadata: () => Promise.resolve(),
    deleteAuthIdentity: () => Promise.resolve(),
    markComplete: () => Promise.resolve(),
    markFailed: () => Promise.resolve(),
  };
  const response = await handleDeleteAccount(
    deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    buildDeps({ repository: failing }),
  );
  assertEquals(response.status, 500);
  const json = await response.json();
  assertEquals(json.data, null);
  assertEquals(json.error.category, "server");
  // The raw Postgres error text is never forwarded to the client.
  assert(!json.error.message.includes("relation"));
});

// ---------------------------------------------------------------------------
// Body handling — this endpoint has nothing to validate, and a malformed
// body must not block an irreversible-intent request over a field nobody
// reads (see schema.ts's header)
// ---------------------------------------------------------------------------

Deno.test("succeeds with no body at all", async () => {
  const response = await handleDeleteAccount(
    deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    buildDeps(),
  );
  assertEquals(response.status, 202);
});

Deno.test("succeeds with an unparsable body, falling back to the header/generated request id", async () => {
  const request = new Request("https://example.com/account", {
    method: "DELETE",
    headers: { Authorization: `Bearer ${VALID_LOOKING_JWT_A}`, "X-Request-Id": "header-id" },
    body: "{ not json",
  });
  const response = await handleDeleteAccount(request, buildDeps());
  assertEquals(response.status, 202);
  const json = await response.json();
  assertEquals(json.request_id, "header-id");
});

Deno.test("a body-supplied request_id is used for correlation when no header is sent", async () => {
  const response = await handleDeleteAccount(
    deleteRequestFor(
      { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
      { request_id: "body-request-id", client_version: "test", body: {} },
    ),
    buildDeps(),
  );
  assertEquals(response.status, 202);
  const json = await response.json();
  assertEquals(json.request_id, "body-request-id");
});

// ---------------------------------------------------------------------------
// Rate limiting
// ---------------------------------------------------------------------------

Deno.test("exceeding the rate limit is a 429 with a Retry-After header", async () => {
  const deps = buildDeps({ rateLimiter: createRateLimiter({ limit: 1, windowMs: 60_000 }) });
  const first = await handleDeleteAccount(
    deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    deps,
  );
  assertEquals(first.status, 202);

  const second = await handleDeleteAccount(
    deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    deps,
  );
  assertEquals(second.status, 429);
  assertEquals((await second.json()).error.category, "rate_limited");
  assertNotEquals(second.headers.get("Retry-After"), null);
});

Deno.test("the rate limit is per user, not global", async () => {
  const deps = buildDeps({ rateLimiter: createRateLimiter({ limit: 1, windowMs: 60_000 }) });
  await handleDeleteAccount(
    deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    deps,
  );
  const other = await handleDeleteAccount(
    deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_B}` }),
    deps,
  );
  assertEquals(other.status, 202);
});

Deno.test("a rate-limited request never calls the repository", async () => {
  const repository = fakeRepository();
  const deps = buildDeps({
    repository,
    rateLimiter: createRateLimiter({ limit: 1, windowMs: 60_000 }),
  });
  await handleDeleteAccount(
    deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    deps,
  );
  repository.calls.requestDeletion.length = 0;
  await handleDeleteAccount(
    deleteRequestFor({ Authorization: `Bearer ${VALID_LOOKING_JWT_A}` }),
    deps,
  );
  assertEquals(repository.calls.requestDeletion.length, 0);
});
