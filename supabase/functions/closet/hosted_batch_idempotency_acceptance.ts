import { assert, assertEquals } from "@std/assert";

// Bounded, no-provider hosted acceptance for closet batch-job ownership and
// retry identity. Every submitted path is synthetic and nonexistent; this
// script never polls a job, uploads bytes, or invokes the image provider.
// Accounts are created anonymously and removed through DELETE /account.
const PROJECT_REF = "anutsdzbxycaavmmkewo";
const BASE_URL = `https://${PROJECT_REF}.supabase.co`;
const RUN_GATE = "ASTRA_RUN_CLOSET_BATCH_IDEMPOTENCY_ACCEPTANCE";

type Row = Record<string, unknown>;
type Account = { id: string; token: string; deleted: boolean };

const accounts: Account[] = [];
const results: Row = { provider_calls: 0, image_uploads: 0, status_polls: 0 };
const cleanupErrors: string[] = [];
let failure: string | null = null;
let stage = "starting";
const reportPath = Deno.args[1];

function headers(token?: string): Headers {
  const value = new Headers({
    apikey: publishableKey,
    "Content-Type": "application/json",
  });
  if (token) value.set("Authorization", `Bearer ${token}`);
  return value;
}

async function readJSON(response: Response): Promise<Row> {
  try {
    const value: unknown = await response.json();
    return value && typeof value === "object" ? value as Row : {};
  } catch {
    return {};
  }
}

async function request(
  path: string,
  token: string,
  init: RequestInit = {},
): Promise<Response> {
  return await fetch(`${BASE_URL}${path}`, {
    ...init,
    headers: { ...Object.fromEntries(headers(token)), ...init.headers },
    signal: init.signal ?? AbortSignal.timeout(20_000),
  });
}

async function writeReport(): Promise<void> {
  if (!reportPath) return;
  await Deno.writeTextFile(
    reportPath,
    JSON.stringify({ stage, results, failure, cleanup_errors: cleanupErrors }, null, 2),
    { mode: 0o600 },
  );
  await Deno.chmod(reportPath, 0o600);
}

async function createAnonymousAccount(label: string): Promise<Account> {
  const response = await fetch(`${BASE_URL}/auth/v1/signup`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({}),
    signal: AbortSignal.timeout(20_000),
  });
  const value = await readJSON(response);
  const user = value.user as Row | undefined;
  if (
    !response.ok || typeof user?.id !== "string" ||
    typeof value.access_token !== "string"
  ) {
    throw new Error(`${label} disposable anonymous signup failed (HTTP ${response.status}).`);
  }
  const account = { id: user.id, token: value.access_token, deleted: false };
  accounts.push(account);
  results[`created_${label}`] = { user_id: account.id };
  await writeReport();
  return account;
}

function stableBatchEnvelope(path: string): Row {
  const itemRequestID = crypto.randomUUID();
  const requestID = crypto.randomUUID();
  return {
    request_id: requestID,
    client_version: "hosted-batch-idempotency-acceptance",
    body: {
      items: [{ request_id: itemRequestID, storage_path: path, image_type: "front" }],
      // Deliberately lie in the body. The edge function must use the JWT.
      user_id: crypto.randomUUID(),
    },
  };
}

async function enqueue(
  account: Account,
  idempotencyKey: string,
  envelope: Row,
): Promise<{ response: Response; data: Row }> {
  const response = await request("/functions/v1/closet/batch-analyze", account.token, {
    method: "POST",
    headers: { "Idempotency-Key": idempotencyKey },
    body: JSON.stringify(envelope),
  });
  const payload = await readJSON(response);
  return {
    response,
    data: payload.data && typeof payload.data === "object" ? payload.data as Row : {},
  };
}

async function cancel(
  account: Account,
  idempotencyKey: string,
): Promise<{ response: Response; data: Row }> {
  const response = await request("/functions/v1/closet/batch-cancel", account.token, {
    method: "POST",
    headers: { "Idempotency-Key": idempotencyKey },
  });
  const payload = await readJSON(response);
  return {
    response,
    data: payload.data && typeof payload.data === "object" ? payload.data as Row : {},
  };
}

