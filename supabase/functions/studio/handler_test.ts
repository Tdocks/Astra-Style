// ============================================================================
// studio/handler_test.ts
// ============================================================================
// Covers, at minimum:
//   - rejects a missing / malformed JWT
//   - the consent gate: no acknowledgment → no row, specific message;
//     stale terms → refused; identity comes from the JWT, never the body
//   - a valid generate creates a `queued` row BEFORE returning (the
//     P6-STUDIO-04 acceptance criterion), disclaimer attached at birth
//   - status polling advances queued → generating → complete with a
//     populated result_image_path (P6-STUDIO-06)
//   - polling an unowned/missing/deleted job returns the same 404
//   - provider failures: retryable faults leave the row where it was;
//     terminal faults produce a user-facing message, never raw provider
//     text (§21)
//   - retry copies prompt_payload verbatim, keeps the failed row, and
//     re-runs the consent-staleness check
// ============================================================================

import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import type { AuthClient } from "../_shared/jwt.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { ProviderError } from "../_shared/providers/types.ts";
import type {
  ImageGenerationProvider,
  StudioGarment,
} from "../_shared/providers/imageGeneration.ts";
import { MockImageGenerationProvider } from "../_shared/providers/mockImageGeneration.ts";
import {
  advanceGeneration,
  handleGenerate,
  handleStatus,
  type StudioGenerationRow,
  type StudioHandlerDeps,
  type StudioJobStore,
} from "./handler.ts";
import { CURRENT_STUDIO_CONSENT_TERMS_VERSION } from "./schema.ts";

const VALID_LOOKING_JWT_A =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWEifQ.dGhpc19pc19ub3RfYV9yZWFsX3NpZ25hdHVyZQ";
const VALID_LOOKING_JWT_B =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWIifQ.YW5vdGhlcl9mYWtlX3NpZ25hdHVyZQ";

const USER_A_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const USER_B_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const OUTFIT_ID = "12121212-1212-4121-8121-121212121212";

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

function memoryJobStore(): StudioJobStore & { rows: Map<string, StudioGenerationRow> } {
  const rows = new Map<string, StudioGenerationRow>();
  const nowIso = () => new Date("2026-08-17T09:00:00Z").toISOString();
  return {
    rows,
    insert(row) {
      const stored: StudioGenerationRow = {
        id: crypto.randomUUID(),
        userId: row.userId,
        referenceImagePath: row.referenceImagePath,
        outfitId: row.outfitId,
        promptPayload: structuredClone(row.promptPayload),
        status: "queued",
        resultImagePath: null,
        provider: row.provider,
        errorMessage: null,
        deletedAt: null,
        createdAt: nowIso(),
        updatedAt: nowIso(),
      };
      rows.set(stored.id, structuredClone(stored));
      return Promise.resolve(structuredClone(stored));
    },
    get(userId, id) {
      const row = rows.get(id);
      // Mirrors RLS: someone else's row and a missing row are the same null.
      if (!row || row.userId !== userId) {
        return Promise.resolve(null);
      }
      return Promise.resolve(structuredClone(row));
    },
    update(userId, id, patch) {
      const row = rows.get(id);
      if (!row || row.userId !== userId) {
        throw new Error("update on a row the caller cannot see");
      }
      if (patch.status !== undefined) row.status = patch.status;
      if (patch.resultImagePath !== undefined) row.resultImagePath = patch.resultImagePath;
      if (patch.errorMessage !== undefined) row.errorMessage = patch.errorMessage;
      if (patch.promptPayload !== undefined) {
        row.promptPayload = structuredClone(patch.promptPayload);
      }
      row.updatedAt = nowIso();
      rows.set(id, row);
      return Promise.resolve(structuredClone(row));
    },
  };
}

const FIXTURE_GARMENTS: StudioGarment[] = [
  {
    role: "top",
    normalizedTitle: "crewneck sweater",
    colorDescription: "navy",
    material: ["merino wool"],
    pattern: "solid",
    fit: "regular",
  },
];

