import { assert, assertEquals } from "@std/assert";

// One-owner connected backend journey. It intentionally makes one Kyra
// request (the builder completion) and creates no photos or Storage objects.
const projectRef = "anutsdzbxycaavmmkewo";
const baseURL = `https://${projectRef}.supabase.co`;
assertEquals(Deno.env.get("ASTRA_RUN_CONNECTED_LIFECYCLE_ACCEPTANCE"), "1");
const keyFile = Deno.args[0];
if (!keyFile) throw new Error("Pass the protected Supabase CLI key JSON path.");
const keyRows = JSON.parse(await Deno.readTextFile(keyFile)) as Array<Record<string, unknown>>;
const key = keyRows.find((row) => row.type === "publishable")?.api_key;
if (typeof key !== "string") throw new Error("Publishable API key unavailable.");
const publishableKey: string = key;
const reportArgument = Deno.args[1];
if (!reportArgument) throw new Error("Pass a protected acceptance report path.");
const reportPath: string = reportArgument;

type Row = Record<string, unknown>;
type Account = { id: string; token: string; deleted: boolean };
const result: Row = {
  top_level_kyra_requests: 0,
  provider_image_requests: 0,
  stage: "starting",
};
let failure: string | null = null;
let account: Account | null = null;

async function writeReport(): Promise<void> {
  await Deno.writeTextFile(reportPath, JSON.stringify({ result, failure }, null, 2) + "\n", {
    create: true,
    mode: 0o600,
  });
  await Deno.chmod(reportPath, 0o600);
}

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

