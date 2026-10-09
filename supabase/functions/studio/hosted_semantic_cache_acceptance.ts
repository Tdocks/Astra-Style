/**
 * No-provider hosted acceptance for P6-STUDIO-07's semantic cache boundary.
 *
 * This script must be run only after the cache RPC, migration, and explicit
 * cache opt-in contract are deployed. It creates two confirmed disposable
 * QA accounts, inserts synthetic Premium rows, queues generation requests but
 * never polls them, and changes one job to complete using an actual tiny PNG
 * uploaded through Supabase Storage. It verifies a real cache hit, allowance
 * stability, legacy-client behavior, reroll behavior, and owner scoping.
 *
 * A separate owned reference-photo delete uses the normal profile endpoint
 * and Storage API. It does not toggle the global retention config or claim to
 * prove hosted age selection; the rolled-back SQL short-window test covers the
 * one-hour selector separately.
 */
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const RUN_GATE = "ASTRA_ALLOW_DISPOSABLE_STUDIO_CACHE_ACCEPTANCE";
const PNG_BYTES = Uint8Array.from(
  atob(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwTJr8HwAEFAImyd6fwgAAAABJRU5ErkJggg==",
  ),
  (character) => character.charCodeAt(0),
);
const JPEG_BYTES = Uint8Array.from(
  atob(
    "/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAAQABAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ4eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQAAQECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGRUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ4eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8A+Y6KKK/oQ/Dz/9k=",
  ),
  (character) => character.charCodeAt(0),
);

interface Envelope<T> {
  readonly data?: T | null;
  readonly error?: { readonly category?: string } | null;
}

interface SyntheticAccount {
  readonly client: SupabaseClient;
  readonly userID: string;
  readonly accessToken: string;
  readonly email: string;
}

interface Generation {
  readonly id: string;
  readonly status: "queued" | "generating" | "complete" | "failed";
  readonly result_image_path: string | null;
}

