// ============================================================================
// closet/handler_test.ts
// ============================================================================
// Covers, at minimum:
//   - rejects a missing / malformed JWT
//   - rejects a body that fails schema validation
//   - requires Idempotency-Key on analyze-item and replays on repeat
//   - returns a well-formed analysis for a valid request
//   - cannot analyse another user's storage path / job even when a
//     different user_id is supplied in the body (ownership isolation)
//   - batch enqueue returns a job id without analysing synchronously
//   - batch poll advances one item at a time and isolates across users
// ============================================================================

import { assertEquals, assertNotEquals } from "@std/assert";
import type { AuthClient } from "../_shared/jwt.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { MockVisionAnalysisProvider } from "../_shared/providers/mockVisionAnalysis.ts";
import {
  type AnalysisJobRow,
  type AnalysisJobStore,
  type AnalyzeHandlerDeps,
  type BatchHandlerDeps,
  handleAnalyzeItem,
  handleBatchAnalyze,
  handleBatchCancel,
  handleBatchStatus,
  type IdempotencyStore,
} from "./handler.ts";
import type { AnalyzeItemElement, ClosetItemAnalysisResultDTO } from "./schema.ts";

const VALID_LOOKING_JWT_A =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWEifQ.dGhpc19pc19ub3RfYV9yZWFsX3NpZ25hdHVyZQ";
const VALID_LOOKING_JWT_B =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWIifQ.YW5vdGhlcl9mYWtlX3NpZ25hdHVyZQ";

const USER_A_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const USER_B_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ATTACKER_SUPPLIED_UUID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const REQUEST_A = "11111111-1111-4111-8111-111111111111";
const REQUEST_B = "22222222-2222-4222-8222-222222222222";
const REQUEST_C = "33333333-3333-4333-8333-333333333333";

function tokenMappedAuthClient(): AuthClient {
  return {
    auth: {
      getUser(jwt?: string) {
        if (jwt === VALID_LOOKING_JWT_A) {
          return Promise.resolve({
            data: { user: { id: USER_A_ID } },
            error: null,
          });
        }
        if (jwt === VALID_LOOKING_JWT_B) {
          return Promise.resolve({
            data: { user: { id: USER_B_ID } },
            error: null,
          });
        }
        return Promise.resolve({
          data: { user: null },
          error: { message: "invalid token" },
        });
      },
    },
  };
}

function memoryIdempotencyStore(): IdempotencyStore & {
  puts: Array<{ userId: string; key: string }>;
} {
  const map = new Map<
    string,
    { requestHash: string; responsePayload: ClosetItemAnalysisResultDTO }
  >();
  const puts: Array<{ userId: string; key: string }> = [];
  return {
    puts,
    get(userId, key) {
      return Promise.resolve(map.get(`${userId}:${key}`) ?? null);
    },
    put(userId, key, requestHash, responsePayload) {
      puts.push({ userId, key });
      map.set(`${userId}:${key}`, { requestHash, responsePayload });
      return Promise.resolve();
    },
  };
}