function memoryGarmentSource() {
  return {
    outfitGarments(_userId: string, outfitId: string): Promise<StudioGarment[]> {
      return Promise.resolve(outfitId === OUTFIT_ID ? FIXTURE_GARMENTS : []);
    },
    itemGarments(_userId: string, itemIds: string[]): Promise<StudioGarment[]> {
      return Promise.resolve(itemIds.length > 0 ? FIXTURE_GARMENTS : []);
    },
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

function buildDeps(): StudioHandlerDeps & {
  jobStore: ReturnType<typeof memoryJobStore>;
  storage: ReturnType<typeof memoryStorage>;
} {
  const storage = memoryStorage();
  return {
    authClient: tokenMappedAuthClient(),
    provider: new MockImageGenerationProvider(storage),
    providerName: "mock",
    jobStore: memoryJobStore(),
    garmentSource: memoryGarmentSource(),
    generateRateLimiter: createRateLimiter({ limit: 1000, windowMs: 60_000 }),
    statusRateLimiter: createRateLimiter({ limit: 1000, windowMs: 60_000 }),
    now: () => new Date("2026-08-17T09:00:00Z"),
    storage,
  };
}

function generateBody(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    reference_image_path: `users/${USER_A_ID}/references/selfie.jpg`,
    outfit_id: OUTFIT_ID,
    consent: {
      acknowledged: true,
      terms_version: CURRENT_STUDIO_CONSENT_TERMS_VERSION,
    },
    ...overrides,
  };
}

function generateRequest(jwt: string | null, body: unknown): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (jwt !== null) {
    headers["Authorization"] = `Bearer ${jwt}`;
  }
  return new Request("http://localhost/studio/generate", {
    method: "POST",
    headers,
    body: JSON.stringify({ request_id: crypto.randomUUID(), body }),
  });
}

function statusRequest(jwt: string, id: string): Request {
  return new Request(`http://localhost/studio/status/${id}`, {
    method: "GET",
    headers: { Authorization: `Bearer ${jwt}` },
  });
}

async function envelopeOf(response: Response): Promise<{
  data: Record<string, unknown> | null;
  error: { category: string; message: string } | null;
}> {
  return await response.json();
}

Deno.test("generate rejects a missing or malformed JWT", async () => {
  const deps = buildDeps();
  const missing = await handleGenerate(generateRequest(null, generateBody()), deps);
  assertEquals(missing.status, 401);
  await missing.body?.cancel();
  const malformed = await handleGenerate(generateRequest("not-a-jwt", generateBody()), deps);
  assertEquals(malformed.status, 401);
  await malformed.body?.cancel();
  assertEquals(deps.jobStore.rows.size, 0);
});

Deno.test("consent gate: no acknowledgment → 400, specific message, and NO row", async () => {
  const deps = buildDeps();
  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, generateBody({ consent: undefined })),
    deps,
  );
  assertEquals(response.status, 400);
  const { error } = await envelopeOf(response);
  assertStringIncludes(error?.message ?? "", "hasn't been confirmed");
  assertEquals(deps.jobStore.rows.size, 0);
});

Deno.test("consent gate: an attestation to old terms is refused, not carried forward", async () => {
  const deps = buildDeps();
  const response = await handleGenerate(
    generateRequest(
      VALID_LOOKING_JWT_A,
      generateBody({ consent: { acknowledged: true, terms_version: "2020-01-01" } }),
    ),
    deps,
  );
  assertEquals(response.status, 400);
  const { error } = await envelopeOf(response);
  assertStringIncludes(error?.message ?? "", "terms have changed");
  assertEquals(deps.jobStore.rows.size, 0);
});

Deno.test("the reference path must be the caller's own references folder", async () => {
  const deps = buildDeps();
  // Another user's reference photo — even with valid consent fields.
  const foreign = await handleGenerate(
    generateRequest(
      VALID_LOOKING_JWT_A,
      generateBody({ reference_image_path: `users/${USER_B_ID}/references/selfie.jpg` }),
    ),
    deps,
  );
  assertEquals(foreign.status, 400);
  await foreign.body?.cancel();
  // The caller's own closet photo is not a consented reference image.
  const closet = await handleGenerate(
    generateRequest(
      VALID_LOOKING_JWT_A,
      generateBody({ reference_image_path: `users/${USER_A_ID}/closet/item.jpg` }),
    ),
    deps,
  );
  assertEquals(closet.status, 400);
  await closet.body?.cancel();
  assertEquals(deps.jobStore.rows.size, 0);
});