async function readOwnerJob(account: Account, jobID: string): Promise<Row[]> {
  const query = new URLSearchParams({
    select: "id,user_id,status,idempotency_key,request_hash,items,results,error_message",
    id: `eq.${jobID}`,
  });
  const response = await request(
    `/rest/v1/closet_analysis_jobs?${query}`,
    account.token,
  );
  assert(response.ok, `Owner SELECT failed (HTTP ${response.status}).`);
  const value: unknown = await response.json();
  assert(Array.isArray(value), "Owner SELECT did not return a row array.");
  return value as Row[];
}

async function readOwnerJobByKey(account: Account, idempotencyKey: string): Promise<Row[]> {
  const query = new URLSearchParams({
    select: "id,user_id,status,idempotency_key,items,results,error_message",
    idempotency_key: `eq.${idempotencyKey}`,
  });
  const response = await request(
    `/rest/v1/closet_analysis_jobs?${query}`,
    account.token,
  );
  assert(response.ok, `Owner key SELECT failed (HTTP ${response.status}).`);
  const value: unknown = await response.json();
  assert(Array.isArray(value), "Owner key SELECT did not return a row array.");
  return value as Row[];
}

async function expectDenied(response: Response, action: string): Promise<number> {
  await response.arrayBuffer();
  assert(
    response.status >= 400 && response.status < 500,
    `Direct ${action} should be denied with a client error; got HTTP ${response.status}.`,
  );
  return response.status;
}

async function deleteNormally(account: Account): Promise<void> {
  const response = await request("/functions/v1/account", account.token, {
    method: "DELETE",
    body: JSON.stringify({}),
  });
  const payload = await readJSON(response);
  if (response.status !== 202 && response.status !== 200) {
    throw new Error(`Normal account cleanup failed (HTTP ${response.status}).`);
  }
  account.deleted = true;
  const data = payload.data && typeof payload.data === "object" ? payload.data as Row : {};
  results[`cleanup_${account.id}`] = {
    status: response.status,
    deletion_id: data.deletion_id ?? payload.deletion_id ?? null,
  };
}

if (Deno.env.get(RUN_GATE) !== "1") {
  throw new Error(`Set ${RUN_GATE}=1 to run this disposable hosted acceptance.`);
}

const keysFile = Deno.args[0];
if (!keysFile) throw new Error("Pass the protected Supabase CLI API-key JSON path.");
const keys = JSON.parse(await Deno.readTextFile(keysFile)) as Array<Row>;
const key = keys.find((entry) => entry.type === "publishable")?.api_key;
if (typeof key !== "string") throw new Error("Publishable API key unavailable.");
const publishableKey = key;

