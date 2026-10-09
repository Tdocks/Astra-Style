import { assert, assertEquals } from "@std/assert";

// One-shot live acceptance for the server-enforced entitlement and generation limits.
// All rows are synthetic and caller-owned; no photos or storage are involved.
const projectRef = "anutsdzbxycaavmmkewo";
const baseURL = `https://${projectRef}.supabase.co`;
assertEquals(Deno.env.get("ASTRA_RUN_ENTITLEMENT_LIMITS_ACCEPTANCE"), "1");
const keyFile = Deno.args[0];
if (!keyFile) throw new Error("Pass the protected Supabase CLI key JSON path.");
const keys = JSON.parse(await Deno.readTextFile(keyFile)) as Array<Record<string, unknown>>;
const keyValue = keys.find((key) => key.type === "publishable")?.api_key;
if (typeof keyValue !== "string") throw new Error("Publishable API key unavailable.");
const publishableKey: string = keyValue;
const reportPath = Deno.args[1];

type Row = Record<string, unknown>;
type Account = { id: string; token: string; deleted: boolean };
const result: Row = {};
let failure: string | null = null;
let account: Account | null = null;

function headers(token?: string): Headers {
  const value = new Headers({ apikey: publishableKey, "Content-Type": "application/json" });
  if (token) value.set("Authorization", `Bearer ${token}`);
  return value;
}

async function json(response: Response): Promise<Row> {
  try {
    const value = await response.json();
    return value && typeof value === "object" ? value as Row : {};
  } catch {
    return {};
  }
}

