/**
 * Bounded hosted acceptance for P6-TEST-01's successful live Studio path.
 *
 * Run from `supabase/functions` with `SUPABASE_URL` and `SUPABASE_ANON_KEY`
 * supplied by the operator's protected environment. This creates an
 * anonymous synthetic account, requests one no-selfie inspiration flat lay,
 * observes queued -> generating -> complete, downloads the private PNG, and
 * requests normal account deletion even when an assertion fails. It never
 * prints credentials, endpoint URLs, storage paths, prompts, or image bytes.
 *
 * The failure/retry branch is deliberately a local injected-provider test in
 * handler_test.ts: a hosted failure must not be manufactured by changing the
 * global provider configuration or risking another user's request.
 */

import { createClient } from "@supabase/supabase-js";

const POLL_INTERVAL_MS = 4_000;
const TOTAL_TIMEOUT_MS = 180_000;
const PNG_SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10];

interface Envelope<T> {
  readonly data?: T;
  readonly error?: { readonly category?: string; readonly message?: string } | null;
}

interface Generation {
  readonly id: string;
  readonly status: "queued" | "generating" | "complete" | "failed";
  readonly result_image_path: string | null;
  readonly provider: string | null;
  readonly prompt_payload?: Readonly<Record<string, unknown>>;
}

interface Quota {
  readonly limit: number;
  readonly remaining: number;
  readonly used: number;
}

interface AuthUserReader {
  readonly auth: {
    getUser(accessToken: string): Promise<{
      readonly data: { readonly user: unknown | null };
      readonly error: unknown | null;
    }>;
  };
}

function requireEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Required protected environment value is missing: ${name}`);
  return value;
}

async function sleep(milliseconds: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function callStudio<T>(
  baseURL: string,
  anonKey: string,
  accessToken: string,
  path: string,
  init: RequestInit,
): Promise<T> {
  const response = await fetch(`${baseURL}/functions/v1/studio/${path}`, {
    ...init,
    headers: {
      apikey: anonKey,
      authorization: `Bearer ${accessToken}`,
      "content-type": "application/json",
      "x-request-id": crypto.randomUUID(),
      ...init.headers,
    },
    signal: AbortSignal.timeout(100_000),
  });
  const envelope = await response.json() as Envelope<T>;
  if (!response.ok || envelope.error || !envelope.data) {
    throw new Error(`Studio request failed with HTTP ${response.status}.`);
  }
  return envelope.data;
}

async function deleteSyntheticAccount(
  baseURL: string,
  anonKey: string,
  accessToken: string,
): Promise<void> {
  const response = await fetch(`${baseURL}/functions/v1/account`, {
    method: "DELETE",
    headers: {
      apikey: anonKey,
      authorization: `Bearer ${accessToken}`,
      "x-request-id": crypto.randomUUID(),
    },
    signal: AbortSignal.timeout(30_000),
  });
  if (response.status !== 200 && response.status !== 202) {
    await response.body?.cancel();
    throw new Error(`Synthetic-account cleanup was not accepted (HTTP ${response.status}).`);
  }
  await response.body?.cancel();
}

async function waitForDeletedIdentity(
  client: AuthUserReader,
  accessToken: string,
): Promise<void> {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const { data, error } = await client.auth.getUser(accessToken);
    if (error || !data.user) return;
    await sleep(1_000);
  }
  throw new Error(
    "The account deletion request was accepted, but Auth still recognizes the synthetic account.",
  );
}

function assertRealPNG(bytes: Uint8Array, contentType: string): void {
  if (contentType !== "image/png" || bytes.byteLength < 50_000) {
    throw new Error("The live provider did not return a substantial PNG image.");
  }
  if (!PNG_SIGNATURE.every((byte, index) => bytes[index] === byte)) {
    throw new Error("The generated object is not a PNG image.");
  }
  const width = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(16);
  const height = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(20);
  if (width < 512 || height < 512) {
    throw new Error("The generated PNG dimensions are below the live-image acceptance threshold.");
  }
}

export async function runHostedStudioAcceptance(): Promise<void> {
  const baseURL = requireEnvironment("SUPABASE_URL").replace(/\/$/, "");
  const anonKey = requireEnvironment("SUPABASE_ANON_KEY");
  const client = createClient(baseURL, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  let accessToken: string | undefined;
  let generationID: string | undefined;
  let completed = false;
  let cleaned = false;
  let stage = "anonymous auth";

  try {
    const { data: auth, error: authError } = await client.auth.signInAnonymously();
    if (authError || !auth.session) {
      throw new Error("Could not create a synthetic anonymous owner.");
    }
    accessToken = auth.session.access_token;

    const startingQuota = await callStudio<Quota>(
      baseURL,
      anonKey,
      accessToken,
      "quota",
      { method: "GET" },
    );
    if (startingQuota.remaining < 1) {
      throw new Error("The fresh synthetic account did not have its expected trial allowance.");
    }

    stage = "generation enqueue";
    const accepted = await callStudio<Generation>(baseURL, anonKey, accessToken, "generate", {
      method: "POST",
      headers: { "idempotency-key": crypto.randomUUID() },
      body: JSON.stringify({
        request_id: crypto.randomUUID(),
        client_version: "P6-TEST-01-hosted-acceptance",
        body: {
          mode: "inspiration",
          context:
            "Synthetic style profile: smart casual, navy and olive palette, cool autumn weather.",
          instructions:
            "A relaxed weekday outfit with practical layers; show the full coordinated flat lay.",
          preset: "smart_casual",
          background: "neutral",
          pose: "standing_front",
          formality: "balanced",
          season: "fall",
          color_palette: ["navy", "olive", "warm neutral"],
          consent: { acknowledged: false, terms_version: "" },
        },
      }),
    });
    generationID = accepted.id;
    if (accepted.status !== "queued" || accepted.provider !== "openai") {
      throw new Error("The hosted request was not queued on the configured live provider.");
    }

    const observed = new Set<Generation["status"]>([accepted.status]);
    let activeID = accepted.id;
    let deadline = Date.now() + TOTAL_TIMEOUT_MS;
    let result = accepted;
    while (result.status !== "complete" && result.status !== "failed" && Date.now() < deadline) {
      await sleep(POLL_INTERVAL_MS);
      stage = "provider polling";
      result = await callStudio<Generation>(
        baseURL,
        anonKey,
        accessToken,
        `status/${activeID}`,
        {
          method: "GET",
        },
      );
      observed.add(result.status);
    }
    if (
      result.status === "failed" &&
      result.prompt_payload?.["is_retryable_failure"] === true
    ) {
      const failedQuota = await callStudio<Quota>(baseURL, anonKey, accessToken, "quota", {
        method: "GET",
      });
      if (failedQuota.used !== startingQuota.used) {
        throw new Error("A retryable provider failure changed the synthetic account's allowance.");
      }
      stage = "retryable provider failure retry";
      const retry = await callStudio<Generation>(baseURL, anonKey, accessToken, "generate", {
        method: "POST",
        body: JSON.stringify({
          request_id: crypto.randomUUID(),
          client_version: "P6-TEST-01-hosted-acceptance-retry",
          body: { retry_of: accepted.id },
        }),
      });
      if (retry.status !== "queued" || retry.provider !== "openai") {
        throw new Error("The retryable failed job did not reuse its original allowance.");
      }
      activeID = retry.id;
      observed.add(retry.status);
      deadline = Date.now() + TOTAL_TIMEOUT_MS;
      result = retry;
      while (result.status !== "complete" && result.status !== "failed" && Date.now() < deadline) {
        await sleep(POLL_INTERVAL_MS);
        stage = "provider retry polling";
        result = await callStudio<Generation>(
          baseURL,
          anonKey,
          accessToken,
          `status/${activeID}`,
          { method: "GET" },
        );
        observed.add(result.status);
      }
    }
    if (result.status !== "complete" || !result.result_image_path) {
      throw new Error(
        `Live generation did not complete before the bounded deadline (state=${result.status}).`,
      );
    }
    generationID = activeID;
    if (!observed.has("generating")) {
      throw new Error("The live job did not expose the generating state during polling.");
    }
    if (result.provider !== "openai") {
      throw new Error("The completed result did not identify the configured live provider.");
    }
    const finalQuota = await callStudio<Quota>(baseURL, anonKey, accessToken, "quota", {
      method: "GET",
    });
    if (finalQuota.used !== startingQuota.used + 1) {
      throw new Error("Successful rendering did not consume exactly one trial allowance.");
    }

    stage = "private image retrieval";
    const { data: image, error: imageError } = await client.storage
      .from("user-content")
      .download(result.result_image_path);
    if (imageError || !image) {
      throw new Error("Could not retrieve the owner's private Studio result.");
    }
    const bytes = new Uint8Array(await image.arrayBuffer());
    assertRealPNG(bytes, image.type);
    const outputPath = Deno.env.get("ASTRA_STUDIO_ACCEPTANCE_IMAGE")?.trim();
    if (!outputPath) {
      throw new Error("Set ASTRA_STUDIO_ACCEPTANCE_IMAGE to a protected temporary file path.");
    }
    stage = "protected image write";
    await Deno.writeFile(outputPath, bytes, { createNew: true, mode: 0o600 });
    completed = true;
  } catch (error) {
    console.error(
      `Hosted Studio acceptance failed during ${stage}: ${
        error instanceof Error ? error.message : "unknown error"
      }`,
    );
    throw error;
  } finally {
    if (accessToken) {
      try {
        stage = "synthetic account cleanup";
        await deleteSyntheticAccount(baseURL, anonKey, accessToken);
        stage = "account deletion confirmation";
        await waitForDeletedIdentity(client, accessToken);
        cleaned = true;
      } finally {
        await client.auth.signOut().catch(() => undefined);
      }
    }
  }

  if (!completed || !cleaned || !generationID) {
    throw new Error("Hosted acceptance did not complete its render and cleanup assertions.");
  }
  console.log(
    "Hosted Studio acceptance passed: live OpenAI flat lay completed, private PNG retrieved, synthetic account deletion accepted.",
  );
  console.log(`Synthetic generation id: ${generationID}`);
}

if (import.meta.main) {
  await runHostedStudioAcceptance();
}
