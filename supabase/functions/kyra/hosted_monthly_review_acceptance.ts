import { assert, assertEquals } from "@std/assert";

// One-shot owner-scoped Monthly Review facts acceptance. This does not call
// Kyra or any provider: it verifies that the data sources the native snapshot
// reads can be created and read by one disposable authenticated owner.
const projectRef = "anutsdzbxycaavmmkewo";
const baseURL = `https://${projectRef}.supabase.co`;
assertEquals(Deno.env.get("ASTRA_RUN_MONTHLY_REVIEW_ACCEPTANCE"), "1");
const keyFile = Deno.args[0];
if (!keyFile) throw new Error("Pass the protected Supabase CLI key JSON path.");
const keys = JSON.parse(await Deno.readTextFile(keyFile)) as Array<Record<string, unknown>>;
const keyValue = keys.find((key) => key.type === "publishable")?.api_key;
if (typeof keyValue !== "string") throw new Error("Publishable API key unavailable.");
const publishableKey: string = keyValue;
const reportPath = Deno.args[1];

type Row = Record<string, unknown>;
type Account = { id: string; token: string };
const result: Row = {
  interval: {
    timezone: "America/New_York",
    start_inclusive: "2026-09-01T04:00:00.000Z",
    end_exclusive: "2026-10-01T04:00:00.000Z",
  },
  provider_calls: 0,
};
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
    signal: init.signal ?? AbortSignal.timeout(30_000),
  });
}

async function writeReport(): Promise<void> {
  if (!reportPath) return;
  await Deno.writeTextFile(reportPath, JSON.stringify({ result, failure }, null, 2), {
    mode: 0o600,
  });
}

async function insert(table: string, owner: Account, value: Row): Promise<Row> {
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
  return payload[0] as Row;
}

async function readRows(owner: Account, path: string): Promise<Row[]> {
  const response = await request(path, owner.token);
  if (!response.ok) {
    throw new Error(`Owner-scoped ${path.split("?")[0]} read failed (HTTP ${response.status}).`);
  }
  const payload = await response.json();
  return Array.isArray(payload) ? payload as Row[] : [];
}