Deno.test("a valid generate creates a queued row before returning, identity from the JWT", async () => {
  const deps = buildDeps();
  const response = await handleGenerate(
    generateRequest(
      VALID_LOOKING_JWT_A,
      // An attacker-supplied user_id in the body must be ignored.
      generateBody({ user_id: USER_B_ID }),
    ),
    deps,
  );
  assertEquals(response.status, 202);
  const { data } = await envelopeOf(response);
  assertEquals(data?.["status"], "queued");
  assertEquals(data?.["user_id"], USER_A_ID);
  assertEquals(data?.["provider"], "mock");
  const payload = data?.["prompt_payload"] as Record<string, unknown>;
  // The §11 label is attached at row creation — no window without it.
  assertStringIncludes(
    payload["disclaimer"] as string,
    "visual styling estimate",
  );
  assertStringIncludes(
    payload["prompt"] as string,
    "Dress him in: top: regular navy crewneck sweater",
  );
  // Wire timestamps must be second-precision ISO8601 for Swift's decoder.
  assert(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(data?.["created_at"] as string));
  assertEquals(deps.jobStore.rows.size, 1);
  const stored = [...deps.jobStore.rows.values()][0]!;
  assertEquals(stored.status, "queued");
  assertEquals(stored.userId, USER_A_ID);
});

Deno.test("an outfit that resolves to no garments is a validation error", async () => {
  const deps = buildDeps();
  const response = await handleGenerate(
    generateRequest(
      VALID_LOOKING_JWT_A,
      generateBody({ outfit_id: "99999999-9999-4999-8999-999999999999" }),
    ),
    deps,
  );
  assertEquals(response.status, 400);
  await response.body?.cancel();
});

async function enqueueOne(deps: ReturnType<typeof buildDeps>): Promise<string> {
  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, generateBody()),
    deps,
  );
  const { data } = await envelopeOf(response);
  return data?.["id"] as string;
}

Deno.test("status polling advances queued → generating → complete with a result path", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);

  const first = await handleStatus(statusRequest(VALID_LOOKING_JWT_A, id), deps, id);
  assertEquals(first.status, 200);
  const firstEnvelope = await envelopeOf(first);
  assertEquals(firstEnvelope.data?.["status"], "generating");
  assertEquals(firstEnvelope.data?.["result_image_path"], null);

  const second = await handleStatus(statusRequest(VALID_LOOKING_JWT_A, id), deps, id);
  const secondEnvelope = await envelopeOf(second);
  assertEquals(secondEnvelope.data?.["status"], "complete");
  const resultPath = secondEnvelope.data?.["result_image_path"] as string;
  assertEquals(resultPath, `users/${USER_A_ID}/studio/${id.toLowerCase()}/result.png`);
  // The object genuinely exists — the mock writes a real placeholder.
  assert(deps.storage.objects.has(resultPath));

  // A poll after completion is a cheap read, terminal state is stable.
  const third = await handleStatus(statusRequest(VALID_LOOKING_JWT_A, id), deps, id);
  const thirdEnvelope = await envelopeOf(third);
  assertEquals(thirdEnvelope.data?.["status"], "complete");
});

Deno.test("polling an unowned job returns the same 404 as a missing one", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);

  const unowned = await handleStatus(statusRequest(VALID_LOOKING_JWT_B, id), deps, id);
  assertEquals(unowned.status, 404);
  const unownedEnvelope = await envelopeOf(unowned);

  const missingId = crypto.randomUUID();
  const missing = await handleStatus(
    statusRequest(VALID_LOOKING_JWT_B, missingId),
    deps,
    missingId,
  );
  assertEquals(missing.status, 404);
  const missingEnvelope = await envelopeOf(missing);
  // Identical envelope either way — existence never leaks across users.
  assertEquals(unownedEnvelope.error?.message, missingEnvelope.error?.message);
});