async function request(path: string, token: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${baseURL}${path}`, {
    ...init,
    headers: { ...Object.fromEntries(headers(token)), ...init.headers },
    signal: init.signal ?? AbortSignal.timeout(75_000),
  });
}

async function writeReport(): Promise<void> {
  if (!reportPath) return;
  await Deno.writeTextFile(reportPath, JSON.stringify({ result, failure }, null, 2), {
    mode: 0o600,
  });
}

async function insert<T extends Row>(table: string, owner: Account, value: Row): Promise<T> {
  const response = await request(`/rest/v1/${table}?select=*`, owner.token, {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify(value),
  });
  const payload = await response.json().catch(() => []);
  if (!response.ok || !Array.isArray(payload) || payload.length !== 1) {
    const error = payload && typeof payload === "object" ? payload as Row : {};
    const code = typeof error.code === "string" ? error.code : "unknown";
    throw new Error(`${table} fixture insert failed (HTTP ${response.status}, ${code}).`);
  }
  return payload[0] as T;
}

async function readRows(owner: Account, path: string): Promise<Row[]> {
  const response = await request(path, owner.token);
  if (!response.ok) throw new Error(`Caller-scoped read failed (HTTP ${response.status}).`);
  const payload = await response.json();
  return Array.isArray(payload) ? payload as Row[] : [];
}

try {
  const signup = await fetch(`${baseURL}/auth/v1/signup`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({}),
    signal: AbortSignal.timeout(20_000),
  });
  const auth = await json(signup);
  const user = auth.user as Row | undefined;
  if (!signup.ok || typeof user?.id !== "string" || typeof auth.access_token !== "string") {
    throw new Error(`Disposable owner creation failed (HTTP ${signup.status}).`);
  }
  account = { id: user.id, token: auth.access_token, deleted: false };
  result.owner_id = account.id;
  const garments: Row[] = [];
  const garment = (index: number): Row => {
    const categories = ["top", "bottom", "shoes", "outerwear", "accessory"];
    return {
      user_id: account!.id,
      name: `Entitlement acceptance item ${index}`,
      category: categories[index % categories.length],
      primary_color: "navy",
      material: [{ fiber: "cotton", percentage: 100 }],
      fit: "regular",
      condition: "good",
      seasonality: ["spring", "summer", "fall", "winter"],
      formality_score: 50,
      warmth_score: 40,
      laundry_state: "clean",
      availability_state: "available",
    };
  };
  for (let index = 0; index < 10; index++) {
    garments.push(await insert("closet_items", account, garment(index)));
  }
  const cappedInsert = async (): Promise<void> => {
    const response = await request("/rest/v1/closet_items", account!.token, {
      method: "POST",
      body: JSON.stringify(garment(11)),
    });
    const error = await json(response);
    assertEquals(response.status, 409);
    assertEquals(error.code, "PT409");
    assertEquals(error.message, "closet_item_limit_reached");
    const details = JSON.parse(String(error.details)) as Row;
    assertEquals(details.limit, 10);
    assertEquals(details.active_count, 10);
  };
  await cappedInsert();
  const archivedID = String(garments[0]!.id);
  const archive = await request(`/rest/v1/closet_items?id=eq.${archivedID}`, account.token, {
    method: "PATCH",
    body: JSON.stringify({ archived_at: new Date().toISOString() }),
  });
  assert(archive.ok);
  garments.push(await insert("closet_items", account, garment(10)));
  const restore = await request(`/rest/v1/closet_items?id=eq.${archivedID}`, account.token, {
    method: "PATCH",
    body: JSON.stringify({ archived_at: null }),
  });
  assertEquals(restore.status, 409);
  const active = await readRows(account, "/rest/v1/closet_items?select=id&archived_at=is.null");
  assertEquals(active.length, 10);
  result.closet = { active_count: active.length, insert_limit: true, restore_limit: true };
  const forbidden = await request(
    "/rest/v1/outfit_generation_reservations?select=id",
    account.token,
  );
  assertEquals(forbidden.status, 403);
  result.client_quota_ledger_denied = true;
  const forbiddenRPC = await request("/rest/v1/rpc/reserve_outfit_generation", account.token, {
    method: "POST",
    body: JSON.stringify({
      p_user_id: account.id,
      p_request_id: crypto.randomUUID(),
      p_fingerprint: "a".repeat(64),
      p_now: new Date().toISOString(),
    }),
  });
  assertEquals(forbiddenRPC.status, 403);
  result.client_quota_rpc_denied = true;
  const directThread = await request("/rest/v1/kyra_threads", account.token, {
    method: "POST",
    body: JSON.stringify({ user_id: account.id, title: "Forbidden direct thread" }),
  });
  assertEquals(directThread.status, 403);
  result.client_thread_insert_denied = true;

  const generationBody = { desired_count: 3, natural_language_request: "A casual everyday outfit" };
  const firstID = crypto.randomUUID();
  const generate = async (id: string, body: Row = generationBody): Promise<Response> => {
    return await request("/functions/v1/outfits/generate", account!.token, {
      method: "POST",
      body: JSON.stringify({
        request_id: id,
        client_version: "entitlement-live-acceptance/1",
        body,
      }),
    });
  };
  const first = await generate(firstID);
  const firstPayload = await json(first);
  assertEquals(first.status, 200);
  assert(Array.isArray(firstPayload.data) && firstPayload.data.length > 0);
  for (let index = 1; index < 5; index++) {
    const response = await generate(crypto.randomUUID());
    const payload = await json(response);
    assertEquals(response.status, 200);
    assert(Array.isArray(payload.data) && payload.data.length > 0);
  }
  const exhausted = await generate(crypto.randomUUID());
  const exhaustedPayload = await json(exhausted);
  assertEquals(exhausted.status, 429);
  const error = exhaustedPayload.error as Row;
  assertEquals(error.category, "subscription_limit_reached");
  const details = error.details as Row;
  assertEquals(details.limit, "outfit_generation_daily");
  assertEquals(details.limit_count, 5);
  assertEquals(details.remaining, 0);
  assert(typeof details.resets_at === "string");
  assertEquals(exhausted.headers.get("Retry-After"), null);

  // The exhausted builder path must stop before creating a thread or using a provider.
  const kyra = await request("/functions/v1/kyra/respond", account.token, {
    method: "POST",
    body: JSON.stringify({
      request_id: crypto.randomUUID(),
      client_version: "entitlement-live-acceptance/1",
      body: {
        thread_id: null,
        text: "Finish this outfit using my closet",
        attachments: [],
        locked_closet_item_ids: [String(garments[1]!.id)],
        outfit_builder_completion: true,
        weather_snapshot: null,
        schedule_snapshot: null,
      },
    }),
  });
  const kyraPayload = await json(kyra);
  assertEquals(kyra.status, 429);
  const kyraError = kyraPayload.error as Row;
  assertEquals(kyraError.category, "subscription_limit_reached");
  assertEquals((kyraError.details as Row).limit, "outfit_generation_daily");
  const threads = await readRows(account, "/rest/v1/kyra_threads?select=id");
  assertEquals(threads.length, 0);
  result.kyra_builder_stopped_before_thread = true;
  const replay = await generate(firstID);
  const replayPayload = await json(replay);
  assertEquals(replay.status, 200);
  assertEquals(replayPayload.data, firstPayload.data);
  const changed = await generate(firstID, { ...generationBody, desired_count: 1 });
  assert(!changed.ok && changed.status !== 429);
  result.generation = {
    successful_requests: 5,
    sixth_blocked: true,
    replay_preserved: true,
    changed_payload_rejected: true,
    quota: details,
  };
} catch (error) {
  failure = error instanceof Error ? error.message : "unknown acceptance failure";
} finally {
  if (account) {
    try {
      const deletion = await request("/functions/v1/account", account.token, {
        method: "DELETE",
        body: JSON.stringify({}),
      });
      const receipt = await json(deletion);
      if (!deletion.ok) {
        result.cleanup_error = `Normal account cleanup failed (HTTP ${deletion.status}).`;
      } else {
        account.deleted = true;
        result.cleanup = {
          status: deletion.status,
          deletion_id: receipt.deletion_id ??
            (receipt.data as Row | undefined)?.deletion_id ?? null,
        };
      }
    } catch (error) {
      result.cleanup_error = error instanceof Error ? error.message : "cleanup failed";
    }
  }
  await writeReport();
}

console.log(JSON.stringify({ result, failure }));
if (result.cleanup_error) throw new Error("Synthetic account cleanup failed.");
if (failure) throw new Error(failure);
