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
  handleHiResExport,
  handleStatus,
  type StudioGenerationRow,
  type StudioHandlerDeps,
  type StudioJobStore,
} from "./handler.ts";
import { CURRENT_STUDIO_CONSENT_TERMS_VERSION } from "./schema.ts";
import { createLogger } from "../_shared/logger.ts";

Deno.test("concurrent status polls submit a queued job once", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  const row = deps.jobStore.rows.get(id);
  assert(row);
  let submitted = 0;
  let unblock: (() => void) | undefined;
  let signalStarted: (() => void) | undefined;
  const blocked = new Promise<void>((resolve) => {
    unblock = resolve;
  });
  const started = new Promise<void>((resolve) => {
    signalStarted = resolve;
  });
  const originalProvider = deps.provider;
  deps.provider = {
    async submitGeneration() {
      submitted += 1;
      signalStarted?.();
      await blocked;
      return { providerJobId: "one-provider-job" };
    },
    pollStatus: (id, ctx) => originalProvider.pollStatus(id, ctx),
  };
  const first = advanceGeneration(
    row,
    deps,
    "concurrency-first",
    createLogger("concurrency-first"),
  );
  await started;
  const second = await advanceGeneration(
    row,
    deps,
    "concurrency-second",
    createLogger("concurrency-second"),
  );
  assertEquals(second.status, "queued");
  assertEquals(submitted, 1);
  unblock?.();
  assertEquals((await first).status, "generating");
  assertEquals(submitted, 1);
});

Deno.test("duplicate retry requests return the same queued job", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  const row = deps.jobStore.rows.get(id);
  assert(row);
  row.status = "failed";
  row.promptPayload["is_retryable_failure"] = true;
  deps.jobStore.rows.set(id, row);
  const responses = await Promise.all(
    [0, 1].map(() => handleGenerate(generateRequest(VALID_LOOKING_JWT_A, { retry_of: id }), deps)),
  );
  assertEquals(responses.map((response) => response.status), [202, 202]);
  const envelopes = await Promise.all(responses.map(envelopeOf));
  assert(envelopes[0] && envelopes[1]);
  assertEquals(envelopes[0].data?.["id"], envelopes[1].data?.["id"]);
  assertEquals(deps.jobStore.rows.size, 2);
});

Deno.test("Premium hi-res export copies source context, queues once, and uses current photo consent", async () => {
  const deps = buildDeps();
  deps.hasActivePremiumSubscription = () => Promise.resolve(true);
  deps.providerName = "openai";
  const sourceID = await enqueueOne(deps);
  const source = deps.jobStore.rows.get(sourceID)!;
  source.status = "complete";
  source.resultImagePath = `users/${USER_A_ID}/studio/${sourceID}/result.png`;
  source.promptPayload["prompt"] = "exact stored prompt";
  source.promptPayload["garments"] = FIXTURE_GARMENTS;
  deps.jobStore.rows.set(sourceID, source);

  const consent = {
    acknowledged: true,
    terms_version: CURRENT_STUDIO_CONSENT_TERMS_VERSION,
  };
  const first = await handleHiResExport(
    hiResRequest(VALID_LOOKING_JWT_A, { source_generation_id: sourceID, consent }),
    deps,
  );
  assertEquals(first.status, 202);
  const firstData = (await envelopeOf(first)).data!;
  const child = deps.jobStore.rows.get(firstData["id"] as string)!;
  assertEquals(child.status, "queued");
  assertEquals(child.referenceImagePath, source.referenceImagePath);
  assertEquals(child.promptPayload["prompt"], "exact stored prompt");
  assertEquals(child.promptPayload["garments"], FIXTURE_GARMENTS);
  assertEquals(child.promptPayload["resolution"], "hi_res");
  assertEquals(
    (child.promptPayload["hi_res_export_consent"] as Record<string, unknown>)["terms_version"],
    CURRENT_STUDIO_CONSENT_TERMS_VERSION,
  );
  assertEquals(source.promptPayload["resolution"], "draft");

  let submittedResolution: string | undefined;
  const provider = deps.provider;
  deps.provider = {
    async submitGeneration(request, ctx) {
      submittedResolution = request.resolution;
      return await provider.submitGeneration(request, ctx);
    },
    pollStatus: (id, ctx) => provider.pollStatus(id, ctx),
  };
  const firstPoll = await handleStatus(
    statusRequest(VALID_LOOKING_JWT_A, child.id),
    deps,
    child.id,
  );
  assertEquals(firstPoll.status, 200);
  assertEquals(submittedResolution, "hi_res");

  const replay = await handleHiResExport(
    hiResRequest(VALID_LOOKING_JWT_A, { source_generation_id: sourceID, consent }),
    deps,
  );
  assertEquals((await envelopeOf(replay)).data?.["id"], child.id);
  assertEquals(deps.jobStore.rows.size, 2);
});