function iso(value: string): string {
  return encodeURIComponent(value);
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
  account = { id: user.id, token: auth.access_token };
  const ownerID = account.id;
  result.owner_id = ownerID;
  result.auth_is_anonymous = user.is_anonymous === true;

  const candidates = await readRows(
    account,
    "/rest/v1/product_candidates?select=id,name&order=id.asc&limit=2",
  );
  if (candidates.length < 2) {
    throw new Error(
      "At least two readable shared catalog candidates are needed for purchase boundary coverage.",
    );
  }
  const insideCandidate = candidates[0]!;
  const boundaryCandidate = candidates[1]!;
  const start = "2026-09-01T04:00:00.000Z";
  const inside = "2026-09-15T16:00:00.000Z";
  const nearEnd = "2026-10-01T03:59:59.999Z";
  const end = "2026-10-01T04:00:00.000Z";
  const beforeStart = "2026-09-01T03:59:59.999Z";

  const closetRows = await Promise.all([
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance September navy wool coat",
      category: "outerwear",
      subcategory: "wool coat",
      primary_color: "navy",
      condition: "good",
      purchase_date: "2026-09-01",
      price_paid: 120,
      currency: "USD",
      created_at: start,
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance September olive overshirt",
      category: "top",
      subcategory: "overshirt",
      primary_color: "olive",
      condition: "good",
      purchase_date: "2026-09-15",
      price_paid: 60,
      currency: "USD",
      created_at: inside,
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance archived September knit",
      category: "top",
      subcategory: "knit",
      primary_color: "charcoal",
      condition: "good",
      purchase_date: "2026-09-20",
      price_paid: 30,
      currency: "USD",
      created_at: "2026-09-20T12:00:00.000Z",
      archived_at: "2026-09-25T12:00:00.000Z",
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance October boundary tee",
      category: "top",
      subcategory: "tee",
      primary_color: "white",
      condition: "good",
      purchase_date: "2026-10-01",
      price_paid: 999,
      currency: "USD",
      created_at: end,
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance prior-month brown derbies",
      category: "shoes",
      subcategory: "derby",
      primary_color: "brown",
      condition: "good",
      purchase_date: "2026-08-20",
      price_paid: 900,
      currency: "USD",
      created_at: "2026-08-20T12:00:00.000Z",
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance underused navy knit",
      category: "top",
      subcategory: "knit",
      primary_color: "navy",
      condition: "good",
      created_at: "2026-08-10T12:00:00.000Z",
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance grey chinos",
      category: "bottom",
      subcategory: "chinos",
      primary_color: "grey",
      condition: "good",
      created_at: "2026-08-10T12:00:00.000Z",
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance olive trousers",
      category: "bottom",
      subcategory: "trousers",
      primary_color: "olive",
      condition: "good",
      created_at: "2026-08-10T12:00:00.000Z",
    }),
    insert("closet_items", account, {
      user_id: account.id,
      name: "Acceptance white sneakers",
      category: "shoes",
      subcategory: "sneakers",
      primary_color: "white",
      condition: "good",
      created_at: "2026-08-10T12:00:00.000Z",
    }),
  ]);
  const byName = new Map(closetRows.map((row) => [String(row.name), String(row.id)]));
  result.closet_item_ids = closetRows.map((row) => row.id);

  const outfitOne = await insert("outfits", account, {
    user_id: account.id,
    name: "Acceptance September outfit one",
    source: "user_created",
    created_at: "2026-08-30T12:00:00.000Z",
  });
  const outfitTwo = await insert("outfits", account, {
    user_id: account.id,
    name: "Acceptance September outfit two",
    source: "user_created",
    created_at: "2026-08-30T12:00:00.000Z",
  });
  result.outfit_ids = [outfitOne.id, outfitTwo.id];
  const outfitItemRows = [
    [outfitOne, "Acceptance underused navy knit", "top"],
    [outfitOne, "Acceptance grey chinos", "bottom"],
    [outfitOne, "Acceptance prior-month brown derbies", "shoes"],
    [outfitTwo, "Acceptance September olive overshirt", "top"],
    [outfitTwo, "Acceptance olive trousers", "bottom"],
    [outfitTwo, "Acceptance white sneakers", "shoes"],
  ] as const;
  for (const [outfit, itemName, role] of outfitItemRows) {
    await insert("outfit_items", account, {
      outfit_id: outfit.id,
      user_id: account.id,
      closet_item_id: byName.get(itemName),
      role,
      sort_order: 0,
    });
  }

  const wearRows = await Promise.all([
    insert("outfit_wears", account, {
      user_id: account.id,
      outfit_id: outfitOne.id,
      worn_at: start,
      occasion: "acceptance start boundary",
    }),
    insert("outfit_wears", account, {
      user_id: account.id,
      outfit_id: outfitOne.id,
      worn_at: inside,
      occasion: "acceptance midmonth",
    }),
    insert("outfit_wears", account, {
      user_id: account.id,
      outfit_id: outfitTwo.id,
      worn_at: nearEnd,
      occasion: "acceptance before end boundary",
    }),
    insert("outfit_wears", account, {
      user_id: account.id,
      outfit_id: outfitTwo.id,
      worn_at: end,
      occasion: "acceptance end boundary",
    }),
    insert("outfit_wears", account, {
      user_id: account.id,
      outfit_id: outfitOne.id,
      worn_at: beforeStart,
      occasion: "acceptance before start boundary",
    }),
  ]);
  result.wear_ids = wearRows.map((row) => row.id);

  const purchases = await Promise.all([
    insert("wishlist_items", account, {
      user_id: account.id,
      product_candidate_id: insideCandidate.id,
      purchased_at: inside,
    }),
    insert("wishlist_items", account, {
      user_id: account.id,
      product_candidate_id: boundaryCandidate.id,
      purchased_at: end,
    }),
  ]);
  result.wishlist_row_ids = purchases.map((row) => row.id);
  const evaluation = await insert("user_product_evaluations", account, {
    user_id: account.id,
    product_candidate_id: insideCandidate.id,
    compatibility_score: 84,
    redundancy_score: 12,
    outfits_unlocked: 5,
    expected_cost_per_wear: 18,
    verdict: "consider",
    reasoning: "Acceptance fixture evaluation only.",
    created_at: inside,
  });
  result.evaluation_id = evaluation.id;

  const ownerFilter = `user_id=eq.${encodeURIComponent(account.id)}`;
  const [closet, wears, ownedPurchases, evaluations] = await Promise.all([
    readRows(
      account,
      `/rest/v1/closet_items?select=id,user_id,name,created_at,purchase_date,price_paid,currency,wear_count,archived_at&${ownerFilter}`,
    ),
    readRows(
      account,
      `/rest/v1/outfit_wears?select=id,user_id,outfit_id,worn_at&${ownerFilter}&worn_at=gte.${
        iso(start)
      }&worn_at=lt.${iso(end)}&order=worn_at.asc`,
    ),
    readRows(
      account,
      `/rest/v1/wishlist_items?select=id,user_id,product_candidate_id,purchased_at&${ownerFilter}&purchased_at=gte.${
        iso(start)
      }&purchased_at=lt.${iso(end)}`,
    ),
    readRows(
      account,
      `/rest/v1/user_product_evaluations?select=id,user_id,product_candidate_id,compatibility_score,outfits_unlocked,verdict,created_at&${ownerFilter}&product_candidate_id=eq.${
        encodeURIComponent(String(insideCandidate.id))
      }`,
    ),
  ]);
  assert(closet.every((row) => row.user_id === ownerID));
  assert(wears.every((row) => row.user_id === ownerID));
  assert(ownedPurchases.every((row) => row.user_id === ownerID));
  assert(evaluations.every((row) => row.user_id === ownerID));

  const monthStart = Date.parse(start);
  const monthEnd = Date.parse(end);
  const newClosetItems = closet.filter((row) => {
    const createdAt = Date.parse(String(row.created_at));
    return createdAt >= monthStart && createdAt < monthEnd;
  });
  assertEquals(
    newClosetItems.length,
    3,
    "new count includes archived history and excludes end boundary",
  );
  assert(newClosetItems.some((row) => row.name === "Acceptance archived September knit"));
  assert(!newClosetItems.some((row) => row.name === "Acceptance October boundary tee"));

  const septemberSpendRows = closet.filter((row) => {
    const date = row.purchase_date;
    return typeof date === "string" && date >= "2026-09-01" && date < "2026-10-01" &&
      row.price_paid !== null;
  });
  const spend = septemberSpendRows.reduce((sum, row) => sum + Number(row.price_paid), 0);
  assertEquals(spend, 210, "spend includes archived September item and excludes other months");
  assert(septemberSpendRows.some((row) => row.name === "Acceptance archived September knit"));

  assertEquals(
    wears.length,
    3,
    "wears include start and near-end, exclude both outside boundaries",
  );
  const uniqueWornOutfitIDs = new Set(wears.map((row) => row.outfit_id));
  assertEquals(uniqueWornOutfitIDs.size, 2);
  assertEquals(ownedPurchases.length, 1, "purchase at next-month start is excluded");
  assertEquals(ownedPurchases[0]?.product_candidate_id, insideCandidate.id);
  assert(evaluations.some((row) => row.id === evaluation.id));
  assertEquals(evaluations[0]?.outfits_unlocked, 5);
  result.owner_scoped_snapshot_facts = {
    closet_rows_visible: closet.length,
    new_items_including_archived: newClosetItems.map((row) => row.name),
    september_spend: spend,
    wear_count: wears.length,
    unique_outfit_count: uniqueWornOutfitIDs.size,
    september_purchase_candidate_id: ownedPurchases[0]?.product_candidate_id,
    evaluation_id: evaluation.id,
    evaluation_outfits_unlocked: evaluations[0]?.outfits_unlocked,
    month_end_boundary_excluded: true,
    month_start_boundary_included: true,
    rows_read_with_owner_jwt: true,
  };
  result.catalog_candidates = [insideCandidate, boundaryCandidate];
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