function memoryJobStore(): AnalysisJobStore & {
  createCalls: Array<{ userId: string; itemCount: number }>;
  rows: Map<string, AnalysisJobRow>;
} {
  const rows = new Map<string, AnalysisJobRow>();
  const idempotencyKeys = new Map<string, string>();
  const claims = new Map<string, { token: string; expiresAt: number }>();
  const createCalls: Array<{ userId: string; itemCount: number }> = [];
  return {
    rows,
    createCalls,
    create(userId, items, idempotencyKey, requestHash) {
      createCalls.push({ userId, itemCount: items.length });
      const scopedKey = idempotencyKey ? `${userId}:${idempotencyKey}` : null;
      const existingId = scopedKey ? idempotencyKeys.get(scopedKey) : null;
      if (existingId) {
        return Promise.resolve(structuredClone(rows.get(existingId)!));
      }
      const row: AnalysisJobRow = {
        id: crypto.randomUUID(),
        userId,
        status: "queued",
        items: [...items],
        results: [],
        idempotencyKey,
        requestHash,
      };
      rows.set(row.id, structuredClone(row));
      if (scopedKey) idempotencyKeys.set(scopedKey, row.id);
      return Promise.resolve(structuredClone(row));
    },
    getByIdempotencyKey(userId, idempotencyKey) {
      const id = idempotencyKeys.get(`${userId}:${idempotencyKey}`);
      const row = id ? rows.get(id) : null;
      return Promise.resolve(row ? structuredClone(row) : null);
    },
    get(userId, jobId) {
      const row = rows.get(jobId);
      if (!row || row.userId !== userId) {
        return Promise.resolve(null);
      }
      return Promise.resolve(structuredClone(row));
    },
    claimNext(userId, jobId, token, claimedAt, leaseUntil) {
      const row = rows.get(jobId);
      if (
        !row || row.userId !== userId || row.status === "complete" ||
        row.status === "failed"
      ) {
        return Promise.resolve(null);
      }
      const claim = claims.get(jobId);
      if (claim && claim.expiresAt > claimedAt.getTime()) {
        return Promise.resolve(null);
      }
      claims.set(jobId, { token, expiresAt: leaseUntil.getTime() });
      const claimed = { ...row, status: "generating" as const };
      rows.set(jobId, structuredClone(claimed));
      return Promise.resolve(structuredClone(claimed));
    },
    saveClaimed(job, token) {
      if (claims.get(job.id)?.token !== token) return Promise.resolve(false);
      rows.set(job.id, structuredClone(job));
      claims.delete(job.id);
      return Promise.resolve(true);
    },
    releaseClaim(userId, jobId, token) {
      const row = rows.get(jobId);
      if (row?.userId === userId && claims.get(jobId)?.token === token) {
        claims.delete(jobId);
      }
      return Promise.resolve();
    },
    cancelByIdempotencyKey(userId, key, now) {
      const scopedKey = `${userId}:${key}`;
      const id = idempotencyKeys.get(scopedKey);
      const row = id ? rows.get(id) : null;
      if (!row) {
        const tombstone: AnalysisJobRow = {
          id: crypto.randomUUID(),
          userId,
          status: "failed",
          items: [],
          results: [],
          idempotencyKey: key,
          requestHash: "0".repeat(64),
          errorMessage: "Cancelled by the owner.",
        };
        rows.set(tombstone.id, structuredClone(tombstone));
        idempotencyKeys.set(scopedKey, tombstone.id);
        return Promise.resolve(true);
      }
      if (row.status === "complete" || row.status === "failed") {
        return Promise.resolve(true);
      }
      const claim = claims.get(row.id);
      if (claim && claim.expiresAt > now.getTime()) return Promise.resolve(false);
      rows.set(row.id, {
        ...row,
        status: "failed",
        items: [],
        results: [],
        errorMessage: "Cancelled by the owner.",
      });
      claims.delete(row.id);
      return Promise.resolve(true);
    },
  };
}

function fixedHash(canonical: string): Promise<string> {
  // Deterministic enough for tests: pad/truncate a hex-looking digest.
  let hash = 0;
  for (let i = 0; i < canonical.length; i++) {
    hash = (hash * 33 + canonical.charCodeAt(i)) >>> 0;
  }
  return Promise.resolve(hash.toString(16).padStart(64, "0").slice(0, 64));
}

function buildAnalyzeDeps(
  overrides: Partial<AnalyzeHandlerDeps> = {},
): AnalyzeHandlerDeps {
  return {
    authClient: tokenMappedAuthClient(),
    provider: new MockVisionAnalysisProvider(),
    idempotencyStore: memoryIdempotencyStore(),
    rateLimiter: createRateLimiter({ limit: 1000, windowMs: 60_000 }),
    now: () => new Date("2026-08-01T12:00:00Z"),
    hashRequest: fixedHash,
    ...overrides,
  };
}

function buildBatchDeps(
  overrides: Partial<BatchHandlerDeps> = {},
): BatchHandlerDeps & {
  jobStore: ReturnType<typeof memoryJobStore>;
} {
  const jobStore = (overrides.jobStore as ReturnType<typeof memoryJobStore> | undefined) ??
    memoryJobStore();
  return {
    authClient: tokenMappedAuthClient(),
    provider: new MockVisionAnalysisProvider(),
    rateLimiter: createRateLimiter({ limit: 1000, windowMs: 60_000 }),
    now: () => new Date("2026-08-01T12:00:00Z"),
    hashRequest: fixedHash,
    ...overrides,
    jobStore,
  };
}