async function request(path: string, owner: Account, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${baseURL}${path}`, {
    ...init,
    headers: { ...Object.fromEntries(headers(owner.token)), ...init.headers },
    signal: init.signal ?? AbortSignal.timeout(75_000),
  });
}

async function insert(table: string, owner: Account, values: Row): Promise<Row> {
  const response = await request(`/rest/v1/${table}?select=*`, owner, {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify(values),
  });
  const payload = await response.json().catch(() => []);
  if (!response.ok || !Array.isArray(payload) || payload.length !== 1) {
    const body = payload && typeof payload === "object" ? payload as Row : {};
    const code = typeof body.code === "string" ? body.code : "unknown";
    throw new Error(`${table} fixture write failed (HTTP ${response.status}, ${code}).`);
  }
  return payload[0] as Row;
}

async function rows(owner: Account, path: string): Promise<Row[]> {
  const response = await request(path, owner);
  if (!response.ok) {
    throw new Error(`Owner read failed for ${path.split("?")[0]} (HTTP ${response.status}).`);
  }
  const payload = await response.json();
  return Array.isArray(payload) ? payload as Row[] : [];
}

function elapsedMonthInterval(now: Date): { start: Date; end: Date } {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    timeZoneName: "shortOffset",
  });
  const offsetMinutesAtNYMonthStart = (year: number, month: number): number => {
    const utcMonthStart = new Date(Date.UTC(year, month, 1));
    const zoneName = formatter.formatToParts(utcMonthStart).find((part) =>
      part.type === "timeZoneName"
    )?.value;
    const match = zoneName?.match(/^GMT([+-])(\d{1,2})(?::(\d{2}))?$/);
    if (!match) throw new Error("Could not determine the review month timezone offset.");
    const sign = match[1] === "-" ? -1 : 1;
    return sign * (Number(match[2]) * 60 + Number(match[3] ?? "0"));
  };
  const localMidnight = (year: number, month: number): Date => {
    const offset = offsetMinutesAtNYMonthStart(year, month);
    return new Date(Date.UTC(year, month, 1) - offset * 60_000);
  };
  const currentNY = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    year: "numeric",
    month: "numeric",
  }).formatToParts(now);
  const year = Number(currentNY.find((part) => part.type === "year")?.value);
  const month = Number(currentNY.find((part) => part.type === "month")?.value) - 1;
  const end = localMidnight(year, month);
  const priorMonth = new Date(Date.UTC(year, month - 1, 1));
  return { start: localMidnight(priorMonth.getUTCFullYear(), priorMonth.getUTCMonth()), end };
}

async function completeOnboarding(owner: Account): Promise<void> {
  const response = await request("/functions/v1/profile/complete-onboarding", owner, {
    method: "POST",
    body: JSON.stringify({
      request_id: crypto.randomUUID(),
      client_version: "connected-lifecycle-acceptance/1",
      body: {
        wardrobe_graph: "menswear_3_role",
        style_goals: [],
        style_profile: {
          primary_identity: "quiet_luxury",
          secondary_identities: [],
          style_goals: [],
          preferred_fit: "tailored",
          preference_vector: {
            version: 1,
            comparisons_answered: 0,
            comparisons_offered: 0,
            dimensions: {},
          },
        },
        body_profile: {},
        lifestyle_profile: {},
        quiz_answers: [],
      },
    }),
  });
  if (!response.ok) throw new Error(`Synthetic onboarding failed (HTTP ${response.status}).`);
  const [profile, styleProfile] = await Promise.all([
    rows(
      owner,
      `/rest/v1/profiles?select=id,wardrobe_graph,onboarding_completed_at&id=eq.${owner.id}`,
    ),
    rows(owner, `/rest/v1/style_profiles?select=user_id,preference_vector&user_id=eq.${owner.id}`),
  ]);
  assertEquals(profile.length, 1);
  assertEquals(profile[0]?.wardrobe_graph, "menswear_3_role");
  assert(
    typeof profile[0]?.onboarding_completed_at === "string" &&
      profile[0].onboarding_completed_at.length > 0,
    "onboarding completion timestamp must be persisted",
  );
  assertEquals(styleProfile.length, 1);
  assertEquals(styleProfile[0]?.user_id, owner.id);
  result.onboarding = {
    profile_rows: 1,
    style_profile_rows: 1,
    preference_answers: 0,
    completed_at_verified: true,
  };
}

async function seedOutfit(
  owner: Account,
  name: string,
  createdAt: string,
  items: Array<{ id: string; role: string }>,
): Promise<Row> {
  const outfit = await insert("outfits", owner, {
    user_id: owner.id,
    name,
    description: "Synthetic owner-created acceptance look.",
    source: "user_created",
    created_at: createdAt,
  });
  for (const [sortOrder, item] of items.entries()) {
    await insert("outfit_items", owner, {
      user_id: owner.id,
      outfit_id: outfit.id,
      closet_item_id: item.id,
      role: item.role,
      sort_order: sortOrder,
    });
  }
  return outfit;
}

async function deleteNormally(owner: Account): Promise<void> {
  const response = await request("/functions/v1/account", owner, {
    method: "DELETE",
    body: JSON.stringify({}),
  });
  const body = await json(response);
  if (!response.ok) {
    result.cleanup_error = `Normal account deletion failed (HTTP ${response.status}).`;
    return;
  }
  owner.deleted = true;
  result.cleanup = {
    status: response.status,
    deletion_id: body.deletion_id ?? (body.data as Row | undefined)?.deletion_id ?? null,
  };
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
    throw new Error(`Disposable anonymous account creation failed (HTTP ${signup.status}).`);
  }
  assertEquals(user.is_anonymous, true, "fixture must be a disposable anonymous account");
  account = { id: user.id, token: auth.access_token, deleted: false };
  result.owner_id = account.id;
  result.auth_is_anonymous = user.is_anonymous === true;
  result.cleanup = { status: "pending", method: "normal account deletion" };
  result.stage = "account_created";
  await writeReport();
  await completeOnboarding(account);
  assert(
    result.onboarding && (result.onboarding as Row).completed_at_verified === true,
    "onboarding must persist a completion timestamp",
  );

  const { start: elapsedStart, end: elapsedEnd } = elapsedMonthInterval(new Date());
  result.elapsed_month_interval = {
    start_inclusive: elapsedStart.toISOString(),
    end_exclusive: elapsedEnd.toISOString(),
    timezone: "America/New_York",
  };
  const startISO = encodeURIComponent(elapsedStart.toISOString());
  const midpoint = new Date(
    elapsedStart.getTime() + (elapsedEnd.getTime() - elapsedStart.getTime()) / 2,
  );
  const createdAt = midpoint.toISOString();
  const itemValues = [
    {
      name: "Acceptance navy merino polo",
      category: "top",
      subcategory: "polo",
      primary_color: "navy",
      material: [{ fiber: "merino wool", percentage: 100 }],
      formality_score: 60,
      warmth_score: 45,
    },
    {
      name: "Acceptance white oxford shirt",
      category: "top",
      subcategory: "oxford shirt",
      primary_color: "white",
      material: [{ fiber: "cotton", percentage: 100 }],
      formality_score: 70,
      warmth_score: 25,
    },
    {
      name: "Acceptance charcoal chinos",
      category: "bottom",
      subcategory: "chinos",
      primary_color: "charcoal",
      material: [{ fiber: "cotton", percentage: 98 }, { fiber: "elastane", percentage: 2 }],
      formality_score: 55,
      warmth_score: 35,
    },
    {
      name: "Acceptance olive trousers",
      category: "bottom",
      subcategory: "trousers",
      primary_color: "olive",
      material: [{ fiber: "cotton", percentage: 100 }],
      formality_score: 58,
      warmth_score: 35,
    },
    {
      name: "Acceptance brown derby shoes",
      category: "shoes",
      subcategory: "derby",
      primary_color: "brown",
      material: [{ fiber: "leather", percentage: 100 }],
      formality_score: 65,
      warmth_score: 25,
    },
  ];
  const garments = await Promise.all(
    itemValues.map((item, index) =>
      insert("closet_items", account!, {
        user_id: account!.id,
        ...item,
        fit: "regular",
        condition: "good",
        seasonality: ["spring", "fall", "winter"],
        laundry_state: "clean",
        availability_state: "available",
        created_at: new Date(elapsedStart.getTime() + index * 3_600_000).toISOString(),
        ...(index === 0
          ? { purchase_date: createdAt.slice(0, 10), price_paid: 120, currency: "USD" }
          : {}),
      })
    ),
  );
  const garmentIDs = garments.map((garment) => String(garment.id));
  result.garment_ids = garmentIDs;
  assertEquals(garments.length, 5);

  const outfitOne = await seedOutfit(account, "Acceptance September weekday look", createdAt, [
    { id: garmentIDs[0]!, role: "top" },
    { id: garmentIDs[2]!, role: "bottom" },
    { id: garmentIDs[4]!, role: "shoes" },
  ]);
  const outfitTwo = await seedOutfit(account, "Acceptance September dinner look", createdAt, [
    { id: garmentIDs[1]!, role: "top" },
    { id: garmentIDs[3]!, role: "bottom" },
    { id: garmentIDs[4]!, role: "shoes" },
  ]);
  const septemberWear = await insert("outfit_wears", account, {
    user_id: account.id,
    outfit_id: outfitOne.id,
    worn_at: createdAt,
    occasion: "Synthetic acceptance wear in the elapsed month",
  });
  result.seeded_outfit_ids = [outfitOne.id, outfitTwo.id];
  result.elapsed_month_wear_id = septemberWear.id;
  result.fixture_ids = {
    owner_id: account.id,
    garment_ids: garmentIDs,
    seeded_outfit_ids: [outfitOne.id, outfitTwo.id],
    elapsed_month_wear_id: septemberWear.id,
  };
  result.stage = "fixtures_seeded";
  await writeReport();

  const lockedItemBeforeKyra = await rows(
    account,
    `/rest/v1/closet_items?select=id,laundry_state,availability_state&user_id=eq.${account.id}&id=eq.${
      garmentIDs[0]
    }`,
  );
  assertEquals(lockedItemBeforeKyra.length, 1);
  assertEquals(lockedItemBeforeKyra[0]?.laundry_state, "worn_once");
  assertEquals(lockedItemBeforeKyra[0]?.availability_state, "available");

  const now = new Date();
  const lockedItemID = garmentIDs[0]!;
  const kyraRequestID = crypto.randomUUID();
  result.top_level_kyra_requests = 1;
  result.kyra_request_id = kyraRequestID;
  result.quota_verification = {
    expected_successful_uses: 1,
    request_id: kyraRequestID,
    client_ledger_readable: false,
    note:
      "Quota ledger and operation table are service-role-only; root can verify this request ID server-side.",
  };
  result.stage = "kyra_request_sent";
  await writeReport();
  const response = await request("/functions/v1/kyra/respond", account, {
    method: "POST",
    body: JSON.stringify({
      request_id: kyraRequestID,
      client_version: "connected-lifecycle-acceptance/1",
      body: {
        thread_id: null,
        text:
          "Refine an everyday outfit using only my owned closet. Keep my Acceptance navy merino polo as the top, then save one complete outfit with a short practical reason.",
        attachments: [],
        weather_snapshot: {
          observed_at: now.toISOString(),
          temperature_high: 58,
          temperature_low: 46,
          condition: "partly_cloudy",
          season: "fall",
        },
        schedule_snapshot: null,
        locked_closet_item_ids: [lockedItemID],
        outfit_builder_completion: true,
      },
    }),
  });
  const envelope = await json(response);
  const data = envelope.data as Row | undefined;
  if (!response.ok || !data) {
    throw new Error(`Kyra builder request failed (HTTP ${response.status}).`);
  }
  const payload = data.structured_payload as Row | undefined;
  const metadata = data.model_metadata as Row | undefined;
  const cards = payload?.cards;
  result.stage = "kyra_response_received";
  result.kyra = {
    http_status: response.status,
    request_count: 1,
    thread_id: data.thread_id ?? null,
    model_identifier: metadata?.model_identifier ?? null,
    tier: metadata?.tier ?? null,
    escalated: metadata?.escalated ?? null,
    fallback_reason: metadata?.fallback_reason ?? null,
    tools_called: Array.isArray(metadata?.tools_called) ? metadata.tools_called : null,
  };
  await writeReport();
  assert(Array.isArray(cards), "Kyra response must contain structured cards.");
  const outfitCard = cards.find((entry) =>
    entry && typeof entry === "object" && (entry as Row).type === "outfit"
  ) as Row | undefined;
  assert(
    outfitCard && typeof outfitCard.outfit_id === "string",
    "Kyra must return a saved outfit card.",
  );
  assert(typeof outfitCard.reason === "string" && outfitCard.reason.trim().length > 0);
  assertEquals(metadata?.fallback_reason, null);
  assertEquals(metadata?.provider_failure, null);
  assertEquals(metadata?.escalated, false);
  assert(typeof metadata?.model_identifier === "string");
  assert(Array.isArray(metadata?.tools_called));
  const toolsCalled = metadata.tools_called as unknown[];
  const maximumToolCalls = metadata.tier === "terra" ? 6 : 4;
  assert(
    toolsCalled.length <= maximumToolCalls,
    `tool calls must stay within the ${String(metadata.tier)} tier limit`,
  );
  const createOutfitCalls = toolsCalled.filter((tool) => tool === "create_outfit").length;
  assert(createOutfitCalls >= 1, "Kyra must use create_outfit to persist the requested look.");
  assert(!toolsCalled.includes("generate_studio_preview"));
  assert(!toolsCalled.includes("analyze_product"));
  (result.kyra as Row).create_outfit_tool_calls = createOutfitCalls;
  const kyraOutfitID = String(outfitCard.outfit_id);
  result.kyra_outfit_id = kyraOutfitID;
  result.stage = "outfit_card_received";
  await writeReport();
  const [profileRows, closetRows, outfits, outfitItems, wearRows, kyraMessages] = await Promise.all(
    [
      rows(account, `/rest/v1/profiles?select=id,wardrobe_graph&id=eq.${account.id}`),
      rows(
        account,
        `/rest/v1/closet_items?select=id,user_id,name,wear_count,last_worn_at,laundry_state,availability_state&user_id=eq.${account.id}&order=created_at.asc`,
      ),
      rows(
        account,
        `/rest/v1/outfits?select=id,user_id,name,source,created_at&user_id=eq.${account.id}&order=created_at.asc`,
      ),
      rows(
        account,
        `/rest/v1/outfit_items?select=id,user_id,outfit_id,closet_item_id,role,product_candidate_id&user_id=eq.${account.id}`,
      ),
      rows(
        account,
        `/rest/v1/outfit_wears?select=id,user_id,outfit_id,worn_at&user_id=eq.${account.id}&order=worn_at.asc`,
      ),
      rows(
        account,
        `/rest/v1/kyra_messages?select=id,user_id,thread_id,role&user_id=eq.${account.id}`,
      ),
    ],
  );
  assertEquals(profileRows.length, 1);
  assertEquals(closetRows.length, 5);
  assertEquals(outfits.length, 3);
  assertEquals(outfits.filter((outfit) => outfit.source === "kyra_suggested").length, 1);
  assertEquals(
    outfits.filter((outfit) => outfit.id === kyraOutfitID).length,
    1,
    "exactly one Kyra-saved outfit should be persisted",
  );
  assert(closetRows.every((row) => row.user_id === account!.id));
  assert(outfits.every((row) => row.user_id === account!.id));
  assert(outfitItems.every((row) => row.user_id === account!.id));
  assert(outfitItems.every((row) => row.product_candidate_id === null));
  const savedItems = outfitItems.filter((row) => row.outfit_id === kyraOutfitID);
  assert(savedItems.length >= 3);
  const lockedSavedItem = savedItems.find((row) => row.closet_item_id === lockedItemID);
  assert(lockedSavedItem, "the saved outfit must include the locked owner garment");
  assertEquals(lockedSavedItem.role, "top");
  assert(savedItems.every((row) => garmentIDs.includes(String(row.closet_item_id))));
  for (const role of ["top", "bottom", "shoes"]) {
    assert(savedItems.some((item) => item.role === role), `saved outfit needs a ${role}`);
  }
  assert(wearRows.every((row) => row.user_id === account!.id));
  assertEquals(wearRows.length, 1);
  assertEquals(wearRows[0]?.outfit_id, septemberWear.outfit_id);
  assert(kyraMessages.length >= 2);
  result.stage = "outfit_persisted_and_owner_verified";
  result.quota_verification = {
    ...(result.quota_verification as Row),
    outfit_generation_daily_usage_expected: 1,
    committed_operation_expected: 1,
    server_side_verification_required: true,
  };
  await writeReport();

  const currentWear = await insert("outfit_wears", account, {
    user_id: account.id,
    outfit_id: kyraOutfitID,
    worn_at: now.toISOString(),
    occasion: "Synthetic current-month acceptance wear",
  });
  result.current_month_wear_id = currentWear.id;
  const currentPeriodWears = await rows(
    account,
    `/rest/v1/outfit_wears?select=id,user_id,outfit_id,worn_at&user_id=eq.${account.id}&worn_at=gte.${
      encodeURIComponent(elapsedEnd.toISOString())
    }`,
  );
  assert(currentPeriodWears.some((wear) => wear.id === currentWear.id));
  const closetAfterWear = await rows(
    account,
    `/rest/v1/closet_items?select=id,user_id,wear_count,last_worn_at,availability_state&user_id=eq.${account.id}`,
  );
  const kyraWornItemIDs = savedItems.map((item) => String(item.closet_item_id));
  const wardrobeWearStats = closetAfterWear.filter((item) =>
    kyraWornItemIDs.includes(String(item.id))
  );
  assertEquals(wardrobeWearStats.length, savedItems.length);
  const currentWearTimestamp = new Date(String(currentWear.worn_at)).getTime();
  for (const wornItem of wardrobeWearStats) {
    const beforeWear = closetRows.find((item) => item.id === wornItem.id);
    assert(beforeWear, "every selected garment must have a pre-wear stats row");
    assertEquals(Number(wornItem.wear_count), Number(beforeWear.wear_count) + 1);
    assertEquals(new Date(String(wornItem.last_worn_at)).getTime(), currentWearTimestamp);
    assertEquals(wornItem.availability_state, "available");
  }
  const elapsedMonthWears = await rows(
    account,
    `/rest/v1/outfit_wears?select=id,user_id,outfit_id,worn_at&user_id=eq.${account.id}&worn_at=gte.${startISO}&worn_at=lt.${
      encodeURIComponent(elapsedEnd.toISOString())
    }`,
  );
  assertEquals(elapsedMonthWears.length, 1);
  assertEquals(elapsedMonthWears[0]?.outfit_id, outfitOne.id);
  assert(!elapsedMonthWears.some((wear) => wear.id === currentWear.id));
  result.live_owner_facts = {
    profile_rows: profileRows.length,
    closet_items: closetRows.length,
    saved_outfits: outfits.length,
    outfit_item_rows: outfitItems.length,
    kyra_message_rows: kyraMessages.length,
    current_month_wear_rows: currentPeriodWears.length,
    kyra_outfit_items_with_wear_stats: wardrobeWearStats.length,
  };
  result.elapsed_month_boundary = {
    elapsed_month_wear_rows: elapsedMonthWears.length,
    current_month_wear_excluded: true,
    note:
      "Home Monthly Review targets the last completed month; this current-month Kyra outfit and wear are intentionally excluded without backdating.",
  };
  result.stage = "wear_and_month_boundary_verified";

  const exported = await request("/functions/v1/profile/export-data", account);
  const exportEnvelope = await json(exported);
  const exportData = (exportEnvelope.data && typeof exportEnvelope.data === "object"
    ? exportEnvelope.data
    : exportEnvelope) as Row;
  const varyHeaderValue = exported.headers.get("Vary");
  result.export = {
    status: exported.status,
    cache_control: exported.headers.get("Cache-Control"),
    vary: varyHeaderValue,
    included_profile_closet_outfits_wears_kyra: false,
    image_bytes_requested: false,
  };
  if (!exported.ok) {
    throw new Error(`Owner export failed (HTTP ${exported.status}).`);
  }
  assertEquals(exportData.owner_user_id, account.id);
  const exportedTables = exportData.tables as Row | undefined;
  assert(exportedTables && typeof exportedTables === "object");
  assertEquals((exportedTables.closet_items as unknown[] | undefined)?.length, 5);
  assertEquals((exportedTables.outfits as unknown[] | undefined)?.length, 3);
  assertEquals((exportedTables.outfit_items as unknown[] | undefined)?.length, outfitItems.length);
  assertEquals((exportedTables.outfit_wears as unknown[] | undefined)?.length, 2);
  assertEquals(
    (exportedTables.kyra_messages as unknown[] | undefined)?.length,
    kyraMessages.length,
  );
  assertEquals(exported.headers.get("Cache-Control"), "no-store");
  const varyHeaders = (varyHeaderValue ?? "")
    .split(",")
    .map((header) =>
      header.trim().toLowerCase()
    );
  assert(varyHeaders.includes("authorization"));
  (result.export as Row).included_profile_closet_outfits_wears_kyra = true;
} catch (error) {
  failure = error instanceof Error ? error.message : "unknown acceptance failure";
} finally {
  if (account && !account.deleted) {
    try {
      await deleteNormally(account);
    } catch (error) {
      result.cleanup_error = error instanceof Error
        ? error.message
        : "normal account deletion failed";
    }
  }
  if (reportPath) {
    await writeReport();
  }
}

console.log(JSON.stringify({ result, failure }));
if (result.cleanup_error) throw new Error("Synthetic account cleanup failed.");
if (failure) throw new Error(failure);
