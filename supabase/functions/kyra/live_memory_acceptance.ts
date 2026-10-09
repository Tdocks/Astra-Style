import { assert, assertEquals } from "@std/assert";

/**
 * Opt-in synthetic-owner acceptance for P5-KYRA-17. Verifies the visible
 * memory list, a real Kyra response while a visible memory exists, hard
 * deletion, and a fresh-thread response after deletion. It uses synthetic
 * text only and always requests normal account deletion.
 *
 * Run with RUN_KYRA_MEMORY_ACCEPTANCE=1, SUPABASE_URL, SUPABASE_ANON_KEY,
 * and --allow-env/--allow-net permissions. No provider key is read here.
 */
const baseURL = Deno.env.get("SUPABASE_URL");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
assertEquals(Deno.env.get("RUN_KYRA_MEMORY_ACCEPTANCE"), "1", "set the explicit opt-in flag");
assert(baseURL, "SUPABASE_URL is required");
assert(anonKey, "SUPABASE_ANON_KEY is required");

type Envelope<T> = { data?: T; error?: { message?: string }; request_id?: string };

function headers(token?: string): Record<string, string> {
  return {
    apikey: anonKey!,
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    "Content-Type": "application/json",
  };
}

async function readJSON<T>(response: Response): Promise<T> {
  const body = await response.json() as T & Envelope<unknown>;
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${body.error?.message ?? "request failed"}`);
  }
  return body;
}

async function readEnvelope<T>(response: Response): Promise<Envelope<T>> {
  return await readJSON<Envelope<T>>(response);
}

function mentions(text: string | undefined, marker: string): boolean {
  return (text ?? "").toLocaleLowerCase().includes(marker.toLocaleLowerCase());
}

async function sendFreshThread(token: string, text: string): Promise<string> {
  const response = await fetch(`${baseURL}/functions/v1/kyra/respond`, {
    method: "POST",
    headers: headers(token),
    body: JSON.stringify({
      request_id: crypto.randomUUID(),
      client_version: "p5-kyra-17-live-acceptance",
      body: { text },
    }),
  });
  const envelope = await readEnvelope<{
    content?: string;
    structured_payload?: { message?: string };
    thread_id?: string;
  }>(response);
  const answer = envelope.data?.structured_payload?.message ?? envelope.data?.content;
  assert(answer, "Kyra response must include a message");
  return answer;
}

const signup = await fetch(`${baseURL}/auth/v1/signup`, {
  method: "POST",
  headers: headers(),
  body: JSON.stringify({}),
});
const auth = await readJSON<{ user?: { id?: string }; access_token?: string }>(signup);
assert(auth.user?.id, "signup response must include the synthetic owner");
assert(auth.access_token, "signup response must include its session token");
const ownerID = auth.user.id;
const token = auth.access_token;

try {
  const marker = `LANTERN-ORBIT-${crypto.randomUUID().slice(0, 8)}`;
  const visibleContent = `Synthetic acceptance note ${marker}: the user prefers chartreuse.`;
  const hiddenContent = `Internal-only synthetic note ${marker}: never show cobalt.`;
  const memoryRows = [
    {
      user_id: ownerID,
      memory_type: "preference",
      content: visibleContent,
      confidence: 0.99,
      is_user_visible: true,
    },
    {
      user_id: ownerID,
      memory_type: "general",
      content: hiddenContent,
      confidence: 0.99,
      is_user_visible: false,
    },
  ];
  const insert = await fetch(`${baseURL}/rest/v1/style_memories?select=id,is_user_visible`, {
    method: "POST",
    headers: { ...headers(token), Prefer: "return=representation" },
    body: JSON.stringify(memoryRows),
  });
  const inserted = await readJSON<Array<{ id: string; is_user_visible: boolean }>>(insert);
  assertEquals(inserted.length, 2);
  const visibleRow = inserted.find((row) => row.is_user_visible);
  const hiddenRow = inserted.find((row) => !row.is_user_visible);
  assert(visibleRow?.id, "visible memory must be persisted");
  assert(hiddenRow?.id, "internal-only fixture memory must be persisted");

  const visibleList = await fetch(
    `${baseURL}/rest/v1/style_memories?select=id,content,is_user_visible&is_user_visible=eq.true&order=created_at.desc`,
    { headers: headers(token) },
  );
  const listed = await readJSON<Array<{ id: string; content: string; is_user_visible: boolean }>>(
    visibleList,
  );
  assert(listed.some((row) => row.id === visibleRow.id));
  assert(!listed.some((row) => row.id === hiddenRow.id));
  assert(!listed.some((row) => row.content.includes("never show cobalt")));

  const prompt =
    "What exact color preference is saved for me? If there is no saved preference, say unknown.";
  const before = await sendFreshThread(token, prompt);
  const beforeMentionsPreference = mentions(before, "chartreuse");

  const deletion = await fetch(
    `${baseURL}/rest/v1/style_memories?id=eq.${encodeURIComponent(visibleRow.id)}&select=id`,
    {
      method: "DELETE",
      headers: { ...headers(token), Prefer: "return=representation" },
    },
  );
  const deleted = await readJSON<Array<{ id: string }>>(deletion);
  assertEquals(deleted.map((row) => row.id), [visibleRow.id]);

  const afterRead = await fetch(
    `${baseURL}/rest/v1/style_memories?select=id&is_user_visible=eq.true&id=eq.${
      encodeURIComponent(visibleRow.id)
    }`,
    { headers: headers(token) },
  );
  const remaining = await readJSON<Array<{ id: string }>>(afterRead);
  assertEquals(remaining.length, 0, "deleted memory must no longer be readable");

  // A new thread ensures the deleted preference cannot leak in via prior
  // assistant turns in conversation history.
  const after = await sendFreshThread(token, prompt);
  const afterMentionsPreference = mentions(after, "chartreuse");
  assert(beforeMentionsPreference, "pre-deletion response should demonstrate memory use");
  assert(!afterMentionsPreference, "post-deletion response must not repeat the deleted preference");

  console.log(JSON.stringify({
    owner_id: ownerID,
    visible_list_excluded_internal_memory: true,
    response_used_visible_memory_before_delete: beforeMentionsPreference,
    fresh_thread_omitted_deleted_memory: !afterMentionsPreference,
  }));
} finally {
  const deletion = await fetch(`${baseURL}/functions/v1/account`, {
    method: "DELETE",
    headers: headers(token),
  });
  const result = await readEnvelope<{ deletion_id?: string; status?: string }>(deletion);
  assertEquals(deletion.status, 202, "synthetic owner should use normal account deletion");
  assert(result.data?.deletion_id, "account deletion response must include its ID");
  console.log(JSON.stringify({
    owner_id: ownerID,
    deletion_id: result.data.deletion_id,
    deletion_status: result.data.status,
  }));
}
