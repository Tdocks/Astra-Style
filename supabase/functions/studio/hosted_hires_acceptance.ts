/**
 * Bounded no-person high-resolution export acceptance.
 *
 * This runner has two phases so the operator can insert a Premium fixture
 * subscription for the freshly created synthetic owner between phases. The
 * prepare phase makes one live inspiration draft; the finish phase makes
 * exactly one hi-res export POST and never retries. Both phases use normal
 * account deletion on failure; finish also deletes after success.
 *
 * The state file contains the synthetic access token and must be protected
 * (mode 0600). It is removed after finish/cleanup. Never print its contents.
 */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

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
  readonly premium: boolean;
  readonly limit: number;
  readonly remaining: number;
  readonly used: number;
}

interface AcceptanceState {
  readonly ownerID: string;
  readonly accessToken: string;
  readonly sourceID?: string;
  readonly sourcePath?: string;
  readonly startingUsage?: number;
}

interface DeletedReceipt {
  readonly ownerID: string;
  readonly deletionID: string;
}

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing protected acceptance setting: ${name}`);
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

async function pollToCompletion(
  baseURL: string,
  anonKey: string,
  accessToken: string,
  initial: Generation,
): Promise<{ generation: Generation; observed: ReadonlySet<Generation["status"]> }> {
  const observed = new Set<Generation["status"]>([initial.status]);
  let generation = initial;
  const deadline = Date.now() + TOTAL_TIMEOUT_MS;
  while (
    generation.status !== "complete" && generation.status !== "failed" &&
    Date.now() < deadline
  ) {
    await sleep(POLL_INTERVAL_MS);
    generation = await callStudio<Generation>(
      baseURL,
      anonKey,
      accessToken,
      `status/${generation.id}`,
      { method: "GET" },
    );
    observed.add(generation.status);
  }
  if (generation.status !== "complete") {
    throw new Error(`The bounded live render did not complete (state=${generation.status}).`);
  }
  if (!observed.has("generating")) {
    throw new Error("The live job did not expose its generating state.");
  }
  return { generation, observed };
}

async function downloadPNG(
  client: SupabaseClient,
  storagePath: string,
  localPath: string,
): Promise<{ width: number; height: number; byteLength: number }> {
  const { data: image, error } = await client.storage.from("user-content").download(storagePath);
  if (error || !image || image.type !== "image/png") {
    throw new Error("Could not retrieve the private PNG result.");
  }
  const bytes = new Uint8Array(await image.arrayBuffer());
  if (
    bytes.byteLength < 50_000 ||
    !PNG_SIGNATURE.every((byte, index) => bytes[index] === byte)
  ) {
    throw new Error("The result was not a substantial PNG image.");
  }
  const width = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(16);
  const height = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(20);
  if (width < 512 || height < 512) {
    throw new Error("The PNG dimensions are below the acceptance threshold.");
  }
  await Deno.writeFile(localPath, bytes, { createNew: true, mode: 0o600 });
  return { width, height, byteLength: bytes.byteLength };
}

async function deleteSyntheticAccount(
  baseURL: string,
  anonKey: string,
  accessToken: string,
): Promise<string> {
  const response = await fetch(`${baseURL}/functions/v1/account`, {
    method: "DELETE",
    headers: {
      apikey: anonKey,
      authorization: `Bearer ${accessToken}`,
      "x-request-id": crypto.randomUUID(),
    },
    signal: AbortSignal.timeout(30_000),
  });
  const envelope = await response.json() as Envelope<{ deletion_id?: string }>;
  if ((response.status !== 200 && response.status !== 202) || !envelope.data?.deletion_id) {
    throw new Error(`Synthetic-account deletion was not accepted (HTTP ${response.status}).`);
  }
  return envelope.data.deletion_id;
}

async function waitForDeletedIdentity(
  client: SupabaseClient,
  accessToken: string,
): Promise<void> {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const { data, error } = await client.auth.getUser(accessToken);
    if (error || !data.user) return;
    await sleep(1_000);
  }
  throw new Error("Auth still recognizes the synthetic account after deletion was accepted.");
}

async function runPrepare(
  baseURL: string,
  anonKey: string,
  statePath: string,
  draftImagePath: string,
): Promise<void> {
  const client = createClient(baseURL, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: auth, error: authError } = await client.auth.signInAnonymously();
  if (authError || !auth.session || !auth.user) {
    throw new Error("Could not create a synthetic anonymous owner.");
  }
  const { user } = auth;
  const { access_token: accessToken } = auth.session;
  let keepOwnerForFinish = false;
  let cleanupConfirmed = false;
  let statePersisted = false;
  try {
    await Deno.writeTextFile(
      statePath,
      JSON.stringify({ ownerID: user.id, accessToken } satisfies AcceptanceState),
      { createNew: true, mode: 0o600 },
    );
    statePersisted = true;
    const startingQuota = await callStudio<Quota>(
      baseURL,
      anonKey,
      accessToken,
      "quota",
      { method: "GET" },
    );
    if (startingQuota.premium || startingQuota.remaining < 1) {
      throw new Error("The fresh synthetic owner did not have the expected trial allowance.");
    }

    const accepted = await callStudio<Generation>(baseURL, anonKey, accessToken, "generate", {
      method: "POST",
      headers: { "idempotency-key": crypto.randomUUID() },
      body: JSON.stringify({
        request_id: crypto.randomUUID(),
        client_version: "P6-STUDIO-hi-res-hosted-acceptance",
        body: {
          mode: "inspiration",
          context: "Synthetic no-person flat lay; smart casual fall clothing in navy and olive.",
          instructions:
            "Show a coherent flat lay of a navy quilted jacket, olive crewneck sweater, light blue button-down, dark denim jeans, gray low-profile sneakers, a dark green knit beanie, and a brown canvas messenger bag. No person, mannequin, body parts, text, labels, logos, or extra garments.",
          preset: "smart_casual",
          background: "neutral",
          pose: "standing_front",
          formality: "balanced",
          season: "fall",
          color_palette: ["navy", "olive", "light blue", "dark denim", "warm neutral"],
          consent: { acknowledged: false, terms_version: "" },
        },
      }),
    });
    if (accepted.status !== "queued" || accepted.provider !== "openai") {
      throw new Error("The synthetic draft was not queued on the configured live provider.");
    }
    const { generation: source } = await pollToCompletion(
      baseURL,
      anonKey,
      accessToken,
      accepted,
    );
    if (!source.result_image_path || source.provider !== "openai") {
      throw new Error("The synthetic source draft has no completed provider result.");
    }
    const quotaAfterDraft = await callStudio<Quota>(
      baseURL,
      anonKey,
      accessToken,
      "quota",
      { method: "GET" },
    );
    if (quotaAfterDraft.used !== startingQuota.used + 1) {
      throw new Error("The source draft did not consume exactly one trial allowance.");
    }
    await downloadPNG(client, source.result_image_path, draftImagePath);
    const state: AcceptanceState = {
      ownerID: user.id,
      accessToken,
      sourceID: source.id,
      sourcePath: source.result_image_path,
      startingUsage: quotaAfterDraft.used,
    };
    await Deno.writeTextFile(statePath, JSON.stringify(state));
    keepOwnerForFinish = true;
    console.log(`Prepared synthetic Premium fixture owner=${user.id} source=${source.id}`);
    console.log(`Draft image: ${draftImagePath}`);
    console.log(
      "Seed only this synthetic owner with a temporary active sandbox subscription, then run finish.",
    );
  } finally {
    if (!keepOwnerForFinish) {
      try {
        await deleteSyntheticAccount(baseURL, anonKey, accessToken);
        await waitForDeletedIdentity(client, accessToken);
        cleanupConfirmed = true;
      } catch {
        console.error(`Synthetic cleanup needs retry with the protected state file: ${statePath}`);
      }
      await client.auth.signOut().catch(() => undefined);
      if (cleanupConfirmed && statePersisted) await Deno.remove(statePath).catch(() => undefined);
    }
  }
}

async function runFinish(
  baseURL: string,
  anonKey: string,
  statePath: string,
  exportImagePath: string,
): Promise<void> {
  const state = JSON.parse(await Deno.readTextFile(statePath)) as AcceptanceState;
  if (!state.sourceID || !state.sourcePath || state.startingUsage === undefined) {
    throw new Error("The prepared high-resolution source state is incomplete; use cleanup phase.");
  }
  const client = createClient(baseURL, anonKey, {
    global: { headers: { Authorization: `Bearer ${state.accessToken}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const result: {
    childID?: string;
    childImage?: { width: number; height: number; byteLength: number };
    deletionID?: string;
  } = {};
  let failure: unknown;
  try {
    const { data: owner, error: ownerError } = await client.auth.getUser(state.accessToken);
    if (ownerError || owner.user?.id !== state.ownerID) {
      throw new Error("The synthetic account session no longer matches its saved owner.");
    }
    const before = await callStudio<Quota>(
      baseURL,
      anonKey,
      state.accessToken,
      "quota",
      { method: "GET" },
    );
    if (!before.premium || before.used !== state.startingUsage || before.remaining < 1) {
      throw new Error("The temporary Premium fixture or remaining allowance is not valid.");
    }

    const source = await callStudio<Generation>(
      baseURL,
      anonKey,
      state.accessToken,
      `status/${state.sourceID}`,
      { method: "GET" },
    );
    if (source.status !== "complete" || source.result_image_path !== state.sourcePath) {
      throw new Error("The owned source draft changed before export.");
    }

    // Deliberately one export POST and no retry/replay: this is the only
    // high-resolution provider submission in this acceptance.
    const accepted = await callStudio<Generation>(
      baseURL,
      anonKey,
      state.accessToken,
      "export-hi-res",
      {
        method: "POST",
        body: JSON.stringify({
          request_id: crypto.randomUUID(),
          client_version: "P6-STUDIO-hi-res-hosted-acceptance",
          body: { source_generation_id: state.sourceID },
        }),
      },
    );
    if (accepted.status !== "queued" || accepted.provider !== "openai") {
      throw new Error("The hi-res export was not queued on the configured live provider.");
    }
    result.childID = accepted.id;
    if (
      accepted.prompt_payload?.["resolution"] !== "hi_res" ||
      accepted.prompt_payload?.["hi_res_source_generation_id"] !== state.sourceID
    ) {
      throw new Error("The accepted export did not identify its source and high-quality tier.");
    }
    const afterReserve = await callStudio<Quota>(
      baseURL,
      anonKey,
      state.accessToken,
      "quota",
      { method: "GET" },
    );
    if (afterReserve.used !== before.used + 1) {
      throw new Error("The hi-res export did not reserve exactly one Premium allowance.");
    }

    const { generation: child } = await pollToCompletion(
      baseURL,
      anonKey,
      state.accessToken,
      accepted,
    );
    if (
      child.result_image_path !== `users/${state.ownerID}/studio/${child.id}/result.png` ||
      child.prompt_payload?.["resolution"] !== "hi_res" ||
      child.prompt_payload?.["hi_res_source_generation_id"] !== state.sourceID
    ) {
      throw new Error("The completed hi-res child failed canonical path or lineage checks.");
    }
    const unchangedSource = await callStudio<Generation>(
      baseURL,
      anonKey,
      state.accessToken,
      `status/${state.sourceID}`,
      { method: "GET" },
    );
    if (
      unchangedSource.status !== "complete" ||
      unchangedSource.result_image_path !== state.sourcePath ||
      unchangedSource.prompt_payload?.["resolution"] === "hi_res"
    ) {
      throw new Error("The export changed or replaced its source draft.");
    }
    const afterComplete = await callStudio<Quota>(
      baseURL,
      anonKey,
      state.accessToken,
      "quota",
      { method: "GET" },
    );
    if (afterComplete.used !== before.used + 1) {
      throw new Error("The completed hi-res export changed Premium usage unexpectedly.");
    }
    result.childImage = await downloadPNG(client, child.result_image_path, exportImagePath);
    console.log(
      `High-resolution result validated: ${result.childImage.width}x${result.childImage.height}, ${result.childImage.byteLength} bytes.`,
    );
    console.log(`Source ${state.sourceID} remained complete; export child ${child.id} completed.`);
    console.log(`Export image: ${exportImagePath}`);
  } catch (error) {
    failure = error;
    console.error(
      `High-resolution acceptance failed: ${
        error instanceof Error ? error.message : "unknown error"
      }`,
    );
  } finally {
    let cleanupConfirmed = false;
    try {
      result.deletionID = await deleteSyntheticAccount(baseURL, anonKey, state.accessToken);
      await waitForDeletedIdentity(client, state.accessToken);
      cleanupConfirmed = true;
      console.log(
        `Synthetic owner deleted: ${state.ownerID}; deletion receipt ${result.deletionID}.`,
      );
    } finally {
      await client.auth.signOut().catch(() => undefined);
      if (cleanupConfirmed) await Deno.remove(statePath).catch(() => undefined);
    }
  }
  if (failure) throw failure;
}