function analyzeBody(overrides: Record<string, unknown> = {}) {
  return {
    request_id: "test-request-id",
    client_version: "ios/1.0.0",
    body: {
      request_id: REQUEST_A,
      storage_path: `users/${USER_A_ID}/closet/capture.jpg`,
      image_type: "front",
      device_hints: {
        dominant_colors_rgb: ["#1B2A4A"],
        detected_text: ["UNIQLO", "SIZE M"],
        approximate_category: "top",
      },
      ...overrides,
    },
  };
}

function analyzeRequest(
  body: unknown = analyzeBody(),
  headers: Record<string, string> = {},
): Request {
  return new Request("https://example.com/closet/analyze-item", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
      "Idempotency-Key": "idem-1",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

Deno.test("analyze-item rejects a request with no Authorization header", async () => {
  const req = new Request("https://example.com/closet/analyze-item", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Idempotency-Key": "x" },
    body: JSON.stringify(analyzeBody()),
  });
  const response = await handleAnalyzeItem(req, buildAnalyzeDeps());
  assertEquals(response.status, 401);
});

Deno.test("analyze-item rejects a missing Idempotency-Key", async () => {
  const headers = new Headers({
    "Content-Type": "application/json",
    Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
  });
  const bare = new Request("https://example.com/closet/analyze-item", {
    method: "POST",
    headers,
    body: JSON.stringify(analyzeBody()),
  });
  const response = await handleAnalyzeItem(bare, buildAnalyzeDeps());
  assertEquals(response.status, 400);
  const json = await response.json();
  assertEquals(json.error.category, "validation");
});

Deno.test("analyze-item rejects a body that fails schema validation", async () => {
  const response = await handleAnalyzeItem(
    analyzeRequest({
      request_id: "r",
      client_version: "ios/1.0.0",
      body: {
        request_id: "not-a-uuid",
        storage_path: "x",
        image_type: "front",
      },
    }),
    buildAnalyzeDeps(),
  );
  assertEquals(response.status, 400);
});

Deno.test("analyze-item returns a well-formed analysis for a valid request", async () => {
  const response = await handleAnalyzeItem(
    analyzeRequest(),
    buildAnalyzeDeps(),
  );
  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.error, null);
  assertEquals(json.data.category.value, "top");
  assertEquals(typeof json.data.name.value, "string");
  assertEquals(
    Array.isArray(json.data.fields_below_confidence_threshold),
    true,
  );
  assertEquals(json.data.ocr_text.includes("UNIQLO"), true);
});

Deno.test(
  "a defaulted category is marked low-confidence rather than asserted",
  async () => {
    // The real device pass sends no `approximate_category` — nothing in
    // `DeviceHintsExtraction` computes one — so this, not the test fixture
    // above, is the shape every production request actually has. The mock
    // provider defaults to "top"; what must not happen is defaulting to
    // "top" and then reporting it at the same confidence as a reading,
    // which would tell a man photographing shoes that he owns a crewneck
    // sweater with nothing on screen to hedge it.
    const body = analyzeBody();
    const inner = (body as { body: Record<string, unknown> }).body;
    const hints = inner.device_hints as Record<string, unknown>;
    delete hints.approximate_category;

    const response = await handleAnalyzeItem(
      analyzeRequest(body),
      buildAnalyzeDeps(),
    );
    assertEquals(response.status, 200);
    const json = await response.json();
    const marked: string[] = json.data.fields_below_confidence_threshold;
    assertEquals(marked.includes("category"), true);
    assertEquals(marked.includes("subcategory"), true);
    assertEquals(json.data.category.confidence < 0.6, true);
  },
);

Deno.test("a read category is not marked low-confidence", async () => {
  const response = await handleAnalyzeItem(
    analyzeRequest(),
    buildAnalyzeDeps(),
  );
  const json = await response.json();
  const marked: string[] = json.data.fields_below_confidence_threshold;
  assertEquals(marked.includes("category"), false);
  assertEquals(json.data.category.confidence > 0.6, true);
});

