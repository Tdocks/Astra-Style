import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { AppError } from "../_shared/errors.ts";
import { supabaseJobStore } from "./jobStore.ts";

function fakeClient(errorMessage?: string, retentionExpiry: string | null = null) {
  const calls: Array<[string, ...unknown[]]> = [];
  const result = {
    data: {
      id: "job",
      user_id: "owner",
      status: "queued",
      created_at: "now",
      updated_at: "now",
      retention_expires_at: retentionExpiry,
    },
    error: errorMessage ? { message: errorMessage } : null,
    count: 1,
  };
  const builder = {
    select(...args: unknown[]) {
      calls.push(["select", ...args]);
      return builder;
    },
    eq(...args: unknown[]) {
      calls.push(["eq", ...args]);
      return builder;
    },
    is(...args: unknown[]) {
      calls.push(["is", ...args]);
      return builder;
    },
    update(...args: unknown[]) {
      calls.push(["update", ...args]);
      return builder;
    },
    single() {
      return Promise.resolve(result);
    },
    maybeSingle() {
      return Promise.resolve(result);
    },
    then(resolve: (value: typeof result) => unknown) {
      return Promise.resolve(result).then(resolve);
    },
  };
  const client = {
    from(table: string) {
      calls.push(["from", table]);
      return builder;
    },
    rpc(name: string, params: unknown) {
      calls.push(["rpc", name, params]);
      return builder;
    },
  } as unknown as SupabaseClient;
  return { calls, store: supabaseJobStore(client) };
}

Deno.test("privileged reads always fence owner and generation ID", async () => {
  const { calls, store } = fakeClient();
  await store.get("owner", "job");
  assertEquals(calls.filter((call) => call[0] === "eq"), [["eq", "user_id", "owner"], [
    "eq",
    "id",
    "job",
  ]]);
});

Deno.test("job reads preserve unsaved expiry and permanent-save null", async () => {
  for (const expiry of [null, "2026-11-08T21:00:00.000Z"]) {
    const { store } = fakeClient(undefined, expiry);
    assertEquals((await store.get("owner", "job"))?.retentionExpiresAt, expiry);
  }
});

Deno.test("job updates and lease releases require owner, ID and claim token", async () => {
  for (const action of ["update", "release"]) {
    const { calls, store } = fakeClient();
    if (action === "update") await store.update("owner", "job", { status: "complete" }, "lease");
    else await store.release("owner", "job", "lease");
    assertEquals(calls.filter((call) => call[0] === "eq"), [["eq", "user_id", "owner"], [
      "eq",
      "id",
      "job",
    ], ["eq", "claim_token", "lease"]]);
  }
  const { store } = fakeClient();
  await assertRejects(() => store.update("owner", "job", { status: "complete" }), AppError);
});

Deno.test("allowance check reads durable owner records, excluding released reservations", async () => {
  const { calls, store } = fakeClient();
  assertEquals(await store.countForUser("owner"), 1);
  assertEquals(calls[0], ["from", "studio_allowances"]);
  assertEquals(calls.filter((call) => call[0] === "eq" || call[0] === "is"), [[
    "eq",
    "user_id",
    "owner",
  ], ["is", "released_at", null]]);
});

Deno.test("enqueue delegates ownership, payload and retry identity to the atomic RPC", async () => {
  const { calls, store } = fakeClient();
  await store.insert({
    userId: "owner",
    referenceImagePath: "",
    outfitId: null,
    promptPayload: {},
    provider: "mock",
    retryOf: "parent",
  });
  assertEquals(calls[0], ["rpc", "enqueue_studio_generation", {
    p_user_id: "owner",
    p_reference_image_path: "",
    p_outfit_id: null,
    p_prompt_payload: {},
    p_provider: "mock",
    p_retry_of: "parent",
  }]);
});

Deno.test("hi-res export delegates source, consent, Premium and reservation checks to its atomic RPC", async () => {
  const { calls, store } = fakeClient();
  const row = await store.enqueueHiResExport(
    "owner",
    "source-generation",
    { acknowledged: true, termsVersion: "2026-08-17" },
    "openai",
  );
  assertEquals(row.id, "job");
  assertEquals(calls[0], ["rpc", "enqueue_studio_hi_res_export", {
    p_user_id: "owner",
    p_source_generation_id: "source-generation",
    p_provider: "openai",
    p_consent_acknowledged: true,
    p_consent_terms_version: "2026-08-17",
  }]);
});

Deno.test("hi-res RPC errors map Premium, provider, consent and unavailable source safely", async () => {
  const cases = [
    ["studio_hi_res_premium_required", 403],
    ["studio_hi_res_provider_unavailable", 503],
    ["studio_export_consent_required", 400],
    ["studio_export_source_unavailable", 404],
    ["studio_export_already_removed", 409],
  ] as const;
  for (const [rpcError, expectedStatus] of cases) {
    const { store } = fakeClient(rpcError);
    const error = await assertRejects(
      () =>
        store.enqueueHiResExport(
          "owner",
          "source-generation",
          { acknowledged: false, termsVersion: "" },
          "mock",
        ),
      AppError,
    );
    assertEquals(error.status, expectedStatus);
    assertEquals(error.message.includes(rpcError), false);
  }
});

Deno.test("database allowance rejection maps to a safe 429 without leaking SQL", async () => {
  const { store } = fakeClient("studio_trial_exhausted");
  const error = await assertRejects(
    () =>
      store.insert({
        userId: "owner",
        referenceImagePath: "",
        outfitId: null,
        promptPayload: {},
        provider: "mock",
      }),
    AppError,
  );
  assertEquals(error.status, 429);
  assertEquals(error.message.includes("studio_trial_exhausted"), false);
});
