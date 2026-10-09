import { assert, assertEquals } from "@std/assert";

// One-shot live acceptance for the native Outfit Builder → Kyra contract.
// All rows are synthetic and caller-owned; no photos or storage are involved.
const projectRef = "anutsdzbxycaavmmkewo";
const baseURL = `https://${projectRef}.supabase.co`;
assertEquals(Deno.env.get("ASTRA_RUN_BUILDER_COMPLETION_ACCEPTANCE"), "1");
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
  const garments = await Promise.all([
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance locked navy merino polo",
      category: "top",
      subcategory: "polo",
      primary_color: "navy",
      material: [{ fiber: "merino wool", percentage: 100 }],
      fit: "regular",
      condition: "good",
      seasonality: ["fall", "winter"],
      formality_score: 60,
      warmth_score: 45,
      laundry_state: "clean",
      availability_state: "available",
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance white oxford shirt",
      category: "top",
      subcategory: "oxford shirt",
      primary_color: "white",
      material: [{ fiber: "cotton", percentage: 100 }],
      fit: "regular",
      condition: "good",
      seasonality: ["spring", "fall"],
      formality_score: 70,
      warmth_score: 25,
      laundry_state: "clean",
      availability_state: "available",
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance charcoal chinos",
      category: "bottom",
      subcategory: "chinos",
      primary_color: "charcoal",
      material: [{ fiber: "cotton", percentage: 98 }, { fiber: "elastane", percentage: 2 }],
      fit: "regular",
      condition: "good",
      seasonality: ["spring", "fall", "winter"],
      formality_score: 55,
      warmth_score: 35,
      laundry_state: "clean",
      availability_state: "available",
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance olive trousers",
      category: "bottom",
      subcategory: "trousers",
      primary_color: "olive",
      material: [{ fiber: "cotton", percentage: 100 }],
      fit: "tailored",
      condition: "good",
      seasonality: ["fall"],
      formality_score: 58,
      warmth_score: 35,
      laundry_state: "clean",
      availability_state: "available",
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance dark brown derby shoes",
      category: "shoes",
      subcategory: "derby",
      primary_color: "brown",
      material: [{ fiber: "leather", percentage: 100 }],
      fit: "regular",
      condition: "good",
      seasonality: ["spring", "fall", "winter"],
      formality_score: 65,
      warmth_score: 25,
      laundry_state: "clean",
      availability_state: "available",
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance white leather low-top sneakers",
      category: "shoes",
      subcategory: "low-top sneakers",
      primary_color: "white",
      material: [{ fiber: "leather", percentage: 100 }],
      fit: "regular",
      condition: "good",
      seasonality: ["spring", "summer", "fall"],
      formality_score: 35,
      warmth_score: 15,
      laundry_state: "clean",
      availability_state: "available",
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance navy mac coat",
      category: "outerwear",
      subcategory: "mac coat",
      primary_color: "navy",
      material: [{ fiber: "cotton", percentage: 100 }],
      fit: "regular",
      condition: "good",
      seasonality: ["fall", "winter", "spring"],
      formality_score: 65,
      warmth_score: 65,
      water_resistance_score: 55,
      laundry_state: "clean",
      availability_state: "available",
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance walnut leather belt",
      category: "accessory",
      subcategory: "belt",
      primary_color: "brown",
      material: [{ fiber: "leather", percentage: 100 }],
      fit: "regular",
      condition: "good",
      seasonality: ["spring", "summer", "fall", "winter"],
      formality_score: 55,
      warmth_score: 0,
      laundry_state: "clean",
      availability_state: "available",
    }),
  ]);
  const lockedItem = garments[0]!;
  const lockedItemID = String(lockedItem.id);
  result.garment_ids = garments.map((item) => item.id);
  result.locked_item_id = lockedItemID;

  const prompt =
    "Finish this outfit using only my owned closet items. Keep these pieces exactly: " +
    `${lockedItem.name} (top). Return one complete outfit and a short reason.`;
  // One client POST only. There is intentionally no retry after timeout/error.
  const response = await request("/functions/v1/kyra/respond", account.token, {
    method: "POST",
    body: JSON.stringify({
      request_id: crypto.randomUUID(),
      client_version: "outfit-builder-live-acceptance/1",
      body: {
        thread_id: null,
        text: prompt,
        attachments: [],
        weather_snapshot: null,
        schedule_snapshot: null,
        locked_closet_item_ids: [lockedItemID],
        outfit_builder_completion: true,
      },
    }),
  });
  const envelope = await json(response);
  const data = envelope.data as Row | undefined;
  if (!response.ok || !data) {
    throw new Error(`Kyra builder completion failed (HTTP ${response.status}).`);
  }
  const structured = data.structured_payload as Row | undefined;
  const metadata = data.model_metadata as Row | undefined;
  const cards = structured?.cards;
  result.response = {
    http_status: response.status,
    thread_id: data.thread_id ?? null,
    assistant_message_id: data.id ?? null,
    model_identifier: metadata?.model_identifier ?? null,
    fallback_reason: metadata?.fallback_reason ?? null,
    provider_failure: metadata?.provider_failure ?? null,
    escalated: metadata?.escalated ?? null,
    tools_called: metadata?.tools_called ?? null,
  };
  assert(Array.isArray(cards), "structured reply must include cards");
  const card = cards.find((entry) =>
    entry && typeof entry === "object" && (entry as Row).type === "outfit"
  ) as Row | undefined;
  assert(card, "Kyra should return an outfit card");
  assert(typeof card.outfit_id === "string", "outfit card must reference the saved outfit");
  result.card = {
    outfit_id: card.outfit_id,
    reason: card.reason ?? null,
  };
  assert(
    typeof card.reason === "string" && card.reason.trim().length > 0,
    "outfit card needs a reason",
  );
  assertEquals(metadata?.fallback_reason, null, "must be a real provider response, not fallback");
  assertEquals(metadata?.provider_failure, null);
  assertEquals(metadata?.escalated, false, "acceptance should stay on one model tier");
  assert(typeof metadata?.model_identifier === "string", "provider model identifier required");
  assert(Array.isArray(metadata?.tools_called));
  assertEquals(metadata.tools_called.filter((name) => name === "create_outfit").length, 1);
  assertEquals(
    metadata.tools_called.length,
    1,
    "builder completion should need only create_outfit",
  );

  const outfitID = String(card.outfit_id);
  result.outfit_id = outfitID;
  const [outfits, outfitItems] = await Promise.all([
    readRows(
      account,
      `/rest/v1/outfits?select=id,user_id,name,description,source,compatibility_score&id=eq.${
        encodeURIComponent(outfitID)
      }`,
    ),
    readRows(
      account,
      `/rest/v1/outfit_items?select=id,user_id,outfit_id,closet_item_id,product_candidate_id,role,sort_order&outfit_id=eq.${
        encodeURIComponent(outfitID)
      }&order=sort_order.asc`,
    ),
  ]);
  assertEquals(outfits.length, 1, "the card outfit should be a persisted row");
  const outfit = outfits[0]!;
  result.persisted_outfit = {
    id: outfit.id,
    user_id: outfit.user_id,
    source: outfit.source,
    name: outfit.name,
    description: outfit.description,
  };
  result.persisted_items = outfitItems.map((item) => ({
    closet_item_id: item.closet_item_id,
    role: item.role,
    user_id: item.user_id,
    product_candidate_id: item.product_candidate_id,
  }));
  assertEquals(outfit.user_id, account.id);
  assertEquals(outfit.source, "kyra_suggested");
  assert(typeof outfit.name === "string" && outfit.name.length > 0);
  assert(typeof outfit.description === "string" && outfit.description.trim().length > 0);
  assert(outfitItems.length >= 3, "complete outfit should cover the three required roles");
  assert(outfitItems.every((item) => item.user_id === account!.id));
  assert(outfitItems.every((item) => item.outfit_id === outfitID));
  assert(outfitItems.every((item) => item.product_candidate_id === null));
  const persistedClosetIDs = outfitItems.map((item) => item.closet_item_id);
  assert(
    persistedClosetIDs.includes(lockedItemID),
    "saved outfit must preserve the locked closet ID",
  );
  assert(persistedClosetIDs.every((id) => garments.some((item) => item.id === id)));
  const roles = new Set(outfitItems.map((item) => item.role));
  assert(roles.has("top") && roles.has("bottom") && roles.has("shoes"));

  result.acceptance = {
    http_status: response.status,
    owner_id: account.id,
    thread_id: data.thread_id,
    assistant_message_id: data.id,
    model_identifier: metadata.model_identifier,
    escalated: metadata.escalated,
    tools_called: metadata.tools_called,
    outfit_id: outfitID,
    outfit_name: outfit.name,
    saved_reason: outfit.description,
    card_reason: card.reason,
    locked_item_id: lockedItemID,
    persisted_item_ids: persistedClosetIDs,
    persisted_roles: outfitItems.map((item) => item.role),
    persisted_owned_outfit_and_items: true,
    persisted_reason_matches_card_reason: outfit.description === card.reason,
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