Deno.test("analyze-item replays a prior response for the same Idempotency-Key", async () => {
  const store = memoryIdempotencyStore();
  const deps = buildAnalyzeDeps({ idempotencyStore: store });
  const first = await handleAnalyzeItem(analyzeRequest(), deps);
  assertEquals(first.status, 200);
  const firstJson = await first.json();
  assertEquals(store.puts.length, 1);

  const second = await handleAnalyzeItem(analyzeRequest(), deps);
  assertEquals(second.status, 200);
  const secondJson = await second.json();
  assertEquals(secondJson.data, firstJson.data);
  assertEquals(store.puts.length, 1);
});

Deno.test(
  "analyze-item cannot use another user's storage path even when a different user_id is supplied in the body",
  async () => {
    const response = await handleAnalyzeItem(
      analyzeRequest({
        request_id: "attack",
        client_version: "ios/1.0.0",
        body: {
          request_id: REQUEST_A,
          storage_path: `users/${USER_B_ID}/closet/secret.jpg`,
          image_type: "front",
          user_id: ATTACKER_SUPPLIED_UUID,
        },
      }),
      buildAnalyzeDeps(),
    );
    assertEquals(response.status, 400);
    const json = await response.json();
    assertEquals(json.error.category, "validation");
  },
);

Deno.test("batch-analyze enqueues a job without analysing synchronously", async () => {
  const deps = buildBatchDeps();
  const providerCalls: string[] = [];
  const provider = new MockVisionAnalysisProvider();
  const original = provider.analyzeGarment.bind(provider);
  provider.analyzeGarment = (request, ctx) => {
    providerCalls.push(request.imageStoragePath);
    return original(request, ctx);
  };
  deps.provider = provider;

  const req = new Request("https://example.com/closet/batch-analyze", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
      "Idempotency-Key": "batch-owner-check",
    },
    body: JSON.stringify({
      request_id: "batch-1",
      client_version: "ios/1.0.0",
      body: {
        items: [
          {
            request_id: REQUEST_A,
            storage_path: `users/${USER_A_ID}/closet/a.jpg`,
            image_type: "front",
          },
          {
            request_id: REQUEST_B,
            storage_path: `users/${USER_A_ID}/closet/b.jpg`,
            image_type: "front",
          },
        ],
        user_id: ATTACKER_SUPPLIED_UUID,
      },
    }),
  });

  const response = await handleBatchAnalyze(req, deps);
  assertEquals(response.status, 202);
  const json = await response.json();
  assertEquals(typeof json.data.job_id, "string");
  assertEquals(json.data.status, "queued");
  assertEquals(providerCalls.length, 0);
  assertEquals(deps.jobStore.createCalls, [{
    userId: USER_A_ID,
    itemCount: 2,
  }]);
  assertNotEquals(deps.jobStore.createCalls[0]?.userId, ATTACKER_SUPPLIED_UUID);
});

Deno.test("batch-analyze replays the same owner job for a repeated idempotency key", async () => {
  const deps = buildBatchDeps({
    rateLimiter: createRateLimiter({ limit: 1, windowMs: 60_000 }),
  });
  const makeRequest = () =>
    new Request("https://example.com/closet/batch-analyze", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
        "Idempotency-Key": "stable-batch-key",
      },
      body: JSON.stringify({
        request_id: "batch-retry",
        client_version: "ios/1.0.0",
        body: {
          items: [{
            request_id: REQUEST_A,
            storage_path: `users/${USER_A_ID}/closet/a.jpg`,
            image_type: "front",
          }],
        },
      }),
    });

  const first = await handleBatchAnalyze(makeRequest(), deps);
  const firstBody = await first.json();
  const replay = await handleBatchAnalyze(makeRequest(), deps);
  const replayBody = await replay.json();

  assertEquals(first.status, 202);
  assertEquals(replay.status, 202);
  assertEquals(replayBody.data.job_id, firstBody.data.job_id);
  assertEquals(deps.jobStore.createCalls.length, 1);
});

