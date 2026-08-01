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
  const createCalls: Array<{ userId: string; itemCount: number }> = [];
  return {
    rows,
    createCalls,
    create(userId, items) {
      createCalls.push({ userId, itemCount: items.length });
      const row: AnalysisJobRow = {
        id: crypto.randomUUID(),
        userId,
        status: "queued",
        items: [...items],
        results: [],
      };
      rows.set(row.id, structuredClone(row));
      return Promise.resolve(structuredClone(row));
    },
    get(userId, jobId) {
      const row = rows.get(jobId);
      if (!row || row.userId !== userId) {
        return Promise.resolve(null);
      }
      return Promise.resolve(structuredClone(row));
    },
    save(job) {
      rows.set(job.id, structuredClone(job));
      return Promise.resolve();
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

function buildAnalyzeDeps(overrides: Partial<AnalyzeHandlerDeps> = {}): AnalyzeHandlerDeps {
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

function buildBatchDeps(overrides: Partial<BatchHandlerDeps> = {}): BatchHandlerDeps & {
  jobStore: ReturnType<typeof memoryJobStore>;
} {
  const jobStore = (overrides.jobStore as ReturnType<typeof memoryJobStore> | undefined) ??
    memoryJobStore();
  return {
    authClient: tokenMappedAuthClient(),
    provider: new MockVisionAnalysisProvider(),
    rateLimiter: createRateLimiter({ limit: 1000, windowMs: 60_000 }),
    now: () => new Date("2026-08-01T12:00:00Z"),
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
      body: { request_id: "not-a-uuid", storage_path: "x", image_type: "front" },
    }),
    buildAnalyzeDeps(),
  );
  assertEquals(response.status, 400);
});

Deno.test("analyze-item returns a well-formed analysis for a valid request", async () => {
  const response = await handleAnalyzeItem(analyzeRequest(), buildAnalyzeDeps());
  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.error, null);
  assertEquals(json.data.category.value, "top");
  assertEquals(typeof json.data.name.value, "string");
  assertEquals(Array.isArray(json.data.fields_below_confidence_threshold), true);
  assertEquals(json.data.ocr_text.includes("UNIQLO"), true);
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
  assertEquals(deps.jobStore.createCalls, [{ userId: USER_A_ID, itemCount: 2 }]);
  assertNotEquals(deps.jobStore.createCalls[0]?.userId, ATTACKER_SUPPLIED_UUID);
});

Deno.test("batch-status advances one item per poll and completes keyed by request_id", async () => {
  const deps = buildBatchDeps();
  const items: AnalyzeItemElement[] = [
    {
      requestId: REQUEST_A,
      storagePath: `users/${USER_A_ID}/closet/a.jpg`,
      imageType: "front",
      deviceHints: { dominantColorsRgb: ["#112233"], detectedText: [], approximateCategory: "top" },
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
