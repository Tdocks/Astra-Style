import { assert, assertEquals } from "@std/assert";

// One-shot live acceptance for the atomic Daily Brief and product lifetime trial persistence.
// All rows are synthetic and caller-owned; no photos or storage are involved.
const projectRef = "anutsdzbxycaavmmkewo";
const baseURL = `https://${projectRef}.supabase.co`;
assertEquals(Deno.env.get("ASTRA_RUN_MORNING_LOOP_ACCEPTANCE"), "1");
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
  for (const category of ["top", "bottom", "shoes"]) {
    await insert("closet_items", account, {
      user_id: account.id,
      name: `Morning loop acceptance ${category}`,
      category,
      primary_color: "navy",
      material: [{ fiber: "cotton", percentage: 100 }],
      fit: "regular",
      condition: "good",
      seasonality: ["spring", "summer", "fall", "winter"],
      formality_score: 50,
      warmth_score: 40,
      laundry_state: "clean",
      availability_state: "available",
    });
  }
  const send = async (
    path: string,
    id: string,
    body: Row,
  ): Promise<{ response: Response; payload: Row }> => {
    const response = await request(`/functions/v1/${path}`, account!.token, {
      method: "POST",
      body: JSON.stringify({
        request_id: id,
        client_version: "morning-loop-live-acceptance/1",
        body,
      }),
    });
    return { response, payload: await json(response) };
  };
  const assertQuota = (
    entry: { response: Response; payload: Row },
    limit: string,
    count: number,
  ): void => {
    assertEquals(entry.response.status, 429);
    const error = entry.payload.error as Row;
    assertEquals(error.category, "subscription_limit_reached");
    const details = error.details as Row;
    assertEquals(details.limit, limit);
    assertEquals(details.limit_count, count);
    assertEquals(details.remaining, 0);
    assertEquals(details.resets_at, null);
    assertEquals(entry.response.headers.get("Retry-After"), null);
  };
  const date = (daysAgo: number): string =>
    new Date(Date.now() - daysAgo * 86_400_000).toISOString().slice(0, 10);
  const firstDate = date(0);
  const firstBody = {
    date: firstDate,
    regenerate: false,
    weather_snapshot: null,
    schedule_snapshot: null,
  };
  const cold = await Promise.all([
    send("daily-brief/generate", crypto.randomUUID(), firstBody),
    send("daily-brief/generate", crypto.randomUUID(), firstBody),
  ]);
  assertEquals(cold[0]!.response.status, 200);
  assertEquals(cold[1]!.response.status, 200);
  assertEquals(cold[0]!.payload.data, cold[1]!.payload.data);
  const days = [1, 2, 3].map((index) => ({
    id: crypto.randomUUID(),
    body: { ...firstBody, date: date(index) },
  }));
  const outcomes = await Promise.all(
    days.map((entry) => send("daily-brief/generate", entry.id, entry.body)),
  );
  const success = outcomes.flatMap((entry, index) => entry.response.status === 200 ? [index] : []);
  assertEquals(success.length, 2);
  for (const entry of outcomes.filter((entry) => entry.response.status !== 200)) {
    assertQuota(entry, "daily_brief_trial_generation", 3);
  }
  const briefs = await readRows(account, "/rest/v1/daily_briefs?select=id,primary_outfit_id");
  const outfits = await readRows(account, "/rest/v1/outfits?select=id");
  assertEquals(briefs.length, 3);
  assertEquals(outfits.length, 3, "same-date cold race must not create an orphan outfit");
  const winningIndex = success[0]!;
  const winningRequest = days[winningIndex]!;
  const replay = await send("daily-brief/generate", winningRequest.id, winningRequest.body);
  assertEquals(replay.response.status, 200);
  assertEquals(replay.payload.data, outcomes[winningIndex]!.payload.data);
  const warm = await send("daily-brief/generate", crypto.randomUUID(), firstBody);
  assertEquals(warm.response.status, 200);
  assertEquals(warm.payload.data, cold[0]!.payload.data);
  const refresh = await send("daily-brief/generate", crypto.randomUUID(), {
    ...firstBody,
    schedule_snapshot: { event_count: 1, earliest_formality_level: "formal" },
  });
  assertEquals(refresh.response.status, 200, "measured-context refresh remains available at limit");
  const removeBrief = await request(
    `/rest/v1/daily_briefs?id=eq.${String((outcomes[winningIndex]!.payload.data as Row).id)}`,
    account.token,
    { method: "DELETE" },
  );
  assert(removeBrief.ok);
  assertQuota(
    await send("daily-brief/generate", crypto.randomUUID(), { ...firstBody, date: date(4) }),
    "daily_brief_trial_generation",
    3,
  );
  const removedBriefReplay = await send(
    "daily-brief/generate",
    winningRequest.id,
    winningRequest.body,
  );
  assertEquals(removedBriefReplay.response.status, 404);
  result.daily_brief = {
    lifetime_successes: 3,
    same_date_converged: true,
    no_cold_race_orphans: true,
    cached_at_limit: true,
    replay: true,
    measured_context_refresh: true,
    deletion_no_refund: true,
    deleted_source_not_replayed: true,
  };

  // Existing shared catalog is read-only; this harness neither extracts nor mutates products.
  const candidates = await readRows(
    account,
    "/rest/v1/product_candidates?select=id&category=in.(top,bottom,shoes,outerwear,accessory)&order=id.asc&limit=2",
  );
  assertEquals(candidates.length, 2, "two existing scorable catalog candidates are required");
  const evaluations = candidates.map((candidate) => ({
    id: crypto.randomUUID(),
    body: { product_candidate_id: String(candidate.id) },
  }));
  const verdicts = await Promise.all(
    evaluations.map((entry) => send("products/evaluate", entry.id, entry.body)),
  );
  const accepted = verdicts.flatMap((entry, index) => entry.response.status === 200 ? [index] : []);
  assertEquals(accepted.length, 1);
  for (const entry of verdicts.filter((entry) => entry.response.status !== 200)) {
    assertQuota(entry, "paste_product_evaluation_trial", 1);
  }
  const winner = accepted[0]!;
  const evaluationRequest = evaluations[winner]!;
  const evaluationReplay = await send(
    "products/evaluate",
    evaluationRequest.id,
    evaluationRequest.body,
  );
  assertEquals(evaluationReplay.response.status, 200);
  assertEquals(evaluationReplay.payload.data, verdicts[winner]!.payload.data);
  const changed = await send(
    "products/evaluate",
    evaluationRequest.id,
    evaluations[1 - winner]!.body,
  );
  assert(!changed.response.ok && changed.response.status !== 429);
  const savedEvaluations = await readRows(account, "/rest/v1/user_product_evaluations?select=id");
  assertEquals(savedEvaluations.length, 1);
  const removeEvaluation = await request(
    `/rest/v1/user_product_evaluations?id=eq.${String(savedEvaluations[0]!.id)}`,
    account.token,
    { method: "DELETE" },
  );
  assert(removeEvaluation.ok);
  assertQuota(
    await send("products/evaluate", crypto.randomUUID(), evaluationRequest.body),
    "paste_product_evaluation_trial",
    1,
  );
  const removedEvaluationReplay = await send(
    "products/evaluate",
    evaluationRequest.id,
    evaluationRequest.body,
  );
  assertEquals(removedEvaluationReplay.response.status, 404);
  const directBrief = await request("/rest/v1/daily_briefs", account.token, {
    method: "POST",
    body: JSON.stringify({ user_id: account.id, brief_date: date(5) }),
  });
  assertEquals(directBrief.status, 403);
  const directEvaluation = await request("/rest/v1/user_product_evaluations", account.token, {
    method: "POST",
    body: JSON.stringify({
      user_id: account.id,
      product_candidate_id: evaluationRequest.body.product_candidate_id,
      verdict: (verdicts[winner]!.payload.data as Row).verdict,
    }),
  });
  assertEquals(directEvaluation.status, 403);
  for (const table of ["morning_loop_trial_usage", "morning_loop_trial_operations"]) {
    const denied = await request(`/rest/v1/${table}?select=user_id`, account.token);
    assertEquals(denied.status, 403);
  }
  result.direct_writes_and_private_ledger_reads_denied = true;
  result.products = {
    lifetime_successes: 1,
    exact_replay: true,
    changed_payload_rejected: true,
    deletion_no_refund: true,
    deleted_source_not_replayed: true,
    catalog_unchanged: true,
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
