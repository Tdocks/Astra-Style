const projectRef = "anutsdzbxycaavmmkewo";
const baseURL = "https://" + projectRef + ".supabase.co";
const keyFile = Deno.args[0];
if (!keyFile) throw new Error("Pass the protected API key JSON path.");
const keys = JSON.parse(await Deno.readTextFile(keyFile)) as Array<Record<string, unknown>>;
const publishableKeyValue = keys.find((key) => key.type === "publishable")?.api_key;
if (typeof publishableKeyValue !== "string") throw new Error("Publishable key unavailable.");
const publishableKey: string = publishableKeyValue;

type Account = { id: string; token: string; deleted: boolean };
const accounts: Account[] = [];
const results: Record<string, unknown> = {};

function canonical(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return "{" + Object.keys(record).sort().map((key) =>
      JSON.stringify(key) + ":" + canonical(record[key])
    ).join(",") + "}";
  }
  return JSON.stringify(value);
}

function authHeaders(token?: string): Headers {
  const headers = new Headers({
    apikey: publishableKey,
    "Content-Type": "application/json",
  });
  if (token) headers.set("Authorization", "Bearer " + token);
  return headers;
}

async function readJson(response: Response): Promise<Record<string, unknown>> {
  try {
    const value = await response.json();
    return value && typeof value === "object" ? value as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

async function createAccount(label: string): Promise<Account> {
  const response = await fetch(baseURL + "/auth/v1/signup", {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify({}),
  });
  const body = await readJson(response);
  const user = body.user as Record<string, unknown> | undefined;
  const id = user?.id;
  const token = body.access_token;
  if (!response.ok || typeof id !== "string" || typeof token !== "string") {
    throw new Error(label + " anonymous signup failed; status=" + response.status);
  }
  const account = { id, token, deleted: false };
  accounts.push(account);
  return account;
}

function answers(records: Array<[string, string]>): Array<Record<string, string>> {
  return records.map(([pair_id, chosen_option_id]) => ({ pair_id, chosen_option_id }));
}

function vector(dimensions: Record<string, unknown>, answered: number): Record<string, unknown> {
  return {
    version: 1,
    comparisons_answered: answered,
    comparisons_offered: answered,
    dimensions,
  };
}

function reading(score: number): Record<string, unknown> {
  return {
    score,
    confidence: "moderate",
    observations: 2,
    agreement: 1,
  };
}

async function completeOnboarding(
  account: Account,
  quizAnswers: Array<Record<string, string>>,
  preferenceVector: Record<string, unknown>,
): Promise<{ status: number; body: Record<string, unknown> }> {
  const response = await fetch(baseURL + "/functions/v1/profile/complete-onboarding", {
    method: "POST",
    headers: authHeaders(account.token),
    body: JSON.stringify({
      request_id: crypto.randomUUID(),
      client_version: "hosted-taste-acceptance/1",
      body: {
        wardrobe_graph: "menswear_3_role",
        style_goals: [],
        style_profile: {
          primary_identity: "quiet_luxury",
          secondary_identities: [],
          style_goals: [],
          preferred_fit: "tailored",
          preference_vector: preferenceVector,
        },
        body_profile: {},
        lifestyle_profile: {},
        quiz_answers: quizAnswers,
      },
    }),
  });
  return { status: response.status, body: await readJson(response) };
}

async function ownRows(account: Account): Promise<Array<Record<string, unknown>>> {
  const response = await fetch(
    baseURL +
      "/rest/v1/style_profiles?select=user_id,preference_quiz_answers,preference_vector&user_id=eq." +
      encodeURIComponent(account.id),
    { headers: authHeaders(account.token) },
  );
  if (!response.ok) throw new Error("owner profile read failed; status=" + response.status);
  const value = await response.json();
  return Array.isArray(value) ? value as Array<Record<string, unknown>> : [];
}

async function deleteAccount(account: Account): Promise<void> {
  const response = await fetch(baseURL + "/functions/v1/account", {
    method: "DELETE",
    headers: authHeaders(account.token),
    body: JSON.stringify({}),
  });
  const body = await readJson(response);
  if (!response.ok) throw new Error("normal account deletion failed; status=" + response.status);
  account.deleted = true;
  results["cleanup_" + account.id] = {
    status: response.status,
    deletion_id: body.deletion_id ??
      (body.data as Record<string, unknown> | undefined)?.deletion_id ?? null,
  };
}

try {
  const owner = await createAccount("owner");
  const firstAnswers = answers([
    ["formality-01", "relaxed"],
    ["colour-01", "restrained"],
    ["texture-01", "flat"],
  ]);
  const firstVector = vector({
    formality: reading(-0.7),
    colour_tolerance: reading(-0.5),
    texture: reading(-0.4),
  }, 3);
  const first = await completeOnboarding(owner, firstAnswers, firstVector);
  if (first.status !== 200) throw new Error("first-run onboarding failed; status=" + first.status);
  const afterFirst = await ownRows(owner);
  if (afterFirst.length !== 1) throw new Error("first-run profile row missing or duplicated");
  const firstRow = afterFirst[0];
  const persistedFirstAnswers = firstRow.preference_quiz_answers as unknown[];
  if (!Array.isArray(persistedFirstAnswers) || persistedFirstAnswers.length !== 3) {
    throw new Error("first-run answers were not persisted atomically");
  }
  if (canonical(persistedFirstAnswers) !== canonical(firstAnswers)) {
    throw new Error("first-run stored answers differ from the submitted choices");
  }
  if (canonical(firstRow.preference_vector) !== canonical(firstVector)) {
    throw new Error("first-run vector differs from the onboarding submission");
  }
  results.first_run = {
    status: first.status,
    owner_id: owner.id,
    answer_count: persistedFirstAnswers.length,
  };

  const peer = await createAccount("peer");
  const peerFirst = await completeOnboarding(peer, [], vector({}, 0));
  if (peerFirst.status !== 200) {
    throw new Error("peer onboarding failed; status=" + peerFirst.status);
  }
  const peerRows = await ownRows(peer);
  if (peerRows.length !== 1) throw new Error("peer profile row missing");

  const refinementPairs: Array<[string, string]> = [
    ["formality-01", "tailored"],
    ["formality-02", "tailored"],
    ["colour-01", "saturated"],
    ["silhouette-01", "loose"],
    ["silhouette-02", "loose"],
    ["texture-01", "pronounced"],
    ["texture-02", "pronounced"],
    ["logo-01", "unbranded"],
    ["logo-02", "unbranded"],
    ["trend-01", "classic"],
    ["trend-02", "classic"],
    ["accessory-01", "layered"],
    ["accessory-02", "layered"],
    ["contrast-01", "tonal"],
    ["contrast-02", "tonal"],
    ["colour-02", "restrained"],
  ];
  const refinementAnswers = answers(refinementPairs);
  const refinementVector = vector({
    colour_tolerance: reading(0.15),
    formality: reading(0.85),
    silhouette: reading(0.55),
    texture: reading(0.7),
    logo_tolerance: reading(-0.8),
    trend_tolerance: reading(-0.6),
    accessory_preference: reading(0.5),
    contrast_preference: reading(-0.4),
  }, 15);
  const refineResponse = await fetch(
    baseURL +
      "/rest/v1/style_profiles?on_conflict=user_id&select=user_id,preference_quiz_answers,preference_vector",
    {
      method: "POST",
      headers: new Headers({
        ...Object.fromEntries(authHeaders(owner.token)),
        Prefer: "resolution=merge-duplicates,return=representation",
      }),
      body: JSON.stringify({
        user_id: owner.id,
        preference_quiz_answers: refinementAnswers,
        preference_vector: refinementVector,
      }),
    },
  );
  if (!refineResponse.ok) {
    throw new Error("owner refinement upsert failed; status=" + refineResponse.status);
  }
  const ownAfterRefinement = await ownRows(owner);
  if (ownAfterRefinement.length !== 1) throw new Error("refinement changed profile row count");
  const finalRow = ownAfterRefinement[0];
  const finalAnswers = finalRow.preference_quiz_answers as Array<Record<string, unknown>>;
  const finalVector = finalRow.preference_vector as Record<string, unknown>;
  const dimensions = finalVector.dimensions as Record<string, unknown>;
  if (!Array.isArray(finalAnswers) || finalAnswers.length !== 16) {
    throw new Error("refinement answers did not persist");
  }
  if (canonical(finalAnswers) !== canonical(refinementAnswers)) {
    throw new Error("refinement stored answers differ from submitted choices");
  }
  if (!dimensions || Object.keys(dimensions).length !== 8) {
    throw new Error("refinement vector did not persist all eight dimensions");
  }

  const peerBefore = await ownRows(peer);
  const ownerPeerRead = await fetch(
    baseURL + "/rest/v1/style_profiles?select=user_id,preference_quiz_answers&user_id=eq." +
      encodeURIComponent(peer.id),
    { headers: authHeaders(owner.token) },
  );
  if (!ownerPeerRead.ok) {
    throw new Error("peer-isolation read returned status=" + ownerPeerRead.status);
  }
  const ownerPeerRows = await ownerPeerRead.json();
  if (!Array.isArray(ownerPeerRows) || ownerPeerRows.length !== 0) {
    throw new Error("owner could read a peer style profile");
  }
  const peerAttempt = await fetch(
    baseURL + "/rest/v1/style_profiles?on_conflict=user_id",
    {
      method: "POST",
      headers: new Headers({
        ...Object.fromEntries(authHeaders(owner.token)),
        Prefer: "resolution=merge-duplicates,return=representation",
      }),
      body: JSON.stringify({
        user_id: peer.id,
        preference_quiz_answers: refinementAnswers,
        preference_vector: refinementVector,
      }),
    },
  );
  if (peerAttempt.ok) {
    const peerWriteBody = await peerAttempt.json();
    if (Array.isArray(peerWriteBody) && peerWriteBody.length !== 0) {
      throw new Error("owner modified peer profile through REST");
    }
  }
  const peerAfter = await ownRows(peer);
  const peerAnswers = peerAfter[0]?.preference_quiz_answers as unknown[];
  if (
    peerBefore.length !== 1 || peerAfter.length !== 1 || !Array.isArray(peerAnswers) ||
    peerAnswers.length !== 0
  ) {
    throw new Error("peer profile changed or became visible during owner write");
  }
  results.refinement = {
    status: refineResponse.status,
    answer_count: finalAnswers.length,
    vector_dimension_count: Object.keys(dimensions).length,
  };
  results.peer_isolation = {
    peer_read_status: ownerPeerRead.status,
    peer_read_row_count: ownerPeerRows.length,
    status: peerAttempt.status,
    peer_answer_count_after_owner_attempt: peerAnswers.length,
  };
} catch (error) {
  results.failure = error instanceof Error ? error.message : "unknown failure";
  throw error;
} finally {
  const cleanupFailures: string[] = [];
  for (const account of [...accounts].reverse()) {
    if (account.deleted) continue;
    try {
      await deleteAccount(account);
    } catch (error) {
      cleanupFailures.push(account.id + ":" + (error instanceof Error ? error.message : "unknown"));
    }
  }
  results.cleanup_failures = cleanupFailures;
  await Deno.writeTextFile(
    "/tmp/astra-taste-refinement-draft/hosted-acceptance-result.json",
    JSON.stringify(results, null, 2) + "\n",
    { create: true, mode: 0o600 },
  );
  console.log(JSON.stringify(results));
}