Deno.test("hi-res export of a flat-lay edit does not request identity-photo consent", async () => {
  const deps = buildDeps();
  deps.hasActivePremiumSubscription = () => Promise.resolve(true);
  deps.providerName = "openai";
  const sourceID = await enqueueOne(deps);
  const source = deps.jobStore.rows.get(sourceID)!;
  source.status = "complete";
  source.promptPayload["mode"] = "inspiration";
  source.resultImagePath = `users/${USER_A_ID}/studio/${sourceID}/result.png`;
  // This is a prior Studio result used for an edit, not a user's identity photo.
  source.referenceImagePath = source.resultImagePath;
  deps.jobStore.rows.set(sourceID, source);
  const response = await handleHiResExport(
    hiResRequest(VALID_LOOKING_JWT_A, { source_generation_id: sourceID }),
    deps,
  );
  assertEquals(response.status, 202);
  const created = deps.jobStore.rows.get(((await envelopeOf(response)).data?.["id"]) as string)!;
  assertEquals(created.referenceImagePath, source.resultImagePath);
  assertEquals(created.promptPayload["hi_res_export_consent"], undefined);
});

Deno.test("hi-res export rejects peer, incomplete, deleted, and expired sources before enqueue", async () => {
  const deps = buildDeps();
  deps.hasActivePremiumSubscription = () => Promise.resolve(true);
  const sourceID = await enqueueOne(deps);
  const source = deps.jobStore.rows.get(sourceID)!;
  source.status = "complete";
  source.resultImagePath = `users/${USER_A_ID}/studio/${sourceID}/result.png`;

  const peer = await handleHiResExport(
    hiResRequest(VALID_LOOKING_JWT_B, { source_generation_id: sourceID }),
    deps,
  );
  assertEquals(peer.status, 404);
  source.status = "generating";
  deps.jobStore.rows.set(sourceID, source);
  const incomplete = await handleHiResExport(
    hiResRequest(VALID_LOOKING_JWT_A, { source_generation_id: sourceID }),
    deps,
  );
  assertEquals(incomplete.status, 404);
  source.status = "complete";
  source.deletedAt = "2026-08-17T08:00:00Z";
  deps.jobStore.rows.set(sourceID, source);
  const deleted = await handleHiResExport(
    hiResRequest(VALID_LOOKING_JWT_A, { source_generation_id: sourceID }),
    deps,
  );
  assertEquals(deleted.status, 404);
  source.deletedAt = null;
  source.retentionExpiresAt = "2026-08-17T08:59:59Z";
  deps.jobStore.rows.set(sourceID, source);
  const expired = await handleHiResExport(
    hiResRequest(VALID_LOOKING_JWT_A, { source_generation_id: sourceID }),
    deps,
  );
  assertEquals(expired.status, 404);
  assertEquals(deps.jobStore.rows.size, 1);
});

Deno.test("non-retryable provider failures cannot bypass quota via retry", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  const row = deps.jobStore.rows.get(id);
  assert(row);
  row.status = "failed";
  row.promptPayload["is_retryable_failure"] = false;
  deps.jobStore.rows.set(id, row);
  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, { retry_of: id }),
    deps,
  );
  assertEquals(response.status, 400);
  assertEquals(deps.jobStore.rows.size, 1);
  await response.body?.cancel();
});

