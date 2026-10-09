import { assertEquals } from "@std/assert";

// Opt-in hosted acceptance for replace_outfit_items. Reads the publishable key
// from a protected Supabase CLI key file; all fixture rows use disposable
// caller JWTs and ordinary RLS. No images, storage, or providers are involved.
const projectRef = "anutsdzbxycaavmmkewo";
const baseURL = `https://${projectRef}.supabase.co`;
if (Deno.env.get("ASTRA_RUN_OUTFIT_EDIT_ACCEPTANCE") !== "1") {
  throw new Error("Set ASTRA_RUN_OUTFIT_EDIT_ACCEPTANCE=1 to run this hosted acceptance.");
}
const keyFile = Deno.args[0];
if (!keyFile) throw new Error("Pass the protected Supabase CLI API-key JSON path.");
const keys = JSON.parse(await Deno.readTextFile(keyFile)) as Array<Record<string, unknown>>;
const publishableKeyValue = keys.find((key) => key.type === "publishable")?.api_key;
if (typeof publishableKeyValue !== "string") throw new Error("Publishable key unavailable.");
const publishableKey: string = publishableKeyValue;

type Account = { id: string; token: string; deleted: boolean };
type Row = Record<string, unknown>;
const accounts: Account[] = [];
const results: Row = {};
const cleanupErrors: string[] = [];
let runFailure: string | null = null;
let stage = "starting";
const reportPath = Deno.args[1];

async function writeReport(): Promise<void> {
  if (!reportPath) return;
  await Deno.writeTextFile(
    reportPath,
    JSON.stringify({ stage, results, failure: runFailure, cleanup_errors: cleanupErrors }, null, 2),
    { mode: 0o600 },
  );
}

function headers(token?: string): Headers {
  const value = new Headers({ apikey: publishableKey, "Content-Type": "application/json" });
  if (token) value.set("Authorization", `Bearer ${token}`);
  return value;
}

async function body(response: Response): Promise<Row> {
  try {
    const value = await response.json();
    return value && typeof value === "object" ? value as Row : {};
  } catch {
    return {};
  }
}

async function createAccount(label: string): Promise<Account> {
  const response = await fetch(`${baseURL}/auth/v1/signup`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({}),
    signal: AbortSignal.timeout(20_000),
  });
  const value = await body(response);
  const user = value.user as Row | undefined;
  if (!response.ok || typeof user?.id !== "string" || typeof value.access_token !== "string") {
    throw new Error(`${label} disposable signup failed (HTTP ${response.status}).`);
  }
  const account = { id: user.id, token: value.access_token, deleted: false };
  accounts.push(account);
  results[`created_${label}`] = { id: account.id };
  await writeReport();
  return account;
}