Deno.test("batch-analyze rejects a changed body under an existing idempotency key", async () => {
  const deps = buildBatchDeps();
  const makeRequest = (path: string) =>
    new Request("https://example.com/closet/batch-analyze", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
        "Idempotency-Key": "stable-batch-key",
      },
      body: JSON.stringify({
        request_id: "batch-changed",
        client_version: "ios/1.0.0",
        body: {
          items: [{
            request_id: REQUEST_A,
            storage_path: path,
            image_type: "front",
          }],
        },
      }),
    });

  const first = await handleBatchAnalyze(
    makeRequest(`users/${USER_A_ID}/closet/a.jpg`),
    deps,
  );
  const conflict = await handleBatchAnalyze(
    makeRequest(`users/${USER_A_ID}/closet/b.jpg`),
    deps,
  );

  assertEquals(first.status, 202);
  assertEquals(conflict.status, 409);
  assertEquals(deps.jobStore.createCalls.length, 1);
});

Deno.test("batch-analyze scopes idempotency keys to the authenticated owner", async () => {
  const deps = buildBatchDeps();
  const requestFor = (token: string, userId: string) =>
    new Request(
      "https://example.com/closet/batch-analyze",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
          "Idempotency-Key": "shared-key",
        },
        body: JSON.stringify({
          request_id: "owner-scoped-key",
          client_version: "ios/1.0.0",
          body: {
            items: [{
              request_id: REQUEST_A,
              storage_path: `users/${userId}/closet/a.jpg`,
              image_type: "front",
            }],
          },
        }),
      },
    );

  const ownerResponse = await handleBatchAnalyze(
    requestFor(VALID_LOOKING_JWT_A, USER_A_ID),
    deps,
  );
  const peerResponse = await handleBatchAnalyze(
    requestFor(VALID_LOOKING_JWT_B, USER_B_ID),
    deps,
  );
  const ownerBody = await ownerResponse.json();
  const peerBody = await peerResponse.json();

  assertEquals(ownerResponse.status, 202);
  assertEquals(peerResponse.status, 202);
  assertNotEquals(ownerBody.data.job_id, peerBody.data.job_id);
  assertEquals(deps.jobStore.createCalls.length, 2);
});

Deno.test("batch-cancel preserves a live worker and clears a safely abandoned job", async () => {
  const deps = buildBatchDeps();
  const job = await deps.jobStore.create(
    USER_A_ID,
    [{ requestId: REQUEST_A, storagePath: `users/${USER_A_ID}/closet/a.jpg`, imageType: "front" }],
    "cancel-key",
    "d".repeat(64),
  );
  await deps.jobStore.claimNext(
    USER_A_ID,
    job.id,
    "active-worker",
    deps.now(),
    new Date(deps.now().getTime() + 60_000),
  );
  const request = (token: string) =>
    new Request("https://example.com/closet/batch-cancel", {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Idempotency-Key": "cancel-key" },
    });

  const conflict = await handleBatchCancel(request(VALID_LOOKING_JWT_A), deps);
  assertEquals(conflict.status, 409);
  assertEquals(deps.jobStore.rows.get(job.id)?.status, "generating");

  await deps.jobStore.releaseClaim(USER_A_ID, job.id, "active-worker");
  const cancelled = await handleBatchCancel(request(VALID_LOOKING_JWT_A), deps);
  assertEquals(cancelled.status, 200);
  assertEquals(deps.jobStore.rows.get(job.id)?.status, "failed");
  assertEquals(deps.jobStore.rows.get(job.id)?.items.length, 0);
  assertEquals(deps.jobStore.rows.get(job.id)?.results.length, 0);

  const peer = await handleBatchCancel(request(VALID_LOOKING_JWT_B), deps);
  assertEquals(peer.status, 200);
  assertEquals(deps.jobStore.rows.get(job.id)?.status, "failed");
});

Deno.test("batch-cancel keeps completed analysis results", async () => {
  const deps = buildBatchDeps();
  const job = await deps.jobStore.create(
    USER_A_ID,
    [{ requestId: REQUEST_A, storagePath: `users/${USER_A_ID}/closet/a.jpg`, imageType: "front" }],
    "completed-cancel-key",
    "e".repeat(64),
  );
  const completed: AnalysisJobRow = {
    ...job,
    status: "complete",
    results: [{ request_id: REQUEST_A, result: {} as ClosetItemAnalysisResultDTO }],
  };
  deps.jobStore.rows.set(job.id, completed);

  const response = await handleBatchCancel(
    new Request("https://example.com/closet/batch-cancel", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
        "Idempotency-Key": "completed-cancel-key",
      },
    }),
    deps,
  );

  assertEquals(response.status, 200);
  assertEquals(deps.jobStore.rows.get(job.id), completed);
});