interface Quota {
  readonly used: number;
  readonly remaining: number;
}

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Required protected acceptance setting is missing: ${name}`);
  return value;
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

async function createConfirmedAccount(
  baseURL: string,
  anonKey: string,
  service: SupabaseClient,
  suffix: string,
): Promise<SyntheticAccount> {
  const id = crypto.randomUUID();
  const email = `astra-studio-cache-${suffix}-${id}@example.invalid`;
  const password = crypto.randomUUID() + crypto.randomUUID();
  const { data: created, error: createError } = await service.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (createError || !created.user) {
    throw new Error("Could not create a disposable confirmed QA account.");
  }
  const client = createClient(baseURL, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: session, error: signInError } = await client.auth.signInWithPassword({
    email,
    password,
  });
  if (signInError || !session.user || !session.session) {
    await service.auth.admin.deleteUser(created.user.id);
    throw new Error("Could not authenticate a disposable confirmed QA account.");
  }
  return {
    client,
    userID: session.user.id,
    accessToken: session.session.access_token,
    email,
  };
}

async function addSyntheticPremium(
  service: SupabaseClient,
  account: SyntheticAccount,
): Promise<void> {
  const { error } = await service.from("subscriptions").insert({
    user_id: account.userID,
    app_store_original_transaction_id: `qa-studio-cache-${crypto.randomUUID()}`,
    product_id: "qa-synthetic-premium-fixture",
    status: "active",
    expires_at: new Date(Date.now() + 86_400_000).toISOString(),
    environment: "sandbox",
  });
  if (error) throw new Error("Could not set the disposable Premium quota fixture.");
}

async function callStudio<T>(
  baseURL: string,
  anonKey: string,
  account: SyntheticAccount,
  body: Record<string, unknown>,
): Promise<T> {
  const response = await fetch(`${baseURL}/functions/v1/studio/generate`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      authorization: `Bearer ${account.accessToken}`,
      "content-type": "application/json",
      "idempotency-key": crypto.randomUUID(),
      "x-request-id": crypto.randomUUID(),
    },
    body: JSON.stringify({
      request_id: crypto.randomUUID(),
      client_version: "P6-STUDIO-07-hosted-cache-acceptance",
      body,
    }),
    signal: AbortSignal.timeout(30_000),
  });
  const envelope = await response.json() as Envelope<T>;
  if (!response.ok || envelope.error || !envelope.data) {
    throw new Error(`Studio enqueue failed with HTTP ${response.status}.`);
  }
  return envelope.data;
}

async function readQuota(
  baseURL: string,
  anonKey: string,
  account: SyntheticAccount,
): Promise<Quota> {
  const response = await fetch(`${baseURL}/functions/v1/studio/quota`, {
    headers: {
      apikey: anonKey,
      authorization: `Bearer ${account.accessToken}`,
      "x-request-id": crypto.randomUUID(),
    },
    signal: AbortSignal.timeout(30_000),
  });
  const envelope = await response.json() as Envelope<Quota>;
  if (!response.ok || envelope.error || !envelope.data) {
    throw new Error(`Studio quota read failed with HTTP ${response.status}.`);
  }
  return envelope.data;
}

function stableRequest(optIn: boolean, variationNonce?: string): Record<string, unknown> {
  return {
    mode: "inspiration",
    context: "Synthetic QA outfit context, neutral palette, indoors.",
    instructions: "A coordinated flat lay of ordinary basics.",
    preset: "smart_casual",
    background: "neutral",
    pose: "standing_front",
    formality: "balanced",
    season: "fall",
    color_palette: ["navy", "olive"],
    ...(optIn ? { semantic_cache_opt_in: true } : {}),
    ...(variationNonce ? { variation_nonce: variationNonce } : {}),
    consent: { acknowledged: false, terms_version: "" },
  };
}

async function deleteAccount(
  baseURL: string,
  anonKey: string,
  service: SupabaseClient,
  account: SyntheticAccount,
): Promise<void> {
  const response = await fetch(`${baseURL}/functions/v1/account`, {
    method: "DELETE",
    headers: {
      apikey: anonKey,
      authorization: `Bearer ${account.accessToken}`,
      "x-request-id": crypto.randomUUID(),
    },
    signal: AbortSignal.timeout(30_000),
  });
  if (response.status !== 202) {
    await response.body?.cancel();
    throw new Error(`Disposable QA account deletion returned HTTP ${response.status}.`);
  }
  const receipt = await response.json() as Envelope<{ deletion_id?: string }>;
  const deletionID = receipt.data?.deletion_id;
  if (!deletionID) throw new Error("Account deletion did not return a receipt.");

  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    const { data, error } = await service.from("account_deletions")
      .select("status")
      .eq("id", deletionID)
      .maybeSingle();
    if (error) throw new Error("Could not verify QA account deletion status.");
    if (data?.status === "completed") {
      const { data: authData, error: authError } = await service.auth.admin.getUserById(
        account.userID,
      );
      if (!authError && authData.user) throw new Error("Auth still recognizes a deleted QA user.");
      if (authError && (authError as { status?: number }).status !== 404) {
        throw new Error("Could not verify deletion of the QA Auth identity.");
      }
      const tables = ["studio_generations", "studio_allowances", "subscriptions", "body_profiles"];
      for (const table of tables) {
        const { count, error: countError } = await service.from(table)
          .select("id", { count: "exact", head: true })
          .eq("user_id", account.userID);
        if (countError || count !== 0) throw new Error("QA account deletion left owned rows.");
      }
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error("QA account deletion did not reach completed status.");
}

async function removeFixtureObject(
  service: SupabaseClient,
  path: string,
): Promise<void> {
  const { error } = await service.storage.from("user-content").remove([path]);
  if (error) throw new Error("Could not remove synthetic cache result through Storage API.");
}

async function deleteOwnedReferenceViaProfileAPI(
  baseURL: string,
  anonKey: string,
  owner: SyntheticAccount,
  service: SupabaseClient,
): Promise<void> {
  const referencePath = `users/${owner.userID}/references/${crypto.randomUUID()}.jpg`;
  const { error: uploadError } = await owner.client.storage.from("user-content").upload(
    referencePath,
    JPEG_BYTES,
    { contentType: "image/jpeg", upsert: false },
  );
  if (uploadError) throw new Error("Could not upload the synthetic owned reference photo.");

  const { error: profileError } = await owner.client.from("body_profiles").upsert({
    user_id: owner.userID,
    appearance: { reference_selfie_paths: [referencePath] },
  }, { onConflict: "user_id" });
  if (profileError) throw new Error("Could not associate the synthetic reference with its owner.");

  const response = await fetch(`${baseURL}/functions/v1/profile/reference-photos`, {
    method: "DELETE",
    headers: {
      apikey: anonKey,
      authorization: `Bearer ${owner.accessToken}`,
      "content-type": "application/json",
      "x-request-id": crypto.randomUUID(),
    },
    body: JSON.stringify({ path: referencePath }),
    signal: AbortSignal.timeout(30_000),
  });
  const envelope = await response.json() as Envelope<{ status?: string }>;
  if (response.status !== 200 || envelope.error || envelope.data?.status !== "complete") {
    throw new Error(
      `Owned reference deletion was not completed by the normal API (HTTP ${response.status}).`,
    );
  }
  const filename = referencePath.split("/").at(-1)!;
  const { data: remainingObjects, error: listError } = await owner.client.storage
    .from("user-content")
    .list(`users/${owner.userID}/references`);
  if (listError || remainingObjects?.some((object) => object.name === filename)) {
    throw new Error("Reference deletion completed but the synthetic Storage object remained.");
  }
  const { data: profile, error: readError } = await owner.client.from("body_profiles")
    .select("appearance")
    .eq("user_id", owner.userID)
    .single();
  const savedPaths = (profile?.appearance as { reference_selfie_paths?: unknown[] } | undefined)
    ?.reference_selfie_paths ?? [];
  if (readError || savedPaths.includes(referencePath)) {
    throw new Error("Reference deletion did not clear the owner's body-profile association.");
  }
  const { data: jobs, error: jobError } = await service.from("studio_retention_jobs")
    .select("kind,status,result_image_path")
    .eq("user_id", owner.userID)
    .eq("generation_key", referencePath.split("/").at(-1)?.replace(/\.jpg$/, ""));
  if (
    jobError ||
    !jobs?.some((job) =>
      job.kind === "reference" && job.status === "complete" && job.result_image_path === null
    )
  ) {
    throw new Error("Reference deletion did not finalize its durable cleanup record.");
  }
}

export async function runHostedStudioCacheAcceptance(): Promise<void> {
  if (Deno.env.get(RUN_GATE) !== "YES") {
    throw new Error(
      `Set ${RUN_GATE}=YES only after the cache migration and function deploy are verified.`,
    );
  }
  const baseURL = requiredEnvironment("SUPABASE_URL").replace(/\/$/, "");
  const keysFile = requiredEnvironment("SUPABASE_KEYS_FILE");
  const keyRecords = JSON.parse(await Deno.readTextFile(keysFile)) as Array<{
    readonly name?: string;
    readonly api_key?: string;
  }>;
  const anonKey = keyRecords.find((record) => record.name === "anon")?.api_key;
  const serviceKey = keyRecords.find((record) => record.name === "service_role")?.api_key;
  if (!anonKey || !serviceKey) throw new Error("Protected Supabase key file is incomplete.");
  const service = createClient(baseURL, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  let owner: SyntheticAccount | undefined;
  let peer: SyntheticAccount | undefined;
  let outputPath: string | undefined;
  let primaryFailure: unknown;
  const cleanupFailures: string[] = [];
  try {
    owner = await createConfirmedAccount(baseURL, anonKey, service, "owner");
    peer = await createConfirmedAccount(baseURL, anonKey, service, "peer");
    await Promise.all([addSyntheticPremium(service, owner), addSyntheticPremium(service, peer)]);

    const startingQuota = await readQuota(baseURL, anonKey, owner);
    assert(startingQuota.used === 0, "Fresh synthetic owner already has a used allowance.");
    const optInBody = stableRequest(true);
    const first = await callStudio<Generation>(baseURL, anonKey, owner, optInBody);
    assert(first.status === "queued", "The cache seed request was not queued.");
    const { data: seedRows, error: seedError } = await service.from("studio_generations")
      .select("cache_key,allowance_id")
      .eq("id", first.id)
      .eq("user_id", owner.userID)
      .single();
    if (seedError || !seedRows || !/^[0-9a-f]{64}$/.test(seedRows.cache_key ?? "")) {
      throw new Error("Deployed function did not persist the opted-in semantic cache key.");
    }
    outputPath = `users/${owner.userID}/studio/${first.id}/result.png`;
    const { error: imageError } = await owner.client.storage.from("user-content").upload(
      outputPath,
      PNG_BYTES,
      { contentType: "image/png", upsert: false },
    );
    if (imageError) throw new Error("Could not upload the synthetic Studio result PNG.");
    const { error: completeError } = await service.from("studio_generations")
      .update({ status: "complete", result_image_path: outputPath })
      .eq("id", first.id)
      .eq("user_id", owner.userID);
    if (completeError) throw new Error("Could not complete the synthetic cache seed generation.");

    const beforeHit = await readQuota(baseURL, anonKey, owner);
    const replay = await callStudio<Generation>(baseURL, anonKey, owner, optInBody);
    assert(
      replay.id === first.id,
      "Equivalent opted-in request did not reuse the completed result.",
    );
    const afterHit = await readQuota(baseURL, anonKey, owner);
    assert(afterHit.used === beforeHit.used, "Semantic cache hit reserved another allowance.");
    assert(afterHit.used === 1, "Cache seed should consume exactly one Premium allowance.");

    const legacy = await callStudio<Generation>(baseURL, anonKey, owner, stableRequest(false));
    assert(legacy.id !== first.id, "Legacy request without opt-in reused a semantic result.");
    assert(legacy.status === "queued", "Legacy request did not create an independent queued job.");

    const reroll = await callStudio<Generation>(
      baseURL,
      anonKey,
      owner,
      stableRequest(true, crypto.randomUUID()),
    );
    assert(reroll.id !== first.id, "Explicit reroll nonce reused the prior result.");

    const peerResult = await callStudio<Generation>(baseURL, anonKey, peer, optInBody);
    assert(peerResult.id !== first.id, "Peer received another owner's cached generation.");
    assert(peerResult.status === "queued", "Peer cache miss did not create its own queued job.");

    await deleteOwnedReferenceViaProfileAPI(baseURL, anonKey, owner, service);
    console.log(
      "Studio semantic cache and owned reference deletion assertions passed; cleanup follows.",
    );
  } catch (error) {
    primaryFailure = error;
  } finally {
    if (outputPath) {
      try {
        await removeFixtureObject(service, outputPath);
      } catch {
        cleanupFailures.push("synthetic result Storage object");
      }
    }
    if (peer) {
      try {
        await deleteAccount(baseURL, anonKey, service, peer);
      } catch {
        cleanupFailures.push("peer account");
      }
    }
    if (owner) {
      try {
        await deleteAccount(baseURL, anonKey, service, owner);
      } catch {
        cleanupFailures.push("owner account");
      }
    }
    if (owner && peer) {
      console.log(
        `Disposable owner/peer IDs for independent cleanup verification: ${owner.userID}, ${peer.userID}`,
      );
    }
  }

  if (primaryFailure) {
    const message = primaryFailure instanceof Error
      ? primaryFailure.message
      : "unknown acceptance failure";
    throw new Error(
      message + (cleanupFailures.length ? `; cleanup failed: ${cleanupFailures.join(", ")}` : ""),
    );
  }
  if (cleanupFailures.length) throw new Error(`Cleanup failed: ${cleanupFailures.join(", ")}`);
  console.log("Both confirmed synthetic accounts reached completed deletion and Auth cleanup.");
  if (owner && peer) console.log(`Disposable owner/peer IDs: ${owner.userID}, ${peer.userID}`);
  console.log("No Studio status endpoint was called; no image provider was contacted.");
}

if (import.meta.main) await runHostedStudioCacheAcceptance();
