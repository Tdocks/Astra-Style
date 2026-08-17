// ============================================================================
// _shared/providers/mockImageGeneration_test.ts
// ============================================================================
// P6-STUDIO-03's mock half: a static placeholder image with the correct
// metadata shape, written to the real deterministic result path, honest
// when the object is missing.
// ============================================================================

import { assert, assertEquals, assertRejects } from "@std/assert";
import { ProviderError } from "./types.ts";
import { MockImageGenerationProvider, placeholderPngBytes } from "./mockImageGeneration.ts";
import { type ImageGenerationRequest, studioResultPath } from "./imageGeneration.ts";

const USER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const GENERATION_ID = "12121212-1212-4121-8121-121212121212";

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

const CTX = { requestId: "req-1", userId: USER_ID, timeoutMs: 1000 };

Deno.test("the placeholder is a real PNG, not a claimed path", () => {
  const bytes = placeholderPngBytes();
  // PNG signature: 137 80 78 71 13 10 26 10.
  assertEquals([...bytes.slice(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
});

Deno.test("submit writes the placeholder to the deterministic §15 path", async () => {
  const storage = memoryStorage();
  const provider = new MockImageGenerationProvider(storage);
  const { providerJobId } = await provider.submitGeneration(request(), CTX);
  assertEquals(providerJobId, GENERATION_ID);
  const expectedPath = studioResultPath(USER_ID, GENERATION_ID);
  assertEquals(expectedPath, `users/${USER_ID}/studio/${GENERATION_ID}/result.png`);
  assert(storage.objects.has(expectedPath));
});

Deno.test("poll reports complete once the object exists, with the correct metadata shape", async () => {
  const storage = memoryStorage();
  const provider = new MockImageGenerationProvider(storage);
  await provider.submitGeneration(request(), CTX);
  const result = await provider.pollStatus(GENERATION_ID, CTX);
  assertEquals(result.status, "complete");
  assertEquals(result.resultStoragePath, studioResultPath(USER_ID, GENERATION_ID));
  assertEquals(result.providerJobId, GENERATION_ID);
  assertEquals(result.errorMessage, null);
  assertEquals(result.isRetryableFailure, false);
});

Deno.test("poll for a job whose object never landed fails retryably rather than spinning", async () => {
  const provider = new MockImageGenerationProvider(memoryStorage());
  const result = await provider.pollStatus(GENERATION_ID, CTX);
  assertEquals(result.status, "failed");
  assertEquals(result.isRetryableFailure, true);
  assertEquals(result.resultStoragePath, null);
});

Deno.test("an empty prompt is rejected the way a live vendor would reject it", async () => {
  const provider = new MockImageGenerationProvider(memoryStorage());
  await assertRejects(
    () => provider.submitGeneration(request({ prompt: "  " }), CTX),
    ProviderError,
  );
});