Deno.test("hi-res retry validates the fresh export consent instead of the source draft receipt", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  const row = deps.jobStore.rows.get(id)!;
  row.status = "failed";
  row.promptPayload["resolution"] = "hi_res";
  row.promptPayload["is_retryable_failure"] = true;
  row.promptPayload["consent"] = { acknowledged: true, terms_version: "2020-01-01" };
  row.promptPayload["hi_res_export_consent"] = {
    acknowledged: true,
    terms_version: CURRENT_STUDIO_CONSENT_TERMS_VERSION,
  };
  deps.jobStore.rows.set(id, row);

  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, { retry_of: id }),
    deps,
  );
  assertEquals(response.status, 202);
  const retryID = (await envelopeOf(response)).data?.["id"] as string;
  assertEquals(deps.jobStore.rows.get(retryID)?.promptPayload["resolution"], "hi_res");
});

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
  const claims = new Map<string, string>();
  const retries = new Map<string, string>();
  const nowIso = () => new Date("2026-08-17T09:00:00Z").toISOString();
  return {
    rows,
    enqueueHiResExport(userId, sourceGenerationId, consent, provider) {
      const source = rows.get(sourceGenerationId);
      if (!source || source.userId !== userId) throw new Error("source unavailable");
      const existing = [...rows.values()].find((candidate) =>
        candidate.promptPayload["hi_res_source_generation_id"] === sourceGenerationId
      );
      if (existing) return Promise.resolve(structuredClone(existing));
      const promptPayload = {
        ...structuredClone(source.promptPayload),
        resolution: "hi_res",
        hi_res_source_generation_id: sourceGenerationId,
        ...(source.referenceImagePath.length > 0 &&
            source.promptPayload["mode"] !== "inspiration" &&
            source.promptPayload["mode"] !== "closet_inspiration"
          ? {
            hi_res_export_consent: {
              acknowledged: consent.acknowledged,
              terms_version: consent.termsVersion,
              attested_at: nowIso(),
            },
          }
          : {}),
      };
      const child: StudioGenerationRow = {
        id: crypto.randomUUID(),
        userId,
        referenceImagePath: source.referenceImagePath,
        outfitId: source.outfitId,
        promptPayload,
        status: "queued",
        resultImagePath: null,
        provider,
        errorMessage: null,
        deletedAt: null,
        createdAt: nowIso(),
        updatedAt: nowIso(),
      };
      rows.set(child.id, structuredClone(child));
      return Promise.resolve(structuredClone(child));
    },
    insert(row) {
      if (row.retryOf) {
        const existingID = retries.get(row.retryOf);
        const existing = existingID ? rows.get(existingID) : undefined;
        if (existing) return Promise.resolve(structuredClone(existing));
      }
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
      if (row.retryOf) retries.set(row.retryOf, stored.id);
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
    countForUser(userId) {
      let n = 0;
      for (const row of rows.values()) {
        if (row.userId === userId && row.deletedAt === null) n += 1;
      }
      return Promise.resolve(n);
    },
    claim(userId, id) {
      const row = rows.get(id);
      if (
        !row || row.userId !== userId || claims.has(id) || row.deletedAt !== null ||
        !["queued", "generating"].includes(row.status)
      ) return Promise.resolve(null);
      const token = crypto.randomUUID();
      claims.set(id, token);
      return Promise.resolve({ row: structuredClone(row), token });
    },
    release(_userId, id, token) {
      if (claims.get(id) === token) claims.delete(id);
      return Promise.resolve();
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
    hasActivePremiumSubscription: () => Promise.resolve(false),
    freeStudioTrialGenerations: 1,
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

function hiResRequest(jwt: string | null, body: unknown, method = "POST"): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (jwt) headers["Authorization"] = `Bearer ${jwt}`;
  return new Request("http://localhost/studio/export-hi-res", {
    method,
    headers,
    body: method === "POST" ? JSON.stringify({ body }) : undefined,
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

Deno.test("Studio generation and status limits return exact Retry-After resets", async () => {
  const generateDeps = buildDeps();
  generateDeps.generateRateLimiter = {
    check: () => ({ allowed: false, remaining: 0, retryAfterSeconds: 23 }),
  };
  const generate = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, generateBody()),
    generateDeps,
  );
  assertEquals(generate.status, 429);
  assertEquals(generate.headers.get("Retry-After"), "23");

  const statusDeps = buildDeps();
  statusDeps.statusRateLimiter = {
    check: () => ({ allowed: false, remaining: 0, retryAfterSeconds: 29 }),
  };
  const status = await handleStatus(
    statusRequest(VALID_LOOKING_JWT_A, OUTFIT_ID),
    statusDeps,
    OUTFIT_ID,
  );
  assertEquals(status.status, 429);
  assertEquals(status.headers.get("Retry-After"), "29");

  const exportDeps = buildDeps();
  exportDeps.generateRateLimiter = {
    check: () => ({ allowed: false, remaining: 0, retryAfterSeconds: 31 }),
  };
  const exportResponse = await handleHiResExport(
    hiResRequest(VALID_LOOKING_JWT_A, { source_generation_id: OUTFIT_ID }),
    exportDeps,
  );
  assertEquals(exportResponse.status, 429);
  assertEquals(exportResponse.headers.get("Retry-After"), "31");
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
  failed.promptPayload["is_retryable_failure"] = true;
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

Deno.test("a second generate without premium is 429 with upgrade copy", async () => {
  const deps = buildDeps();
  const first = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, generateBody()),
    deps,
  );
  assertEquals(first.status, 202);
  await first.body?.cancel();
  const second = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, generateBody()),
    deps,
  );
  assertEquals(second.status, 429);
  const { error } = await envelopeOf(second);
  assertEquals(error?.category, "rate_limited");
  assertStringIncludes(error?.message ?? "", "free visual estimate");
  assertEquals(deps.jobStore.rows.size, 1);
});

Deno.test("premium skips the studio trial quota", async () => {
  const deps = buildDeps();
  deps.hasActivePremiumSubscription = () => Promise.resolve(true);
  const first = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, generateBody()),
    deps,
  );
  assertEquals(first.status, 202);
  await first.body?.cancel();
  const second = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, generateBody()),
    deps,
  );
  assertEquals(second.status, 202);
  await second.body?.cancel();
  assertEquals(deps.jobStore.rows.size, 2);
});