try {
  stage = "create anonymous owner and peer";
  const owner = await createAnonymousAccount("owner");
  const peer = await createAnonymousAccount("peer");

  stage = "enqueue and replay the owner's identical body";
  const ownerKey = crypto.randomUUID();
  const ownerPath = `users/${owner.id}/closet/nonexistent-${crypto.randomUUID()}.jpg`;
  const ownerEnvelope = stableBatchEnvelope(ownerPath);
  const first = await enqueue(owner, ownerKey, ownerEnvelope);
  const replay = await enqueue(owner, ownerKey, ownerEnvelope);
  assertEquals(first.response.status, 202, "first request should enqueue without polling");
  assertEquals(replay.response.status, 202, "retry should replay without polling");
  assertEquals(first.data.status, "queued");
  assertEquals(replay.data.status, "queued");
  assert(typeof first.data.job_id === "string", "first response lacks job ID");
  assertEquals(replay.data.job_id, first.data.job_id, "same owner/key/body returns the same job");
  const ownerJobID = first.data.job_id as string;
  results.primary_owner_job_id = ownerJobID;
  await writeReport();

  stage = "reject changed body under the same owner key";
  const changed = await enqueue(
    owner,
    ownerKey,
    stableBatchEnvelope(`users/${owner.id}/closet/changed-${crypto.randomUUID()}.jpg`),
  );
  assertEquals(changed.response.status, 409, "changed body must conflict");

  stage = "owner-scoped SELECT and peer isolation";
  const ownerRows = await readOwnerJob(owner, ownerJobID);
  assertEquals(ownerRows.length, 1);
  assertEquals(ownerRows[0]?.user_id, owner.id);
  const peerRows = await readOwnerJob(peer, ownerJobID);
  assertEquals(peerRows.length, 0, "peer RLS SELECT must not reveal the owner's job");

  const peerGet = await request(
    `/functions/v1/closet/batch-status/${ownerJobID}`,
    peer.token,
  );
  assertEquals(peerGet.status, 404, "peer must not fetch the owner's job status");
  await peerGet.arrayBuffer();

  stage = "direct client INSERT, UPDATE and DELETE denied";
  const directInsert = await request(
    "/rest/v1/closet_analysis_jobs?select=id",
    owner.token,
    {
      method: "POST",
      headers: { Prefer: "return=representation" },
      body: JSON.stringify({
        user_id: owner.id,
        status: "queued",
        items: [],
        results: [],
        idempotency_key: `forged-${crypto.randomUUID()}`,
        request_hash: "a".repeat(64),
      }),
    },
  );
  const insertStatus = await expectDenied(directInsert, "INSERT");

  const directUpdate = await request(
    `/rest/v1/closet_analysis_jobs?id=eq.${ownerJobID}`,
    owner.token,
    { method: "PATCH", body: JSON.stringify({ status: "complete" }) },
  );
  const updateStatus = await expectDenied(directUpdate, "UPDATE");

  const directDelete = await request(
    `/rest/v1/closet_analysis_jobs?id=eq.${ownerJobID}`,
    owner.token,
    { method: "DELETE" },
  );
  const deleteStatus = await expectDenied(directDelete, "DELETE");
  const afterMutationAttempts = await readOwnerJob(owner, ownerJobID);
  assertEquals(afterMutationAttempts, ownerRows, "denied DML must leave the owned job unchanged");

  // A shared idempotency key across owners must still result in distinct rows.
  stage = "same key remains owner scoped";
  const sharedKey = crypto.randomUUID();
  const peerEnqueue = await enqueue(
    peer,
    sharedKey,
    stableBatchEnvelope(`users/${peer.id}/closet/nonexistent-${crypto.randomUUID()}.jpg`),
  );
  const ownerEnqueue = await enqueue(
    owner,
    sharedKey,
    stableBatchEnvelope(`users/${owner.id}/closet/nonexistent-${crypto.randomUUID()}.jpg`),
  );
  assertEquals(peerEnqueue.response.status, 202);
  assertEquals(ownerEnqueue.response.status, 202);
  assert(peerEnqueue.data.job_id !== ownerEnqueue.data.job_id, "idempotency keys are owner scoped");

  stage = "cancel-before-enqueue tombstone, replay, and owner isolation";
  const earlyCancelKey = crypto.randomUUID();
  const earlyCancel = await cancel(owner, earlyCancelKey);
  const earlyCancelReplay = await cancel(owner, earlyCancelKey);
  assertEquals(earlyCancel.response.status, 200);
  assertEquals(earlyCancel.data.cancelled, true);
  assertEquals(earlyCancelReplay.response.status, 200);
  assertEquals(earlyCancelReplay.data.cancelled, true);
  const tombstonedEnqueue = await enqueue(
    owner,
    earlyCancelKey,
    stableBatchEnvelope(`users/${owner.id}/closet/cancelled-${crypto.randomUUID()}.jpg`),
  );
  assertEquals(tombstonedEnqueue.response.status, 409);

  // The same key remains independent for another owner: their enqueue is
  // queued, and an owner-side replay of its own tombstone cannot affect it.
  const peerEnqueueUnderTombstonedKey = await enqueue(
    peer,
    earlyCancelKey,
    stableBatchEnvelope(`users/${peer.id}/closet/peer-${crypto.randomUUID()}.jpg`),
  );
  assertEquals(peerEnqueueUnderTombstonedKey.response.status, 202);
  const peerJobID = peerEnqueueUnderTombstonedKey.data.job_id;
  assert(typeof peerJobID === "string");
  results.cancel_before_enqueue_owner_tombstone = earlyCancelKey;
  results.peer_job_under_same_key = peerJobID;
  await writeReport();
  assertEquals((await cancel(owner, earlyCancelKey)).response.status, 200);
  const peerJobAfterOwnerCancel = await readOwnerJob(peer, peerJobID);
  assertEquals(peerJobAfterOwnerCancel.length, 1);
  assertEquals(peerJobAfterOwnerCancel[0]?.status, "queued");

  stage = "peer cancellation cannot mutate owner's queued job";
  const peerCancelOfOwnerKey = await cancel(peer, ownerKey);
  assertEquals(peerCancelOfOwnerKey.response.status, 200);
  assertEquals(peerCancelOfOwnerKey.data.cancelled, true);
  const peerTombstone = await readOwnerJobByKey(peer, ownerKey);
  assertEquals(peerTombstone.length, 1);
  assertEquals(peerTombstone[0]?.status, "failed");
  assertEquals(peerTombstone[0]?.items, []);
  const ownerJobAfterPeerCancel = await readOwnerJob(owner, ownerJobID);
  assertEquals(ownerJobAfterPeerCancel.length, 1);
  assertEquals(ownerJobAfterPeerCancel[0]?.status, "queued");

  stage = "owner cancellation clears its existing queued job and replays";
  const ownerCancel = await cancel(owner, ownerKey);
  const ownerCancelReplay = await cancel(owner, ownerKey);
  assertEquals(ownerCancel.response.status, 200);
  assertEquals(ownerCancel.data.cancelled, true);
  assertEquals(ownerCancelReplay.response.status, 200);
  assertEquals(ownerCancelReplay.data.cancelled, true);
  const cancelledOwnerJob = await readOwnerJob(owner, ownerJobID);
  assertEquals(cancelledOwnerJob.length, 1);
  assertEquals(cancelledOwnerJob[0]?.status, "failed");
  assertEquals(cancelledOwnerJob[0]?.items, []);
  assertEquals(cancelledOwnerJob[0]?.results, []);
  const peerJobAfterReplay = await readOwnerJob(peer, peerJobID);
  assertEquals(peerJobAfterReplay[0]?.status, "queued");

  results.batch_cancel = {
    cancel_before_enqueue_status: earlyCancel.response.status,
    cancel_before_enqueue_replay_status: earlyCancelReplay.response.status,
    late_owner_enqueue_status: tombstonedEnqueue.response.status,
    peer_enqueue_same_key_status: peerEnqueueUnderTombstonedKey.response.status,
    owner_replay_preserved_peer_queue: peerJobAfterOwnerCancel[0]?.status === "queued" &&
      peerJobAfterReplay[0]?.status === "queued",
    peer_cancel_of_owner_key_status: peerCancelOfOwnerKey.response.status,
    owner_job_unchanged_by_peer_cancel: ownerJobAfterPeerCancel[0]?.status === "queued",
    owner_existing_job_cancel_status: ownerCancel.response.status,
    owner_cancel_replay_status: ownerCancelReplay.response.status,
    cancelled_owner_job_status: cancelledOwnerJob[0]?.status,
    cancelled_items: (cancelledOwnerJob[0]?.items as unknown[] | undefined)?.length ?? null,
    cancelled_results: (cancelledOwnerJob[0]?.results as unknown[] | undefined)?.length ?? null,
    provider_calls: 0,
    image_uploads: 0,
    status_polls: 0,
  };

  results.batch_enqueue = {
    first_status: first.response.status,
    replay_status: replay.response.status,
    same_job_replayed: replay.data.job_id === first.data.job_id,
    changed_body_status: changed.response.status,
    peer_status_status: peerGet.status,
    owner_select_rows: ownerRows.length,
    peer_select_rows: peerRows.length,
    direct_insert_status: insertStatus,
    direct_update_status: updateStatus,
    direct_delete_status: deleteStatus,
    peer_scoped_key_distinct_jobs: peerEnqueue.data.job_id !== ownerEnqueue.data.job_id,
    status_polls: 0,
    provider_calls: 0,
    image_uploads: 0,
    owner_id: owner.id,
    peer_id: peer.id,
    owner_job_id: ownerJobID,
    cancelled_peer_control_job_id: peerJobID,
  };
  stage = "acceptance assertions passed; normal account cleanup pending";
} catch (error) {
  failure = error instanceof Error ? error.message : "unknown acceptance failure";
} finally {
  for (const account of [...accounts].reverse()) {
    if (account.deleted) continue;
    try {
      await deleteNormally(account);
    } catch {
      cleanupErrors.push(account.id);
    }
  }
  await writeReport();
}

console.log(JSON.stringify({ stage, results, failure, cleanup_errors: cleanupErrors }));
if (cleanupErrors.length > 0) {
  throw new Error(`Normal account cleanup failed for fixture IDs: ${cleanupErrors.join(", ")}`);
}
if (failure) throw new Error(failure);