async function request(path: string, token: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${baseURL}${path}`, {
    ...init,
    headers: { ...Object.fromEntries(headers(token)), ...init.headers },
    signal: init.signal ?? AbortSignal.timeout(20_000),
  });
}

async function insert<T extends Row>(table: string, account: Account, value: Row): Promise<T> {
  const response = await request(`/rest/v1/${table}?select=*`, account.token, {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify(value),
  });
  const result = await response.json().catch(() => []);
  if (!response.ok || !Array.isArray(result) || result.length !== 1) {
    const error = result && typeof result === "object" ? result as Row : {};
    const code = typeof error.code === "string" ? error.code : "unknown";
    throw new Error(`${table} fixture insert failed (HTTP ${response.status}, ${code}).`);
  }
  return result[0] as T;
}

async function rows(
  table: string,
  account: Account,
  query: string,
): Promise<Row[]> {
  const response = await request(`/rest/v1/${table}?${query}`, account.token);
  if (!response.ok) throw new Error(`${table} fixture read failed (HTTP ${response.status}).`);
  const value = await response.json();
  return Array.isArray(value) ? value as Row[] : [];
}

async function patchOwnedRow(
  table: string,
  account: Account,
  query: string,
  value: Row,
): Promise<Response> {
  return await request(`/rest/v1/${table}?${query}`, account.token, {
    method: "PATCH",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify(value),
  });
}

async function edit(
  account: Account,
  outfitID: string,
  expectedUpdatedAt: string,
  name: string,
  itemIDs: string[],
): Promise<Response> {
  return await request("/rest/v1/rpc/replace_outfit_items", account.token, {
    method: "POST",
    body: JSON.stringify({
      p_outfit_id: outfitID,
      p_expected_updated_at: expectedUpdatedAt,
      p_name: name,
      p_description: "Synthetic hosted outfit edit acceptance fixture",
      p_compatibility_score: 76,
      p_items: itemIDs.map((closet_item_id, sort_order) => ({
        closet_item_id,
        role: ["top", "bottom", "shoes"][sort_order],
        sort_order,
      })),
    }),
  });
}

async function deleteAccount(account: Account): Promise<void> {
  const response = await request("/functions/v1/account", account.token, {
    method: "DELETE",
    body: JSON.stringify({}),
  });
  const value = await body(response);
  if (!response.ok) throw new Error(`Normal account cleanup failed (HTTP ${response.status}).`);
  account.deleted = true;
  results[`cleanup_${account.id}`] = {
    status: response.status,
    deletion_id: value.deletion_id ?? (value.data as Row | undefined)?.deletion_id ?? null,
  };
}

async function ownedSnapshot(owner: Account, outfitID: string): Promise<Row> {
  const [outfits, items, wears] = await Promise.all([
    rows(
      "outfits",
      owner,
      `select=id,user_id,name,description,compatibility_score,updated_at&id=eq.${outfitID}`,
    ),
    rows(
      "outfit_items",
      owner,
      `select=id,outfit_id,user_id,closet_item_id,role,sort_order,is_required,created_at,updated_at&outfit_id=eq.${outfitID}&order=sort_order.asc`,
    ),
    rows(
      "outfit_wears",
      owner,
      `select=id,outfit_id,user_id,worn_at,occasion,rating,feedback,created_at,updated_at&outfit_id=eq.${outfitID}`,
    ),
  ]);
  return { outfits, items, wears };
}

try {
  stage = "create accounts";
  const owner = await createAccount("owner");
  const peer = await createAccount("peer");
  stage = "insert garments";
  const garments = await Promise.all([
    insert("closet_items", owner, {
      user_id: owner.id,
      name: "Acceptance top",
      category: "top",
      primary_color: "navy",
    }),
    insert("closet_items", owner, {
      user_id: owner.id,
      name: "Acceptance trousers",
      category: "bottom",
      primary_color: "grey",
    }),
    insert("closet_items", owner, {
      user_id: owner.id,
      name: "Acceptance shoes",
      category: "shoes",
      primary_color: "brown",
    }),
  ]);
  const peerGarment = await insert("closet_items", peer, {
    user_id: peer.id,
    name: "Peer acceptance top",
    category: "top",
    primary_color: "green",
  });
  const careTargetID = String(garments[0].id);
  const careSet = await patchOwnedRow(
    "closet_items",
    owner,
    `id=eq.${careTargetID}&select=id,care_instructions`,
    { care_instructions: "Hand wash cold; dry flat." },
  );
  if (!careSet.ok) {
    throw new Error(`Owner care-instructions write failed (HTTP ${careSet.status}).`);
  }
  const careSetRows = await careSet.json() as Row[];
  assertEquals(careSetRows.length, 1);
  assertEquals(careSetRows[0]?.care_instructions, "Hand wash cold; dry flat.");

  const careClear = await patchOwnedRow(
    "closet_items",
    owner,
    `id=eq.${careTargetID}&select=id,care_instructions`,
    { care_instructions: null },
  );
  if (!careClear.ok) {
    throw new Error(`Owner care-instructions clear failed (HTTP ${careClear.status}).`);
  }
  const careClearRows = await careClear.json() as Row[];
  assertEquals(careClearRows.length, 1);
  assertEquals(
    careClearRows[0]?.care_instructions,
    null,
    "explicit JSON null clears stored care text",
  );

  const peerCareWrite = await patchOwnedRow(
    "closet_items",
    peer,
    `id=eq.${careTargetID}&select=id,care_instructions`,
    { care_instructions: "Peer must not edit this." },
  );
  if (!peerCareWrite.ok) {
    throw new Error(`Peer care-write request failed unexpectedly (HTTP ${peerCareWrite.status}).`);
  }
  const peerCareRows = await peerCareWrite.json() as Row[];
  assertEquals(peerCareRows.length, 0, "peer cannot update owner care instructions");
  const careAfterPeer = await rows(
    "closet_items",
    owner,
    `select=id,care_instructions&id=eq.${careTargetID}`,
  );
  assertEquals(
    careAfterPeer[0]?.care_instructions,
    null,
    "peer write leaves cleared value unchanged",
  );
  const outfit = await insert("outfits", owner, {
    user_id: owner.id,
    name: "Before edit",
    description: "Synthetic acceptance fixture",
    source: "user_created",
  });
  const peerOutfit = await insert("outfits", peer, {
    user_id: peer.id,
    name: "Peer outfit",
    description: "Synthetic peer fixture",
    source: "user_created",
  });
  const initialItems = [garments[0], garments[1]];
  for (let index = 0; index < initialItems.length; index++) {
    const garment = initialItems[index]!;
    await insert("outfit_items", owner, {
      outfit_id: outfit.id,
      user_id: owner.id,
      closet_item_id: garment.id,
      role: garment.category,
      sort_order: index,
      is_required: true,
    });
  }
  await insert("outfit_items", peer, {
    outfit_id: peerOutfit.id,
    user_id: peer.id,
    closet_item_id: peerGarment.id,
    role: "top",
    sort_order: 0,
    is_required: true,
  });
  const wear = await insert("outfit_wears", owner, {
    user_id: owner.id,
    outfit_id: outfit.id,
    worn_at: "2026-10-01T12:00:00Z",
    occasion: "acceptance fixture",
    rating: 4,
    feedback: "synthetic history row",
  });
  const beforeEdit = await ownedSnapshot(owner, String(outfit.id));
  const baseOutfit = (beforeEdit.outfits as Row[])[0];
  if (!baseOutfit || typeof baseOutfit.updated_at !== "string") {
    throw new Error("Owner outfit snapshot or optimistic-lock token unavailable.");
  }

  stage = "successful edit";
  const success = await edit(
    owner,
    String(outfit.id),
    baseOutfit.updated_at,
    "After edit",
    garments.map((garment) => String(garment.id)),
  );
  if (!success.ok) throw new Error(`Owner outfit edit failed (HTTP ${success.status}).`);
  const saved = await success.json() as Row;
  assertEquals(saved.id, outfit.id, "edit keeps the outfit's durable ID");
  assertEquals(saved.name, "After edit");
  const afterEdit = await ownedSnapshot(owner, String(outfit.id));
  assertEquals((afterEdit.outfits as Row[]).length, 1);
  assertEquals(
    (afterEdit.items as Row[]).map((row) => row.closet_item_id),
    garments.map((row) => row.id),
  );
  assertEquals((afterEdit.wears as Row[]).map((row) => row.id), [wear.id]);
  assertEquals((afterEdit.wears as Row[])[0]?.outfit_id, outfit.id);
  assertEquals((afterEdit.wears as Row[])[0]?.worn_at, wear.worn_at);

  stage = "stale edit request";
  await writeReport();
  const stale = await edit(
    owner,
    String(outfit.id),
    baseOutfit.updated_at,
    "Stale edit should fail",
    [String(garments[0].id)],
  );
  stage = `stale edit response HTTP ${stale.status}`;
  await writeReport();
  if (stale.ok) throw new Error("Stale optimistic-lock token was accepted.");
  stage = "stale edit snapshot read";
  await writeReport();
  const afterStale = await ownedSnapshot(owner, String(outfit.id));
  assertEquals(
    afterStale,
    afterEdit,
    "stale edit leaves outfit, items, and wear history byte-identical",
  );

  stage = "peer item denial";
  const peerItemAttempt = await edit(
    owner,
    String(outfit.id),
    String((afterEdit.outfits as Row[])[0]?.updated_at),
    "Peer item attempt",
    [String(peerGarment.id)],
  );
  if (peerItemAttempt.ok) throw new Error("Peer-owned closet item was accepted.");
  const afterPeerItem = await ownedSnapshot(owner, String(outfit.id));
  assertEquals(afterPeerItem, afterEdit, "peer-item denial leaves all owner rows unchanged");

  stage = "peer outfit denial";
  const peerOutfitAttempt = await edit(
    owner,
    String(peerOutfit.id),
    baseOutfit.updated_at,
    "Peer outfit attempt",
    [String(garments[0].id)],
  );
  if (peerOutfitAttempt.status !== 404) {
    throw new Error(
      `Peer-owned outfit should be hidden as HTTP 404; got ${peerOutfitAttempt.status}.`,
    );
  }
  const peerVisibility = await rows("outfits", owner, `select=id&id=eq.${peerOutfit.id}`);
  assertEquals(peerVisibility.length, 0, "owner cannot read the peer outfit through RLS");

  results.owner_edit = {
    status: success.status,
    owner_id: owner.id,
    outfit_id: outfit.id,
    item_ids: garments.map((row) => row.id),
    retained_wear_id: wear.id,
    retained_worn_at: wear.worn_at,
  };
  results.care_instructions = {
    set_status: careSet.status,
    explicit_null_status: careClear.status,
    peer_write_rows: peerCareRows.length,
    remains_null_after_peer_write: careAfterPeer[0]?.care_instructions === null,
  };
  results.stale_token = { rejected: true, status: stale.status, unchanged: true };
  results.peer_item = { rejected: true, status: peerItemAttempt.status, unchanged: true };
  results.peer_outfit = {
    rejected: true,
    status: peerOutfitAttempt.status,
    invisible_to_owner: peerVisibility.length === 0,
  };
  stage = "all acceptance assertions passed";
} catch (error) {
  runFailure = error instanceof Error ? error.message : "unknown acceptance failure";
} finally {
  for (const account of accounts.reverse()) {
    if (account.deleted) continue;
    try {
      await deleteAccount(account);
    } catch {
      cleanupErrors.push(account.id);
    }
  }
  await writeReport();
}

console.log(JSON.stringify({ results, failure: runFailure, cleanup_errors: cleanupErrors }));
if (cleanupErrors.length) {
  throw new Error(
    `Normal account cleanup failed for synthetic fixture IDs: ${cleanupErrors.join(", ")}`,
  );
}
if (runFailure) throw new Error(runFailure);