Deno.test("batch-cancel tombstone fences an enqueue that arrives later", async () => {
  const deps = buildBatchDeps();
  const cancelled = await handleBatchCancel(
    new Request("https://example.com/closet/batch-cancel", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
        "Idempotency-Key": "cancel-before-enqueue",
      },
    }),
    deps,
  );
  assertEquals(cancelled.status, 200);

  const lateEnqueue = await handleBatchAnalyze(
    new Request("https://example.com/closet/batch-analyze", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
        "Idempotency-Key": "cancel-before-enqueue",
      },
      body: JSON.stringify({
        request_id: "late-enqueue",
        client_version: "ios/1.0.0",
        body: {
          items: [{
            request_id: REQUEST_A,
            storage_path: `users/${USER_A_ID}/closet/a.jpg`,
            image_type: "front",
          }],
        },
      }),
    }),
    deps,
  );
  assertEquals(lateEnqueue.status, 409);
  assertEquals(deps.jobStore.createCalls.length, 0);
});

Deno.test("batch-status advances one item per poll and completes keyed by request_id", async () => {
  const deps = buildBatchDeps();
  const items: AnalyzeItemElement[] = [
    {
      requestId: REQUEST_A,
      storagePath: `users/${USER_A_ID}/closet/a.jpg`,
      imageType: "front",
      deviceHints: {
        dominantColorsRgb: ["#112233"],
        detectedText: [],
        approximateCategory: "top",
      },
    },
    {
      requestId: REQUEST_B,
      storagePath: `users/${USER_A_ID}/closet/b.jpg`,
      imageType: "front",
      deviceHints: {
        dominantColorsRgb: ["#445566"],
        detectedText: [],
        approximateCategory: "bottom",
      },
    },
    {
      requestId: REQUEST_C,
      storagePath: `users/${USER_A_ID}/closet/c.jpg`,
      imageType: "front",
    },
  ];
  const job = await deps.jobStore.create(USER_A_ID, items);

  const poll = () =>
    handleBatchStatus(
      new Request(`https://example.com/closet/batch-status/${job.id}`, {
        method: "GET",
        headers: { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
      }),
      deps,
      job.id,
    );

  const first = await poll();
  assertEquals(first.status, 200);
  const firstJson = await first.json();
  assertEquals(firstJson.data.status, "generating");
  assertEquals(firstJson.data.results.length, 1);
  assertEquals(firstJson.data.results[0].request_id, REQUEST_A);

  const second = await poll();
  const secondJson = await second.json();
  assertEquals(secondJson.data.results.length, 2);

  const third = await poll();
  const thirdJson = await third.json();
  assertEquals(thirdJson.data.status, "complete");
  assertEquals(thirdJson.data.results.length, 3);
  const ids = thirdJson.data.results.map((r: { request_id: string }) => r.request_id);
  assertEquals(new Set(ids), new Set([REQUEST_A, REQUEST_B, REQUEST_C]));
});

Deno.test("concurrent batch-status polls invoke the provider once for the claimed item", async () => {
  const deps = buildBatchDeps();
  const job = await deps.jobStore.create(USER_A_ID, [{
    requestId: REQUEST_A,
    storagePath: `users/${USER_A_ID}/closet/a.jpg`,
    imageType: "front",
  }]);
  const provider = deps.provider as MockVisionAnalysisProvider;
  const originalAnalyze = provider.analyzeGarment.bind(provider);
  let providerCalls = 0;
  let notifyProviderStarted!: () => void;
  let releaseProvider!: () => void;
  const providerStarted = new Promise<void>((resolve) => notifyProviderStarted = resolve);
  const providerGate = new Promise<void>((resolve) => releaseProvider = resolve);
  provider.analyzeGarment = async (request, context) => {
    providerCalls += 1;
    notifyProviderStarted();
    await providerGate;
    return await originalAnalyze(request, context);
  };

  const poll = () =>
    handleBatchStatus(
      new Request(`https://example.com/closet/batch-status/${job.id}`, {
        method: "GET",
        headers: { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
      }),
      deps,
      job.id,
    );

  const firstPoll = poll();
  await providerStarted;
  const concurrentPoll = await poll();
  const concurrentPayload = await concurrentPoll.json();
  assertEquals(concurrentPoll.status, 200);
  assertEquals(concurrentPayload.data.status, "generating");
  assertEquals(concurrentPayload.data.results.length, 0);
  assertEquals(providerCalls, 1);

  releaseProvider();
  const firstResponse = await firstPoll;
  const firstPayload = await firstResponse.json();
  assertEquals(firstPayload.data.status, "complete");
  assertEquals(firstPayload.data.results.length, 1);
  assertEquals(providerCalls, 1);
});

Deno.test("batch-status cannot read another user's job", async () => {
  const deps = buildBatchDeps();
  const job = await deps.jobStore.create(USER_A_ID, [
    {
      requestId: REQUEST_A,
      storagePath: `users/${USER_A_ID}/closet/a.jpg`,
      imageType: "front",
    },
  ]);

  const response = await handleBatchStatus(
    new Request(`https://example.com/closet/batch-status/${job.id}`, {
      method: "GET",
      headers: { Authorization: `Bearer ${VALID_LOOKING_JWT_B}` },
    }),
    deps,
    job.id,
  );
  assertEquals(response.status, 404);
});

Deno.test("batch-analyze rejects another user's storage path in the batch", async () => {
  const deps = buildBatchDeps();
  const req = new Request("https://example.com/closet/batch-analyze", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
    },
    body: JSON.stringify({
      request_id: "batch-attack",
      client_version: "ios/1.0.0",
      body: {
        items: [
          {
            request_id: REQUEST_A,
            storage_path: `users/${USER_B_ID}/closet/stolen.jpg`,
            image_type: "front",
          },
        ],
      },
    }),
  });
  const response = await handleBatchAnalyze(req, deps);
  assertEquals(response.status, 400);
  assertEquals(deps.jobStore.createCalls.length, 0);
});