async function runCleanup(baseURL: string, anonKey: string, statePath: string): Promise<void> {
  const state = JSON.parse(await Deno.readTextFile(statePath)) as AcceptanceState;
  const client = createClient(baseURL, anonKey, {
    global: { headers: { Authorization: `Bearer ${state.accessToken}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  let cleanupConfirmed = false;
  try {
    const deletionID = await deleteSyntheticAccount(baseURL, anonKey, state.accessToken);
    await waitForDeletedIdentity(client, state.accessToken);
    cleanupConfirmed = true;
    console.log(`Synthetic owner deleted: ${state.ownerID}; deletion receipt ${deletionID}.`);
  } finally {
    await client.auth.signOut().catch(() => undefined);
    if (cleanupConfirmed) await Deno.remove(statePath).catch(() => undefined);
  }
}

if (import.meta.main) {
  const phase = Deno.args[0];
  const baseURL = requiredEnvironment("SUPABASE_URL").replace(/\/$/, "");
  const anonKey = requiredEnvironment("SUPABASE_ANON_KEY");
  const statePath = requiredEnvironment("ASTRA_STUDIO_HIRES_STATE_FILE");
  if (phase === "prepare") {
    await runPrepare(
      baseURL,
      anonKey,
      statePath,
      requiredEnvironment("ASTRA_STUDIO_HIRES_DRAFT_IMAGE"),
    );
  } else if (phase === "finish") {
    await runFinish(
      baseURL,
      anonKey,
      statePath,
      requiredEnvironment("ASTRA_STUDIO_HIRES_EXPORT_IMAGE"),
    );
  } else if (phase === "cleanup") {
    await runCleanup(baseURL, anonKey, statePath);
  } else {
    throw new Error("Choose prepare, finish, or cleanup.");
  }
}
