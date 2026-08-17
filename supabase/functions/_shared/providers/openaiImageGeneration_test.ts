// ============================================================================
// _shared/providers/openaiImageGeneration_test.ts
// ============================================================================
// The live adapter, tested entirely offline via an injected `fetchImpl` —
// no network, no key, no spend. Covers the request shape (model pin, size,
// quality tiering), result re-hosting, and the error taxonomy mapping the
// handler's retry logic depends on.
// ============================================================================

import { assert, assertEquals, assertRejects } from "@std/assert";
import { ProviderError } from "./types.ts";
import { OpenAIImageGenerationProvider } from "./openaiImageGeneration.ts";
import { type ImageGenerationRequest, studioResultPath } from "./imageGeneration.ts";

const USER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const GENERATION_ID = "12121212-1212-4121-8121-121212121212";
const CTX = { requestId: "req-1", userId: USER_ID, timeoutMs: 5000 };

function request(overrides: Partial<ImageGenerationRequest> = {}): ImageGenerationRequest {
  return {
    generationId: GENERATION_ID,
    referenceImageStoragePath: `users/${USER_ID}/references/selfie.jpg`,
    structuredGarmentList: [],
    prompt: "Create a realistic editorial menswear visualization…",
    pose: "standing_front",
    background: "studio",
    lighting: "",
    formality: "",
    resolution: "draft",
    preserveFace: true,
    preserveBodyProportions: true,
    preserveHairFacialHair: true,
    ...overrides,
  };
}

function memoryStorage() {
  const objects = new Map<string, Uint8Array>();
  return {
    objects,
    storeResult(path: string, bytes: Uint8Array, _contentType: string): Promise<void> {
      objects.set(path, bytes);
      return Promise.resolve();
    },
    resultExists(path: string): Promise<boolean> {
      return Promise.resolve(objects.has(path));
    },
  };
}

function buildProvider(
  fetchImpl: typeof fetch,
  storage = memoryStorage(),
): { provider: OpenAIImageGenerationProvider; storage: ReturnType<typeof memoryStorage> } {
  return {
    storage,
    provider: new OpenAIImageGenerationProvider({
      apiKey: "test-key-never-real",
      model: "gpt-image-1.5",
      loadImageBytes: () => Promise.resolve(new Uint8Array([1, 2, 3])),
      storeResult: storage.storeResult,
      resultExists: storage.resultExists,
      fetchImpl,
    }),
  };
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status });
}

Deno.test("the multipart form pins the model and maps draft/hi_res to medium/high", () => {
  const { provider } = buildProvider(fetch);
  const draft = provider.buildForm(request({ resolution: "draft" }), new Uint8Array([1]));
  assertEquals(draft.get("model"), "gpt-image-1.5");
  assertEquals(draft.get("size"), "1024x1536");
  assertEquals(draft.get("quality"), "medium");
  assertEquals(draft.get("n"), "1");
  assert(draft.get("image") instanceof Blob);
  const hiRes = provider.buildForm(request({ resolution: "hi_res" }), new Uint8Array([1]));
  assertEquals(hiRes.get("quality"), "high");
});

Deno.test("a successful render is decoded and re-hosted at the deterministic path", async () => {
  const b64 = btoa("fake-png-bytes");
  const { provider, storage } = buildProvider(() =>
    Promise.resolve(jsonResponse(200, { data: [{ b64_json: b64 }] }))
  );
  const { providerJobId } = await provider.submitGeneration(request(), CTX);
  assertEquals(providerJobId, GENERATION_ID);
  const path = studioResultPath(USER_ID, GENERATION_ID);
  const stored = storage.objects.get(path);
  assert(stored !== undefined);
  assertEquals(new TextDecoder().decode(stored), "fake-png-bytes");

  const poll = await provider.pollStatus(providerJobId, CTX);
  assertEquals(poll.status, "complete");
  assertEquals(poll.resultStoragePath, path);
});

Deno.test("error taxonomy: statuses and codes map to the shared ProviderError vocabulary", async () => {
  const cases: Array<{ status: number; body: unknown; code: string; retryable: boolean }> = [
    { status: 401, body: {}, code: "AUTH_FAILED", retryable: false },
    { status: 400, body: {}, code: "INVALID_INPUT", retryable: false },
    {
      status: 400,
      body: { error: { code: "moderation_blocked" } },
      code: "CONTENT_MODERATION_REJECTED",
      retryable: false,
    },
    { status: 429, body: {}, code: "RATE_LIMITED", retryable: true },
    {
      status: 429,
      body: { error: { code: "insufficient_quota" } },
      code: "PROVIDER_QUOTA_EXCEEDED",
      retryable: false,
    },
    { status: 500, body: {}, code: "PROVIDER_UNAVAILABLE", retryable: true },
  ];
  for (const testCase of cases) {
    const { provider } = buildProvider(() =>
      Promise.resolve(jsonResponse(testCase.status, testCase.body))
    );
    const err = await assertRejects(
      () => provider.submitGeneration(request(), CTX),
      ProviderError,
    );
    assertEquals(err.code, testCase.code, `HTTP ${testCase.status}`);
    assertEquals(err.retryable, testCase.retryable, `HTTP ${testCase.status}`);
  }
});

Deno.test("a 200 with no image data is an UNKNOWN failure, not a silent success", async () => {
  const { provider, storage } = buildProvider(() =>
    Promise.resolve(jsonResponse(200, { data: [] }))
  );
  const err = await assertRejects(
    () => provider.submitGeneration(request(), CTX),
    ProviderError,
  );
  assertEquals(err.code, "UNKNOWN");
  assertEquals(storage.objects.size, 0);
});

Deno.test("an unreachable endpoint maps to a retryable PROVIDER_UNAVAILABLE", async () => {
  const { provider } = buildProvider(() => Promise.reject(new TypeError("connection refused")));
  const err = await assertRejects(
    () => provider.submitGeneration(request(), CTX),
    ProviderError,
  );
  assertEquals(err.code, "PROVIDER_UNAVAILABLE");
  assertEquals(err.retryable, true);
});

Deno.test("poll for a lost render fails retryably instead of reporting progress", async () => {
  const { provider } = buildProvider(fetch);
  const result = await provider.pollStatus(GENERATION_ID, CTX);
  assertEquals(result.status, "failed");
  assertEquals(result.isRetryableFailure, true);
});