Deno.test("closet analyze and batch handlers return exact rate-limit reset hints", async () => {
  const limiter = createRateLimiter({ limit: 1, windowMs: 60_000 });
  limiter.check(USER_A_ID, Date.parse("2026-08-01T12:00:00Z"));
  const analyzeResponse = await handleAnalyzeItem(
    analyzeRequest(),
    buildAnalyzeDeps({ rateLimiter: limiter }),
  );
  assertEquals(analyzeResponse.status, 429);
  assertEquals(analyzeResponse.headers.get("Retry-After"), "60");

  const batchLimiter = createRateLimiter({ limit: 1, windowMs: 60_000 });
  batchLimiter.check(USER_A_ID, Date.parse("2026-08-01T12:00:00Z"));
  const batchResponse = await handleBatchAnalyze(
    new Request("https://example.com/closet/batch-analyze", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
        "Idempotency-Key": "rate-limited-batch",
      },
      body: JSON.stringify({
        request_id: "limit",
        client_version: "ios/1.0.0",
        body: {
          items: [{
            request_id: REQUEST_A,
            storage_path: `users/${USER_A_ID}/closet/a.jpg`,
            image_type: "front",
          }],
        },
      }),
    }),
    buildBatchDeps({ rateLimiter: batchLimiter }),
  );
  assertEquals(batchResponse.status, 429);
  assertEquals(batchResponse.headers.get("Retry-After"), "60");

  const statusLimiter = createRateLimiter({ limit: 1, windowMs: 60_000 });
  statusLimiter.check(USER_A_ID, Date.parse("2026-08-01T12:00:00Z"));
  const jobID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const statusResponse = await handleBatchStatus(
    new Request(`https://example.com/closet/batch-status/${jobID}`, {
      method: "GET",
      headers: { Authorization: `Bearer ${VALID_LOOKING_JWT_A}` },
    }),
    buildBatchDeps({ rateLimiter: statusLimiter }),
    jobID,
  );
  assertEquals(statusResponse.status, 429);
  assertEquals(statusResponse.headers.get("Retry-After"), "60");
});