Deno.test("a deleted generation is gone: its status poll is a 404", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  const row = deps.jobStore.rows.get(id)!;
  row.deletedAt = new Date("2026-08-17T09:05:00Z").toISOString();
  deps.jobStore.rows.set(id, row);

  const response = await handleStatus(statusRequest(VALID_LOOKING_JWT_A, id), deps, id);
  assertEquals(response.status, 404);
  await response.body?.cancel();
});

function failingProvider(error: ProviderError): ImageGenerationProvider {
  return {
    submitGeneration() {
      return Promise.reject(error);
    },
    pollStatus() {
      return Promise.reject(error);
    },
  };
}

Deno.test("a retryable provider fault leaves the row queued — never a terminal failure", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  deps.provider = failingProvider(
    new ProviderError("PROVIDER_UNAVAILABLE", true, "vendor 503"),
  );

  const response = await handleStatus(statusRequest(VALID_LOOKING_JWT_A, id), deps, id);
  const { data } = await envelopeOf(response);
  assertEquals(data?.["status"], "queued");
  assertEquals(deps.jobStore.rows.get(id)?.status, "queued");
});

Deno.test("a moderation rejection is terminal, non-accusatory, and never raw provider text", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  deps.provider = failingProvider(
    new ProviderError("CONTENT_MODERATION_REJECTED", false, "policy_violation_face_swap_suspected"),
  );

  const response = await handleStatus(statusRequest(VALID_LOOKING_JWT_A, id), deps, id);
  const { data } = await envelopeOf(response);
  assertEquals(data?.["status"], "failed");
  const message = data?.["error_message"] as string;
  assertStringIncludes(message, "can't be used for a Style Studio preview");
  assert(!message.includes("policy_violation"));
  const payload = data?.["prompt_payload"] as Record<string, unknown>;
  assertEquals(payload["is_retryable_failure"], false);
  // §21: the prompt survives the failure untouched, ready for a retry.
  assertStringIncludes(payload["prompt"] as string, "Dress him in:");
});

Deno.test("retry copies prompt_payload verbatim, keeps the failed row as the audit record", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  const failed = deps.jobStore.rows.get(id)!;
  failed.status = "failed";
  failed.errorMessage = "That took longer than expected. Try again?";
  failed.promptPayload["provider_job_id"] = "stale-job";
  failed.promptPayload["is_retryable_failure"] = true;
  deps.jobStore.rows.set(id, failed);

  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, { retry_of: id }),
    deps,
  );
  assertEquals(response.status, 202);
  const { data } = await envelopeOf(response);
  const retryId = data?.["id"] as string;
  assert(retryId !== id);
  assertEquals(data?.["status"], "queued");
  const retryPayload = data?.["prompt_payload"] as Record<string, unknown>;
  // Verbatim prompt (the user reconfigures nothing), minus job-instance state.
  assertEquals(retryPayload["prompt"], failed.promptPayload["prompt"]);
  assertEquals(retryPayload["provider_job_id"], undefined);
  assertEquals(retryPayload["is_retryable_failure"], undefined);
  assertEquals(deps.jobStore.rows.get(id)?.status, "failed");
  assertEquals(deps.jobStore.rows.size, 2);
});

Deno.test("retry of a non-failed generation is refused", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, { retry_of: id }),
    deps,
  );
  assertEquals(response.status, 400);
  const { error } = await envelopeOf(response);
  assertStringIncludes(error?.message ?? "", "Only a failed generation");
});

Deno.test("retry re-runs the consent-staleness check against the stored attestation", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  const failed = deps.jobStore.rows.get(id)!;
  failed.status = "failed";
  (failed.promptPayload["consent"] as Record<string, unknown>)["terms_version"] = "2020-01-01";
  deps.jobStore.rows.set(id, failed);

  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, { retry_of: id }),
    deps,
  );
  assertEquals(response.status, 400);
  const { error } = await envelopeOf(response);
  assertStringIncludes(error?.message ?? "", "terms have changed");
});

Deno.test("advanceGeneration is a no-op on terminal rows", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  const row = deps.jobStore.rows.get(id)!;
  row.status = "complete";
  row.resultImagePath = "users/x/studio/y/result.png";
  const logger = {
    info() {},
    warn() {},
    error() {},
    adoptRequestId() {},
  };
  const advanced = await advanceGeneration(row, deps, "req-1", logger);
  assertEquals(advanced, row);
});