Deno.test("retry of a failed trial job is not a second trial", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  const failed = deps.jobStore.rows.get(id)!;
  failed.status = "failed";
  failed.promptPayload["is_retryable_failure"] = true;
  deps.jobStore.rows.set(id, failed);
  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, { retry_of: id }),
    deps,
  );
  assertEquals(response.status, 202);
  await response.body?.cancel();
});

Deno.test("controlled live-provider failure retries the same trial to completion without a new quota check", async () => {
  const deps = buildDeps();
  let quotaChecks = 0;
  const countForUser = deps.jobStore.countForUser;
  deps.jobStore.countForUser = (userId) => {
    quotaChecks += 1;
    return countForUser(userId);
  };
  let submissions = 0;
  let originalPolls = 0;
  deps.provider = {
    submitGeneration(_request) {
      submissions += 1;
      return Promise.resolve({ providerJobId: `controlled-job-${submissions}` });
    },
    pollStatus(providerJobId) {
      if (providerJobId === "controlled-job-2") {
        return Promise.resolve({
          status: "complete",
          resultStoragePath: "users/synthetic/studio/retry/result.png",
          providerJobId,
          errorMessage: null,
          isRetryableFailure: false,
        });
      }
      originalPolls += 1;
      return Promise.resolve({
        status: "failed",
        resultStoragePath: null,
        providerJobId,
        errorMessage: "controlled transient provider failure",
        isRetryableFailure: true,
      });
    },
  };

  const accepted = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, { mode: "inspiration" }),
    deps,
  );
  const sourceID = (await envelopeOf(accepted)).data?.["id"] as string;
  assertEquals(accepted.status, 202);
  assertEquals(quotaChecks, 1);
  const started = await handleStatus(statusRequest(VALID_LOOKING_JWT_A, sourceID), deps, sourceID);
  assertEquals((await envelopeOf(started)).data?.["status"], "generating");
  const failed = await handleStatus(statusRequest(VALID_LOOKING_JWT_A, sourceID), deps, sourceID);
  assertEquals((await envelopeOf(failed)).data?.["status"], "failed");
  assertEquals(deps.jobStore.rows.get(sourceID)?.promptPayload["is_retryable_failure"], true);
  assertEquals(originalPolls, 1);

  const retryResponse = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, { retry_of: sourceID }),
    deps,
  );
  assertEquals(retryResponse.status, 202);
  const retryID = (await envelopeOf(retryResponse)).data?.["id"] as string;
  assertEquals(quotaChecks, 1, "retry must not consume or re-check the one-trial allowance");
  assertEquals(deps.jobStore.rows.get(sourceID)?.status, "failed");

  const retryStarted = await handleStatus(
    statusRequest(VALID_LOOKING_JWT_A, retryID),
    deps,
    retryID,
  );
  assertEquals((await envelopeOf(retryStarted)).data?.["status"], "generating");
  const retried = await handleStatus(statusRequest(VALID_LOOKING_JWT_A, retryID), deps, retryID);
  const retriedData = (await envelopeOf(retried)).data;
  assertEquals(retriedData?.["status"], "complete");
  assertEquals(deps.jobStore.rows.size, 2);
});

