import { assert, assertEquals } from "@std/assert";

// Opt-in, one-request Monthly Review acceptance against the deployed Kyra
// provider. This fixture uses text facts only and always deletes its account.
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

type RecordValue = Record<string, unknown>;
type Account = { id: string; token: string; deleted: boolean };
const result: RecordValue = {};
let failure: string | null = null;
let account: Account | null = null;

function headers(token?: string): Headers {
  const value = new Headers({ apikey: publishableKey, "Content-Type": "application/json" });
  if (token) value.set("Authorization", `Bearer ${token}`);
  return value;
}

async function json(response: Response): Promise<RecordValue> {
  try {
    const value = await response.json();
    return value && typeof value === "object" ? value as RecordValue : {};
  } catch {
    return {};
  }
}

async function request(path: string, token: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${baseURL}${path}`, {
    ...init,
    headers: { ...Object.fromEntries(headers(token)), ...init.headers },
    signal: init.signal ?? AbortSignal.timeout(90_000),
  });
}

async function writeReport(): Promise<void> {
  if (!reportPath) return;
  await Deno.writeTextFile(reportPath, JSON.stringify({ result, failure }, null, 2), {
    mode: 0o600,
  });
}

try {
  const signup = await fetch(`${baseURL}/auth/v1/signup`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({}),
    signal: AbortSignal.timeout(20_000),
  });
  const auth = await json(signup);
  const user = auth.user as RecordValue | undefined;
  if (!signup.ok || typeof user?.id !== "string" || typeof auth.access_token !== "string") {
    throw new Error(`Disposable account creation failed (HTTP ${signup.status}).`);
  }
  account = { id: user.id, token: auth.access_token, deleted: false };
  result.owner_id = account.id;

  const prompt = [
    "Write a concise Monthly Review for October 2026 using only the eight supplied synthetic fixture facts below.",
    "Treat the figures as fixed, do not call tools, and do not invent counts, purchases, causes, trends, or measurements.",
    "Explicitly acknowledge missing information instead of filling gaps. Include one practical next priority and one specific challenge for next month.",
    "1. Two new closet pieces were added: a navy wool coat and an olive cotton overshirt.",
    "2. Tracked spend for those two pieces is $180 USD.",
    "3. Three looks were marked worn during the month.",
    "4. Those looks span two distinct outfits.",
    "5. No purchased item has a recorded product evaluation, so there is no best-purchase or outfit-unlock result.",
    "6. An older brown derby shoe has one recorded wear.",
    "7. An older charcoal knit has zero recorded wears.",
    "8. Current and prior-month wardrobe versatility scores, weather, and occasion history are unavailable.",
  ].join("\n");

  // Exactly one client POST is issued. Do not retry on timeout or provider failure.
  const response = await request("/functions/v1/kyra/respond", account.token, {
    method: "POST",
    body: JSON.stringify({
      request_id: crypto.randomUUID(),
      client_version: "monthly-review-live-acceptance/1",
      body: { text: prompt },
    }),
  });
  const envelope = await json(response);
  const data = envelope.data as RecordValue | undefined;
  if (!response.ok || !data) {
    throw new Error(`Kyra Monthly Review request failed (HTTP ${response.status}).`);
  }
  const structured = data.structured_payload as RecordValue | undefined;
  const metadata = data.model_metadata as RecordValue | undefined;
  const message = structured?.message;
  const threadID = data.thread_id;
  if (typeof message !== "string" || message.trim().length < 40) {
    throw new Error("Kyra did not return a readable structured review.");
  }
  assert(typeof threadID === "string", "new conversation should return its persisted thread ID");
  assert(typeof metadata?.model_identifier === "string", "provider model identifier is required");
  assertEquals(
    metadata.fallback_reason,
    null,
    "the review must be provider-authored, not fallback text",
  );
  assertEquals(metadata.provider_failure, null, "provider must report no failure");
  assertEquals(metadata.escalated, false, "single provider call requires no model escalation");
  assertEquals(
    metadata.tools_called,
    [],
    "the authoring request must not require additional tool calls",
  );

  const [threadsResponse, messagesResponse] = await Promise.all([
    request(
      `/rest/v1/kyra_threads?select=id,user_id&id=eq.${encodeURIComponent(threadID)}`,
      account.token,
    ),
    request(
      `/rest/v1/kyra_messages?select=id,user_id,thread_id,role,content&id=eq.${
        encodeURIComponent(String(data.id))
      }`,
      account.token,
    ),
  ]);
  if (!threadsResponse.ok || !messagesResponse.ok) {
    throw new Error("Could not verify the persisted Monthly Review thread and assistant message.");
  }
  const threads = await threadsResponse.json() as RecordValue[];
  const messages = await messagesResponse.json() as RecordValue[];
  assertEquals(threads.length, 1);
  assertEquals(threads[0]?.user_id, account.id);
  assertEquals(messages.length, 1);
  assertEquals(messages[0]?.user_id, account.id);
  assertEquals(messages[0]?.thread_id, threadID);
  assertEquals(messages[0]?.role, "assistant");
  assertEquals(messages[0]?.content, data.content);
  result.acceptance = {
    http_status: response.status,
    thread_id: threadID,
    assistant_message_id: data.id,
    model_identifier: metadata.model_identifier,
    escalated: metadata.escalated,
    tool_calls: metadata.tools_called,
    fallback_reason: metadata.fallback_reason,
    structured_review: message,
    persisted_thread_and_message: true,
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
            (receipt.data as RecordValue | undefined)?.deletion_id ?? null,
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