Deno.test("inspiration enqueues without selfie and carries weather and edit context", async () => {
  const deps = buildDeps();
  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, {
      mode: "inspiration",
      context: "Rain; calendar: formal; quiz: relaxed fit",
      instructions: "Date night",
    }),
    deps,
  );
  assertEquals(response.status, 202);
  const row = [...deps.jobStore.rows.values()][0];
  assert(row);
  assertEquals(row.referenceImagePath, "");
  assertEquals(row.promptPayload["mode"], "inspiration");
  assertStringIncludes(row.promptPayload["prompt"] as string, "Date night");
  assertStringIncludes(row.promptPayload["prompt"] as string, "Rain");
});
Deno.test("closet inspiration rejects partly unresolved selection", async () => {
  const deps = buildDeps();
  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, {
      mode: "closet_inspiration",
      ad_hoc_item_ids: [OUTFIT_ID, USER_B_ID],
    }),
    deps,
  );
  assertEquals(response.status, 400);
  assertEquals(deps.jobStore.rows.size, 0);
});
Deno.test("inspiration edit refuses someone else's source", async () => {
  const deps = buildDeps();
  const id = await enqueueOne(deps);
  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_B, { mode: "inspiration", source_generation_id: id }),
    deps,
  );
  assertEquals(response.status, 400);
  assertEquals(deps.jobStore.rows.size, 1);
});

Deno.test("inspiration edit resolves owned image server-side and retry does not require selfie consent", async () => {
  const deps = buildDeps();
  deps.hasActivePremiumSubscription = () => Promise.resolve(true);
  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, { mode: "inspiration" }),
    deps,
  );
  assertEquals(response.status, 202);
  const original = [...deps.jobStore.rows.values()][0];
  assert(original);
  await deps.jobStore.update(USER_A_ID, original.id, {
    status: "complete",
    resultImagePath: `users/${USER_A_ID}/studio/${original.id}/result.png`,
  });
  const edited = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, {
      mode: "inspiration",
      source_generation_id: original.id,
      instructions: "More casual",
    }),
    deps,
  );
  assertEquals(edited.status, 202);
  const rows = [...deps.jobStore.rows.values()];
  const edit = rows[1];
  assert(edit);
  assertEquals(edit.referenceImagePath, `users/${USER_A_ID}/studio/${original.id}/result.png`);
  await deps.jobStore.update(USER_A_ID, edit.id, {
    status: "failed",
    promptPayload: { ...edit.promptPayload, is_retryable_failure: true },
  });
  const retry = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, { retry_of: edit.id }),
    deps,
  );
  assertEquals(retry.status, 202);
});

Deno.test("inspiration cannot edit a personal reference Studio result", async () => {
  const deps = buildDeps();
  deps.hasActivePremiumSubscription = () => Promise.resolve(true);
  const id = await enqueueOne(deps);
  await deps.jobStore.update(USER_A_ID, id, {
    status: "complete",
    resultImagePath: `users/${USER_A_ID}/studio/${id}/result.png`,
  });
  const response = await handleGenerate(
    generateRequest(VALID_LOOKING_JWT_A, { mode: "inspiration", source_generation_id: id }),
    deps,
  );
  assertEquals(response.status, 400);
  assertEquals(deps.jobStore.rows.size, 1);
});

Deno.test("initial submission replay returns the same job after the free allowance is used", async () => {
  const deps = buildDeps();
  const key = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  let originalHash: string | undefined;
  const insert = deps.jobStore.insert.bind(deps.jobStore);
  deps.jobStore.insert = (row) => {
    assertEquals(row.requestKey, key);
    originalHash = row.requestHash;
    assertEquals(originalHash?.length, 64);
    return insert(row);
  };
  deps.jobStore.findSubmission = (user, requestedKey, hash) => {
    assertEquals(user, USER_A_ID);
    assertEquals(requestedKey, key);
    if (originalHash) assertEquals(hash, originalHash);
    return Promise.resolve([...deps.jobStore.rows.values()][0] ?? null);
  };
  const request = () => {
    const req = generateRequest(VALID_LOOKING_JWT_A, generateBody());
    req.headers.set("Idempotency-Key", key);
    return req;
  };
  const first = await handleGenerate(request(), deps);
  const replay = await handleGenerate(request(), deps);
  assertEquals(first.status, 202);
  assertEquals(replay.status, 202);
  assertEquals((await first.json()).data.id, (await replay.json()).data.id);
  assertEquals(deps.jobStore.rows.size, 1);
});
