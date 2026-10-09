import { assert, assertEquals } from "@std/assert";
import type {
  StylistCompletionRequest,
  StylistCompletionResult,
} from "../_shared/providers/stylistReasoning.ts";
import { ProviderError } from "../_shared/providers/types.ts";
import type { ClosetItemMapperRow } from "../_shared/scoring/closetItemMapper.ts";
import { handleKyraRespond, type HandlerDeps, type KyraStore } from "./handler.ts";
import type { PackingRepository } from "../packing/plan.ts";

const USER = "aaaaaaaa-0000-4000-8000-000000000001";
const THREAD = "bbbbbbbb-0000-4000-8000-000000000001";
const USER_MESSAGE = "cccccccc-0000-4000-8000-000000000001";
const ASSISTANT_MESSAGE = "cccccccc-0000-4000-8000-000000000002";
const PACKET_ITEM = "dddddddd-0000-4000-8000-000000000001";
const SAVED_MEMORY = "eeeeeeee-0000-4000-8000-000000000001";

const NOW = () => new Date("2026-08-16T09:00:00Z");

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

const fakeAuthClient = {
  auth: {
    getUser: (_jwt?: string) => Promise.resolve({ data: { user: { id: USER } }, error: null }),
  },
};

interface StoreRecording {
  threadsCreated: string[];
  userMessages: Array<{ threadId: string; content: string; studioGenerationID?: string | null }>;
  assistantMessages: Array<{
    threadId: string;
    content: string;
    structuredPayload: Record<string, unknown>;
    modelMetadata: Record<string, unknown>;
  }>;
  memoriesInserted: Array<{ memoryType: string; content: string; confidence: number }>;
}

function fakeStore(
  recording: StoreRecording,
  overrides: Partial<KyraStore> = {},
): KyraStore {
  return {
    createThread: (_userId, title) => {
      recording.threadsCreated.push(title);
      return Promise.resolve(THREAD);
    },
    threadExists: (threadId) => Promise.resolve(threadId === THREAD),
    countThreadsCreatedSince: () => Promise.resolve(0),
    insertUserMessage: (_userId, threadId, content, studioGenerationID) => {
      recording.userMessages.push({ threadId, content, studioGenerationID });
      // Postgres-shaped timestamp WITH microseconds: the DTO must normalize
      // it to whole-second Zulu or the Swift decoder throws.
      return Promise.resolve({ id: USER_MESSAGE, createdAt: "2026-08-16T09:00:01.123456+00:00" });
    },
    insertAssistantMessage: (_userId, threadId, content, structuredPayload, modelMetadata) => {
      recording.assistantMessages.push({
        threadId,
        content,
        structuredPayload: structuredPayload as unknown as Record<string, unknown>,
        modelMetadata,
      });
      return Promise.resolve({
        id: ASSISTANT_MESSAGE,
        createdAt: "2026-08-16T09:00:02.654321+00:00",
      });
    },
    listRecentMessages: () => Promise.resolve([]),
    hasActivePremiumSubscription: () => Promise.resolve(false),
    loadStyleProfile: () => Promise.resolve(null),
    loadBodyProfile: () => Promise.resolve(null),
    loadLifestyleProfile: () => Promise.resolve(null),
    listUpcomingOccasions: () => Promise.resolve([]),
    listPacketClosetItems: () =>
      Promise.resolve([{
        id: PACKET_ITEM,
        category: "top",
        subcategory: "knit polo",
        brand: null,
        primary_color: "olive",
        formality_score: 40,
        fit: "regular",
        availability_state: "available",
        laundry_state: "clean",
        wear_count: 3,
        last_worn_at: null,
      }]),
    listRecentFeedback: () => Promise.resolve([]),
    listVisibleMemories: () => Promise.resolve([]),
    listClosetItems: () => Promise.resolve([]),
    listItemsByIds: () => Promise.resolve([]),
    listProductCandidateCategories: () => Promise.resolve(new Map()),
    listOutfitItemIds: () => Promise.resolve(new Map()),
    getOccasionTitle: () => Promise.resolve(null),
    readWardrobeGraph: () => Promise.resolve("menswear_3_role"),
    insertOutfit: () => Promise.resolve("ffffffff-0000-4000-8000-000000000001"),
    commitOutfitGeneration: () =>
      Promise.resolve({
        outfit_id: "ffffffff-0000-4000-8000-000000000001",
        source: "kyra_suggested",
      }),
    listOwnedItemIds: () => Promise.resolve([]),
    getOutfitItemIds: () => Promise.resolve(null),
    insertWornOutfit: () => Promise.resolve("ffffffff-0000-4000-8000-000000000002"),
    findWearOnDate: () => Promise.resolve(null),
    insertWear: () => Promise.resolve("ffffffff-0000-4000-8000-000000000003"),
    readWearCounts: () => Promise.resolve(new Map()),
    listMemoriesByType: () => Promise.resolve([]),
    insertMemory: (_userId, record) => {
      recording.memoriesInserted.push(record);
      return Promise.resolve(SAVED_MEMORY);
    },
    updateMemoryConfidence: () => Promise.resolve(),
    deleteMemory: () => Promise.resolve(),
    packing: emptyPackingRepository(),
    ...overrides,
  };
}

function emptyPackingRepository(): PackingRepository {
  return {
    listCandidateItems: () => Promise.resolve([]),
    readWardrobeGraph: () => Promise.resolve("menswear_3_role"),
    listOccasions: () => Promise.resolve([]),
    findBriefs: () => Promise.resolve([]),
    createOutfits: () => Promise.resolve([]),
    upsertBrief: (input) =>
      Promise.resolve({
        id: `brief-${input.briefDate}`,
        user_id: input.userId,
        brief_date: input.briefDate,
        primary_outfit_id: input.primaryOutfitId,
        alternative_outfit_ids: [...input.alternativeOutfitIds],
        schedule_snapshot: input.scheduleSnapshot,
      }),
    listOutfitItemIds: () => Promise.resolve([]),
  };
}

function emptyRecording(): StoreRecording {
  return { threadsCreated: [], userMessages: [], assistantMessages: [], memoriesInserted: [] };
}

type ScriptEntry =
  | { kind: "result"; result: Partial<StylistCompletionResult> }
  | { kind: "throw"; error: Error };

interface FakeProvider {
  requests: StylistCompletionRequest[];
  provider: HandlerDeps["provider"];
}

function scriptedProvider(script: ScriptEntry[]): FakeProvider {
  const requests: StylistCompletionRequest[] = [];
  return {
    requests,
    provider: {
      complete(request) {
        requests.push(request);
        const entry = script.shift();
        if (entry === undefined) {
          return Promise.reject(new Error("Provider script exhausted — test bug."));
        }
        if (entry.kind === "throw") {
          return Promise.reject(entry.error);
        }
        return Promise.resolve({
          message: "",
          toolCalls: [],
          finishReason: "stop",
          usage: { inputTokens: 100, outputTokens: 50 },
          modelIdentifier: "fake-model-1",
          ...entry.result,
        });
      },
      // deno-lint-ignore require-yield
      async *completeStream() {
        throw new Error("not used in tests");
      },
    },
  };
}

function goodJson(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    message: "I'd wear the olive knit polo tonight.",
    intent: "daily_outfit",
    cards: [{ type: "closet_item", closet_item_id: PACKET_ITEM }],
    suggested_actions: [{ id: "a1", label: "See alternatives", kind: "view_alternatives" }],
    memory_proposals: [],
    confidence: 0.8,
    ...overrides,
  });
}

function deps(
  provider: FakeProvider,
  store: KyraStore,
  configOverrides: Partial<HandlerDeps["config"]> = {},
  rateLimiter: HandlerDeps["rateLimiter"] = {
    check: () => ({ allowed: true, remaining: 9, retryAfterSeconds: 0 }),
  },
): HandlerDeps {
  return {
    authClient: fakeAuthClient,
    store,
    provider: provider.provider,
    rateLimiter,
    config: {
      freeDailyConversationLimit: 3,
      confidenceEscalationThreshold: 0.55,
      memoryMinimumConfidence: 0.7,
      ...configOverrides,
    },
    now: NOW,
    sleep: () => Promise.resolve(),
  };
}

function request(body: Record<string, unknown>): Request {
  return new Request("http://localhost/kyra/respond", {
    method: "POST",
    headers: {
      Authorization: "Bearer aaa.bbb.ccc",
      "Content-Type": "application/json",
      "X-Request-Id": "test-request-id",
    },
    body: JSON.stringify({ request_id: "test-request-id", client_version: "ios/1.0.0", body }),
  });
}

async function envelope(response: Response): Promise<Record<string, unknown>> {
  return await response.json() as Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test("happy path: tool call round-trip, then a KyraMessage the client can decode", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([
    {
      kind: "result",
      result: {
        finishReason: "tool_calls",
        toolCalls: [{ id: "call_1", name: "get_weather", arguments: {} }],
      },
    },
    { kind: "result", result: { message: goodJson() } },
  ]);
  const response = await handleKyraRespond(
    request({ text: "What should I wear tonight?" }),
    deps(provider, fakeStore(recording)),
  );
  assertEquals(response.status, 200);
  const body = await envelope(response);
  assertEquals(body["error"], null);
  const data = body["data"] as Record<string, unknown>;

  // Field-by-field: the Swift KyraMessage decode shape.
  assertEquals(data["id"], ASSISTANT_MESSAGE);
  assertEquals(data["thread_id"], THREAD);
  assertEquals(data["role"], "assistant");
  assertEquals(data["content"], "I'd wear the olive knit polo tonight.");
  // ISO-8601 whole-second Zulu — Swift's .iso8601 rejects fractional seconds.
  assertEquals(data["created_at"], "2026-08-16T09:00:02Z");
  const payload = data["structured_payload"] as Record<string, unknown>;
  assertEquals(payload["intent"], "daily_outfit");
  assertEquals((payload["cards"] as unknown[]).length, 1);
  assertEquals(payload["confidence"], 0.8);

  // The turn is persisted: one user message, one assistant message, a thread.
  assertEquals(recording.threadsCreated.length, 1);
  assertEquals(recording.userMessages[0]?.content, "What should I wear tonight?");
  assertEquals(recording.assistantMessages[0]?.threadId, THREAD);
  assertEquals(recording.assistantMessages[0]?.modelMetadata.tools_called, ["get_weather"]);

  // The provider saw the full eleven-tool surface and the luna tier.
  assertEquals(provider.requests[0]?.tools.length, 11);
  assertEquals(provider.requests[0]?.tier, "luna");
  // Tool result was fed back as a tool message before the second call.
  const secondCallMessages = provider.requests[1]?.messages ?? [];
  assertEquals(secondCallMessages[secondCallMessages.length - 1]?.role, "tool");
});

Deno.test("P5-KYRA-19: the 4th free-tier conversation today is blocked with an upgrade prompt", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([]);
  const response = await handleKyraRespond(
    request({ text: "hello" }),
    deps(provider, fakeStore(recording, { countThreadsCreatedSince: () => Promise.resolve(3) })),
  );
  assertEquals(response.status, 429);
  const body = await envelope(response);
  const error = body["error"] as Record<string, unknown>;
  assertEquals(error["category"], "subscription_limit_reached");
  assertEquals(error["details"], {
    limit: "kyra_conversation_daily",
    limit_count: 3,
    remaining: 0,
    resets_at: "2026-08-17T00:00:00.000Z",
  });
  assert(String(error["message"]).includes("Premium"));
  // Nothing was created or spent.
  assertEquals(recording.threadsCreated.length, 0);
  assertEquals(provider.requests.length, 0);
});

Deno.test("Kyra burst rate limit returns the exact Retry-After reset", async () => {
  const response = await handleKyraRespond(
    request({ text: "hello" }),
    deps(
      scriptedProvider([]),
      fakeStore(emptyRecording()),
      {},
      { check: () => ({ allowed: false, remaining: 0, retryAfterSeconds: 23 }) },
    ),
  );
  assertEquals(response.status, 429);
  assertEquals(response.headers.get("Retry-After"), "23");
});

Deno.test("P5-KYRA-19: premium users are never blocked by the daily limit", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([{ kind: "result", result: { message: goodJson() } }]);
  const response = await handleKyraRespond(
    request({ text: "hello" }),
    deps(
      provider,
      fakeStore(recording, {
        countThreadsCreatedSince: () => Promise.resolve(50),
        hasActivePremiumSubscription: () => Promise.resolve(true),
      }),
    ),
  );
  assertEquals(response.status, 200);
});

Deno.test("P5-KYRA-19: the atomic conversation gate admits the third free conversation", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([{ kind: "result", result: { message: goodJson() } }]);
  let created = 0;
  const response = await handleKyraRespond(
    request({ text: "third conversation" }),
    deps(
      provider,
      fakeStore(recording, {
        createThreadWithDailyLimit: () => {
          created++;
          return Promise.resolve({
            threadID: THREAD,
            allowed: true,
            replayed: false,
            threadDeleted: false,
            limitCount: 3,
            remaining: 0,
            resetsAt: "2026-08-17T00:00:00Z",
          });
        },
      }),
    ),
  );
  assertEquals(response.status, 200);
  assertEquals(created, 1);
  assertEquals(provider.requests.length, 1);
});

Deno.test("builder outfit quota denial is typed and happens before thread or provider work", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([]);
  let reserveCalls = 0;
  const response = await handleKyraRespond(
    request({ text: "Complete this outfit", outfit_builder_completion: true }),
    {
      ...deps(provider, fakeStore(recording)),
      outfitGenerationQuota: {
        isPremium: () => Promise.resolve(false),
        reserve: () => {
          reserveCalls++;
          return Promise.resolve({
            allowed: false,
            remaining: 0,
            resetsAt: "2026-08-17T00:00:00Z",
            limitCount: 5,
            reservation_id: null,
            replay_payload: null,
            in_flight: false,
          });
        },
        finish: () => Promise.resolve(),
      },
    },
  );
  assertEquals(response.status, 429);
  const body = await envelope(response);
  const error = body["error"] as Record<string, unknown>;
  assertEquals(error["category"], "subscription_limit_reached");
  assertEquals(error["details"], {
    limit: "outfit_generation_daily",
    limit_count: 5,
    remaining: 0,
    resets_at: "2026-08-17T00:00:00Z",
  });
  assertEquals(reserveCalls, 1);
  assertEquals(recording.threadsCreated.length, 0);
  assertEquals(recording.userMessages.length, 0);
  assertEquals(provider.requests.length, 0);
});

Deno.test("builder reservation is released when Kyra produces no outfit", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([{ kind: "result", result: { message: goodJson() } }]);
  const finishes: Array<{ succeeded: boolean; result: unknown }> = [];
  const response = await handleKyraRespond(
    request({ text: "Complete this outfit", outfit_builder_completion: true }),
    {
      ...deps(provider, fakeStore(recording)),
      outfitGenerationQuota: {
        isPremium: () => Promise.resolve(false),
        reserve: () =>
          Promise.resolve({
            allowed: true,
            remaining: 4,
            resetsAt: "2026-08-17T00:00:00Z",
            limitCount: 5,
            reservation_id: "44444444-0000-4000-8000-000000000001",
            replay_payload: null,
            in_flight: false,
          }),
        finish: (_userID, _reservationID, succeeded, result) => {
          finishes.push({ succeeded, result });
          return Promise.resolve();
        },
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(finishes, [{ succeeded: false, result: null }]);
});

Deno.test("create_outfit quota denial on an existing thread returns typed 429", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([{
    kind: "result",
    result: {
      finishReason: "tool_calls",
      toolCalls: [{
        id: "builder_call_1",
        name: "create_outfit",
        arguments: {
          item_ids: [
            PACKET_ITEM,
            "dddddddd-0000-4000-8000-000000000002",
            "dddddddd-0000-4000-8000-000000000003",
          ],
          occasion_tags: [],
          reason: "A balanced outfit.",
        },
      }],
    },
  }]);
  const rows = [
    {
      id: PACKET_ITEM,
      category: "top",
      primary_color: "olive",
      secondary_colors: [],
      pattern: "solid",
      material: [],
      fit: "regular",
      seasonality: [],
      formality_score: 40,
      warmth_score: 35,
      water_resistance_score: 20,
      laundry_state: "clean",
      availability_state: "available",
    },
    {
      id: "dddddddd-0000-4000-8000-000000000002",
      category: "bottom",
      primary_color: "navy",
      secondary_colors: [],
      pattern: "solid",
      material: [],
      fit: "regular",
      seasonality: [],
      formality_score: 40,
      warmth_score: 35,
      water_resistance_score: 20,
      laundry_state: "clean",
      availability_state: "available",
    },
    {
      id: "dddddddd-0000-4000-8000-000000000003",
      category: "shoes",
      primary_color: "brown",
      secondary_colors: [],
      pattern: "solid",
      material: [],
      fit: "regular",
      seasonality: [],
      formality_score: 40,
      warmth_score: 35,
      water_resistance_score: 20,
      laundry_state: "clean",
      availability_state: "available",
    },
  ] as ClosetItemMapperRow[];
  const response = await handleKyraRespond(
    request({ text: "Create a new outfit", thread_id: THREAD }),
    {
      ...deps(provider, fakeStore(recording, { listItemsByIds: () => Promise.resolve(rows) })),
      outfitGenerationQuota: {
        isPremium: () => Promise.resolve(false),
        reserve: () =>
          Promise.resolve({
            allowed: false,
            remaining: 0,
            resetsAt: "2026-08-17T00:00:00Z",
            limitCount: 5,
            reservation_id: null,
            replay_payload: null,
            in_flight: false,
          }),
        finish: () => Promise.resolve(),
      },
    },
  );
  assertEquals(response.status, 429);
  const body = await envelope(response);
  const error = body["error"] as Record<string, unknown>;
  assertEquals(error["category"], "subscription_limit_reached");
  assertEquals((error["details"] as Record<string, unknown>)["limit"], "outfit_generation_daily");
  assertEquals(provider.requests.length, 1);
});

Deno.test("P5-KYRA-19: continuing an existing thread does not consume the daily allowance", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([{ kind: "result", result: { message: goodJson() } }]);
  const response = await handleKyraRespond(
    request({ text: "and for tomorrow?", thread_id: THREAD }),
    deps(provider, fakeStore(recording, { countThreadsCreatedSince: () => Promise.resolve(3) })),
  );
  assertEquals(response.status, 200);
  assertEquals(recording.threadsCreated.length, 0);
});

Deno.test("an unknown thread id is not found — RLS makes unowned and nonexistent identical", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([]);
  const response = await handleKyraRespond(
    request({ text: "hi", thread_id: "bbbbbbbb-0000-4000-8000-00000000dead" }),
    deps(provider, fakeStore(recording)),
  );
  assertEquals(response.status, 404);
});

Deno.test("missing Authorization is 401 before any work happens", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([]);
  const response = await handleKyraRespond(
    new Request("http://localhost/kyra/respond", {
      method: "POST",
      body: JSON.stringify({ body: { text: "hi" } }),
    }),
    deps(provider, fakeStore(recording)),
  );
  assertEquals(response.status, 401);
  assertEquals(provider.requests.length, 0);
});

Deno.test("studio inspiration attachment is owner-resolved and sent as image input", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([{ kind: "result", result: { message: goodJson() } }]);
  const generationID = "99999999-9999-4999-8999-999999999999";
  const signedURL =
    "https://project.supabase.co/storage/v1/object/sign/user-content/result.png?token=secret";
  const response = await handleKyraRespond(
    request({
      text: "Help me refine this generated look.",
      attachments: [{ type: "studio_inspiration", value: generationID }],
    }),
    {
      ...deps(provider, fakeStore(recording)),
      resolveStudioInspiration: (userID, id) => {
        assertEquals(userID, USER);
        assertEquals(id, generationID);
        return Promise.resolve(signedURL);
      },
    },
  );
  assertEquals(response.status, 200);
  const firstRequest = provider.requests[0];
  const userMessage = firstRequest?.messages.find((message) => message.role === "user");
  assertEquals(userMessage?.images, [{ url: signedURL }]);
  assertEquals(JSON.stringify(firstRequest?.contextPacket).includes(generationID), true);
  assertEquals(recording.userMessages[0]?.content.includes(signedURL), false);
  assertEquals(recording.userMessages[0]?.studioGenerationID, generationID);
});

Deno.test("reopened Kyra history re-resolves only its newest Studio image reference", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([{ kind: "result", result: { message: goodJson() } }]);
  const newestGeneration = "99999999-9999-4999-8999-999999999999";
  const signedURL =
    "https://project.supabase.co/storage/v1/object/sign/user-content/users/aaaaaaaa-0000-4000-8000-000000000001/studio/99999999-9999-4999-8999-999999999999/result.png?token=secret";
  const resolverCalls: string[] = [];
  const response = await handleKyraRespond(
    request({ text: "Can you refine that?", thread_id: THREAD }),
    {
      ...deps(
        provider,
        fakeStore(recording, {
          listRecentMessages: () =>
            Promise.resolve([
              {
                role: "user",
                content: "Look at this first look.",
                structured_payload: null,
                // Repeated reference UUIDs still attach only to the newest row.
                studio_generation_id: newestGeneration,
              },
              {
                role: "assistant",
                content: "I like the silhouette.",
                structured_payload: { message: "I like the silhouette." },
              },
              {
                role: "user",
                content: "And this newer version?",
                structured_payload: null,
                studio_generation_id: newestGeneration,
              },
            ]),
        }),
      ),
      resolveStudioInspiration: (_userID, id) => {
        resolverCalls.push(id);
        return Promise.resolve(signedURL);
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(resolverCalls, [newestGeneration]);
  const messages = provider.requests[0]?.messages ?? [];
  const attachedMessages = messages.filter((message) => (message.images?.length ?? 0) > 0);
  assertEquals(attachedMessages.length, 1);
  assertEquals(attachedMessages[0]?.content, "And this newer version?");
  assertEquals(attachedMessages[0]?.images, [{ url: signedURL }]);
  assertEquals(recording.userMessages[0]?.content.includes(signedURL), false);
  assertEquals(JSON.stringify(recording.assistantMessages).includes(signedURL), false);
});

Deno.test("unavailable historical Studio image gets a no-vision system instruction", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([{ kind: "result", result: { message: goodJson() } }]);
  const generationID = "99999999-9999-4999-8999-999999999999";
  const response = await handleKyraRespond(
    request({ text: "What did you think of that?", thread_id: THREAD }),
    {
      ...deps(
        provider,
        fakeStore(recording, {
          listRecentMessages: () =>
            Promise.resolve([{
              role: "user",
              content: "Here is my look.",
              structured_payload: null,
              studio_generation_id: generationID,
            }]),
        }),
      ),
      resolveStudioInspiration: () => Promise.resolve(null),
    },
  );
  assertEquals(response.status, 200);
  const messages = provider.requests[0]?.messages ?? [];
  assertEquals(
    messages.some((message) =>
      message.role === "system" &&
      message.content.includes("Do not claim to see or describe its visual contents")
    ),
    true,
  );
  assertEquals(messages.some((message) => (message.images?.length ?? 0) > 0), false);
});

Deno.test("unavailable Studio inspiration references are rejected before conversation creation", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([]);
  const response = await handleKyraRespond(
    request({
      text: "Help me refine this generated look.",
      attachments: [{ type: "studio_inspiration", value: "99999999-9999-4999-8999-999999999999" }],
    }),
    {
      ...deps(provider, fakeStore(recording)),
      resolveStudioInspiration: () => Promise.resolve(null),
    },
  );
  assertEquals(response.status, 404);
  assertEquals(recording.threadsCreated, []);
  assertEquals(provider.requests, []);
});

Deno.test("docs/09 §2.1: confidence below threshold retries on Terra; Terra's answer is used outright", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([
    { kind: "result", result: { message: goodJson({ confidence: 0.3 }) } }, // luna, hedged
    {
      kind: "result",
      result: {
        message: goodJson({ confidence: 0.85, message: "Terra's stronger answer." }),
      },
    },
  ]);
  const response = await handleKyraRespond(
    request({ text: "hard question" }),
    deps(provider, fakeStore(recording)),
  );
  assertEquals(response.status, 200);
  const data = (await envelope(response))["data"] as Record<string, unknown>;
  assertEquals(data["content"], "Terra's stronger answer.");
  assertEquals(provider.requests.map((r) => r.tier), ["luna", "terra"]);
  const metadata = data["model_metadata"] as Record<string, unknown>;
  assertEquals(metadata["escalated"], true);
  assertEquals(metadata["tier"], "terra");
});

Deno.test("docs/09 §2.1: a failed Terra retry leaves the valid Luna answer standing", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([
    { kind: "result", result: { message: goodJson({ confidence: 0.3 }) } },
    { kind: "throw", error: new ProviderError("PROVIDER_UNAVAILABLE", false, "down") },
  ]);
  const response = await handleKyraRespond(
    request({ text: "hard question" }),
    deps(provider, fakeStore(recording)),
  );
  assertEquals(response.status, 200);
  const data = (await envelope(response))["data"] as Record<string, unknown>;
  const payload = data["structured_payload"] as Record<string, unknown>;
  assertEquals(payload["confidence"], 0.3); // hedged, honest, not a fallback
  assertEquals(payload["intent"], "daily_outfit");
});

Deno.test("docs/06 §6 + docs/09 §2.2: malformed output repairs on the same tier first", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([
    { kind: "result", result: { message: "not json at all" } },
    { kind: "result", result: { message: goodJson() } }, // luna repair succeeds
  ]);
  const response = await handleKyraRespond(
    request({ text: "hi" }),
    deps(provider, fakeStore(recording)),
  );
  assertEquals(response.status, 200);
  const data = (await envelope(response))["data"] as Record<string, unknown>;
  assertEquals(data["content"], "I'd wear the olive knit polo tonight.");
  assertEquals(provider.requests.map((r) => r.tier), ["luna", "luna"]);
  // The repair pass carries no tools — reformatting is not a tool problem.
  assertEquals(provider.requests[1]?.tools.length, 0);
});

Deno.test("docs/06 §6: both repairs failing produces the in-voice safe fallback, persisted", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([
    { kind: "result", result: { message: "broken 1" } },
    { kind: "result", result: { message: "broken 2" } }, // luna repair fails
    { kind: "result", result: { message: "broken 3" } }, // terra repair fails
  ]);
  const response = await handleKyraRespond(
    request({ text: "hi" }),
    deps(provider, fakeStore(recording)),
  );
  assertEquals(response.status, 200); // never a raw error to the chat UI
  const data = (await envelope(response))["data"] as Record<string, unknown>;
  const payload = data["structured_payload"] as Record<string, unknown>;
  assertEquals(payload["confidence"], 0);
  assertEquals(payload["intent"], "general");
  assert(String(payload["message"]).includes("train of thought"));
  assertEquals(provider.requests.map((r) => r.tier), ["luna", "luna", "terra"]);
  assertEquals(recording.assistantMessages.length, 1); // the turn still persists
});

Deno.test("docs/09 §2.3: a thrashing tool loop escalates to Terra with history preserved", async () => {
  const recording = emptyRecording();
  const toolCallResult: ScriptEntry = {
    kind: "result",
    result: {
      finishReason: "tool_calls",
      toolCalls: [{ id: "call_x", name: "get_weather", arguments: {} }],
    },
  };
  const provider = scriptedProvider([
    toolCallResult,
    toolCallResult,
    toolCallResult,
    toolCallResult, // luna cap = 4 iterations, all thrashing
    { kind: "result", result: { message: goodJson() } }, // terra resolves it
  ]);
  const response = await handleKyraRespond(
    request({ text: "hi" }),
    deps(provider, fakeStore(recording)),
  );
  assertEquals(response.status, 200);
  assertEquals(provider.requests.map((r) => r.tier), [
    "luna",
    "luna",
    "luna",
    "luna",
    "terra",
  ]);
  // Terra received the preserved tool-call history, not a fresh start.
  const terraMessages = provider.requests[4]?.messages ?? [];
  assert(terraMessages.some((message) => message.role === "tool"));
});

Deno.test("docs/06 §6: a provider outage becomes an in-voice fallback, never a 5xx to the chat", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([
    { kind: "throw", error: new ProviderError("PROVIDER_UNAVAILABLE", false, "no key") },
  ]);
  const response = await handleKyraRespond(
    request({ text: "hi" }),
    deps(provider, fakeStore(recording)),
  );
  assertEquals(response.status, 200);
  const data = (await envelope(response))["data"] as Record<string, unknown>;
  const payload = data["structured_payload"] as Record<string, unknown>;
  assertEquals(payload["confidence"], 0);
  assert(String(payload["message"]).includes("couldn't reach"));
});

Deno.test("a missing provider key is identified separately from a transient outage", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([
    {
      kind: "throw",
      error: new ProviderError(
        "PROVIDER_UNAVAILABLE",
        false,
        "stylist key missing",
        undefined,
        true,
      ),
    },
  ]);
  const response = await handleKyraRespond(
    request({ text: "hi" }),
    deps(provider, fakeStore(recording)),
  );
  assertEquals(response.status, 200);
  const data = (await envelope(response))["data"] as Record<string, unknown>;
  const metadata = data["model_metadata"] as Record<string, unknown>;
  assertEquals(metadata["fallback_reason"], "provider_not_configured");
});

Deno.test("hallucinated closet-item cards are dropped before persistence and the wire", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([
    {
      kind: "result",
      result: {
        message: goodJson({
          cards: [
            { type: "closet_item", closet_item_id: PACKET_ITEM }, // real: in the packet
            { type: "closet_item", closet_item_id: "deadbeef-0000-4000-8000-000000000000" },
          ],
        }),
      },
    },
  ]);
  const response = await handleKyraRespond(
    request({ text: "hi" }),
    deps(provider, fakeStore(recording)),
  );
  const data = (await envelope(response))["data"] as Record<string, unknown>;
  const payload = data["structured_payload"] as Record<string, unknown>;
  const cards = payload["cards"] as Array<Record<string, unknown>>;
  assertEquals(cards.length, 1);
  assertEquals(cards[0]!["closet_item_id"], PACKET_ITEM);
  // The persisted row matches the wire exactly — no divergent copies.
  const persisted = recording.assistantMessages[0]!.structuredPayload;
  assertEquals((persisted["cards"] as unknown[]).length, 1);
});

Deno.test("memory_proposals reflect what save_preference actually did, not model claims", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([
    {
      kind: "result",
      result: {
        finishReason: "tool_calls",
        toolCalls: [{
          id: "call_1",
          name: "save_preference",
          arguments: {
            memory_type: "fit_note",
            content: "Slim cuts don't work through the chest",
            confidence: 0.85,
            source_message_id: "11111111-0000-4000-8000-00000000fake",
          },
        }],
      },
    },
    {
      kind: "result",
      result: {
        // The model claims a DIFFERENT proposal in its final response; the
        // trace-derived truth must win.
        message: goodJson({
          memory_proposals: [{
            memory_type: "preference",
            content: "A proposal the model made up without a tool call",
            confidence: 0.9,
          }],
        }),
      },
    },
  ]);
  const response = await handleKyraRespond(
    request({ text: "Slim never fits my chest, remember that" }),
    deps(provider, fakeStore(recording)),
  );
  const data = (await envelope(response))["data"] as Record<string, unknown>;
  const payload = data["structured_payload"] as Record<string, unknown>;
  const proposals = payload["memory_proposals"] as Array<Record<string, unknown>>;
  assertEquals(proposals.length, 1);
  assertEquals(proposals[0]!["memory_id"], SAVED_MEMORY);
  assertEquals(proposals[0]!["action_taken"], "created");
  assertEquals(proposals[0]!["content"], "Slim cuts don't work through the chest");
  assertEquals(proposals[0]!["memory_type"], "fit_note");
  // The write really happened, with the server-known source message id.
  assertEquals(recording.memoriesInserted.length, 1);
});

Deno.test("a failing tool degrades the turn honestly instead of failing it", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([
    {
      kind: "result",
      result: {
        finishReason: "tool_calls",
        toolCalls: [{ id: "call_1", name: "get_schedule", arguments: {} }],
      },
    },
    { kind: "result", result: { message: goodJson({ confidence: 0.6 }) } },
  ]);
  let calls = 0;
  const store = fakeStore(recording, {
    listUpcomingOccasions: () => {
      calls += 1;
      return Promise.reject(new Error("db unreachable"));
    },
  });
  const response = await handleKyraRespond(request({ text: "hi" }), deps(provider, store));
  assertEquals(response.status, 200);
  // Retried once (packet fetch also calls it once and degrades separately).
  assert(calls >= 2);
  // The model received a structured failure result, visible in its messages.
  const secondCall = provider.requests[1]!;
  const toolMessage = secondCall.messages[secondCall.messages.length - 1]!;
  assert(toolMessage.content.includes("TOOL_EXECUTION_FAILED"));
});

Deno.test("live product tool registration replaces the stub and relays a missing catalog result", async () => {
  const recording = emptyRecording();
  let lookups = 0;
  const provider = scriptedProvider([
    {
      kind: "result",
      result: {
        finishReason: "tool_calls",
        toolCalls: [{
          id: "product_call",
          name: "analyze_product",
          arguments: { product_candidate_id: PACKET_ITEM },
        }],
      },
    },
    { kind: "result", result: { message: goodJson() } },
  ]);
  const response = await handleKyraRespond(request({ text: "Is this catalog item useful?" }), {
    ...deps(provider, fakeStore(recording)),
    analyzeProduct: {
      find: () => {
        lookups++;
        return Promise.resolve(null);
      },
      extract: () => {
        throw new Error("Unexpected extraction");
      },
      evaluate: () => {
        throw new Error("Unexpected evaluation");
      },
    },
  });
  assertEquals(response.status, 200);
  assertEquals(lookups, 1);
  const definition = provider.requests[0]?.tools.find((tool) => tool.name === "analyze_product");
  assert(definition && !definition.description.includes("NOT YET AVAILABLE"));
  const toolMessage = provider.requests[1]?.messages.find((message) => message.role === "tool");
  assert(toolMessage?.content?.includes("PRODUCT_NOT_FOUND"));
  assert(!toolMessage?.content?.includes("NOT_BUILT"));
});

Deno.test("Studio cost question is persisted before its private approval record", async () => {
  const recording = emptyRecording();
  const provider = scriptedProvider([
    {
      kind: "result",
      result: {
        finishReason: "tool_calls",
        toolCalls: [{
          id: "preview_call",
          name: "generate_studio_preview",
          arguments: { item_ids: [PACKET_ITEM], reference_image_id: PACKET_ITEM },
        }],
      },
    },
    { kind: "result", result: { message: goodJson() } },
  ]);
  let prepared = 0;
  const response = await handleKyraRespond(request({ text: "Can I see a preview?" }), {
    ...deps(
      provider,
      fakeStore(recording, { listOwnedItemIds: () => Promise.resolve([PACKET_ITEM]) }),
    ),
    studio: {
      referenceIDs: () => Promise.resolve([PACKET_ITEM]),
      confirmations: {
        pending: () => Promise.resolve(null),
        close: () => {
          throw new Error("Unexpected closure");
        },
        prepare: (user, thread, prompt, selection) => {
          assertEquals(user, USER);
          assertEquals(thread, THREAD);
          assertEquals(prompt, ASSISTANT_MESSAGE);
          assertEquals(recording.assistantMessages.length, 1);
          assert(recording.assistantMessages[0]?.content.includes("uses one preview"));
          assertEquals(selection.itemIds, [PACKET_ITEM]);
          prepared++;
          return Promise.resolve({
            id: USER_MESSAGE,
            promptMessageID: prompt,
            selection,
            selectionKey: "fixture",
            expiresAt: "2026-10-09T00:30:00Z",
          });
        },
      },
      preview: (turn) => ({
        userText: turn.userText,
        pending: null,
        currentConsentTermsVersion: "fixture",
        resolveOwnedConsentedReference: () => {
          throw new Error("No approval yet");
        },
        enqueue: () => {
          throw new Error("No approval yet");
        },
      }),
    },
  });
  assertEquals(response.status, 200);
  assertEquals(prepared, 1);
  assertEquals(recording.assistantMessages[0]?.structuredPayload.cards, [{
    type: "closet_item",
    closet_item_id: PACKET_ITEM,
  }]);
});

Deno.test("cancelled preview closes approval and cannot prepare a replacement in the same turn", async () => {
  const { studioSelectionKey } = await import("./tools/generateStudioPreview.ts");
  const recording = emptyRecording();
  const selection = {
    outfitId: null,
    itemIds: [PACKET_ITEM],
    referenceImageId: PACKET_ITEM,
    pose: "standing" as const,
    background: "studio-neutral",
    resolution: "draft" as const,
  };
  let closed = 0;
  const provider = scriptedProvider([
    {
      kind: "result",
      result: {
        finishReason: "tool_calls",
        toolCalls: [{
          id: "preview_call",
          name: "generate_studio_preview",
          arguments: { item_ids: [PACKET_ITEM], reference_image_id: PACKET_ITEM },
        }],
      },
    },
    { kind: "result", result: { message: goodJson() } },
  ]);
  const response = await handleKyraRespond(
    request({ text: "Don't generate this preview", thread_id: THREAD }),
    {
      ...deps(
        provider,
        fakeStore(recording, {
          listRecentMessages: () =>
            Promise.resolve([{
              id: ASSISTANT_MESSAGE,
              role: "assistant",
              content: "It uses one preview. Generate it?",
              structured_payload: null,
            }]),
        }),
      ),
      studio: {
        confirmations: {
          pending: (_user, _thread, prompt) => {
            assertEquals(prompt, ASSISTANT_MESSAGE);
            return Promise.resolve({
              id: USER_MESSAGE,
              promptMessageID: ASSISTANT_MESSAGE,
              selection,
              selectionKey: studioSelectionKey(selection),
              expiresAt: "2099-01-01T00:00:00Z",
            });
          },
          close: () => {
            closed++;
            return Promise.resolve();
          },
          prepare: () => {
            throw new Error("Cancellation cannot create a new approval");
          },
        },
        preview: (turn) => {
          assertEquals(turn.proposal, null);
          return {
            userText: turn.userText,
            pending: null,
            currentConsentTermsVersion: "fixture",
            resolveOwnedConsentedReference: () => {
              throw new Error("Cancelled");
            },
            enqueue: () => {
              throw new Error("Cancelled");
            },
          };
        },
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(closed, 1);
  assert(
    provider.requests[1]?.messages.some((message) =>
      message.content?.includes("PREVIEW_CANCELLED")
    ),
  );
});

Deno.test("matching saved yes approval submits once and closes its confirmation", async () => {
  const { studioSelectionKey } = await import("./tools/generateStudioPreview.ts");
  const recording = emptyRecording();
  const selection = {
    outfitId: null,
    itemIds: [PACKET_ITEM],
    referenceImageId: PACKET_ITEM,
    pose: "standing" as const,
    background: "studio-neutral",
    resolution: "draft" as const,
  };
  const proposal = {
    id: USER_MESSAGE,
    promptMessageID: ASSISTANT_MESSAGE,
    selection,
    selectionKey: studioSelectionKey(selection),
    expiresAt: "2099-01-01T00:00:00Z",
  };
  let submitted = 0;
  let closed = 0;
  const provider = scriptedProvider([
    {
      kind: "result",
      result: {
        finishReason: "tool_calls",
        toolCalls: [{
          id: "preview_call",
          name: "generate_studio_preview",
          arguments: { item_ids: [PACKET_ITEM], reference_image_id: PACKET_ITEM },
        }],
      },
    },
    { kind: "result", result: { message: goodJson() } },
  ]);
  const response = await handleKyraRespond(request({ text: "yes" }), {
    ...deps(
      provider,
      fakeStore(recording, {
        listRecentMessages: () =>
          Promise.resolve([{
            id: ASSISTANT_MESSAGE,
            role: "assistant",
            content: "It uses one preview. Generate it?",
            structured_payload: null,
          }]),
      }),
    ),
    studio: {
      confirmations: {
        pending: () => Promise.resolve(proposal),
        close: (_user, _thread, id) => {
          assertEquals(id, proposal.id);
          closed++;
          return Promise.resolve();
        },
        prepare: () => {
          throw new Error("Accepted approval should not be replaced");
        },
      },
      preview: (turn) => {
        assertEquals(turn.proposal?.id, proposal.id);
        return {
          userText: turn.userText,
          pending: { selectionKey: proposal.selectionKey, askedAboutGenerationCost: true },
          currentConsentTermsVersion: "fixture",
          resolveOwnedConsentedReference: () =>
            Promise.resolve({ path: "owned", termsVersion: "fixture" }),
          enqueue: (selected) => {
            assertEquals(selected, selection);
            submitted++;
            return Promise.resolve({
              generationId: PACKET_ITEM,
              status: "queued",
              estimatedSeconds: 120,
            });
          },
        };
      },
    },
  });
  assertEquals(response.status, 200);
  const payload = await response.json();
  assertEquals(
    payload.data.structured_payload.suggested_actions.find((action: { id: string }) =>
      action.id === "studio-preview:" + PACKET_ITEM
    )?.label,
    "Open preview",
  );
  assertEquals(submitted, 1);
  assertEquals(closed, 1);
});

Deno.test("preview proposals with unavailable items, consent or resolution cannot prepare approval", async () => {
  for (const scenario of ["missing_item", "missing_photo", "hi_res"]) {
    const recording = emptyRecording();
    const provider = scriptedProvider([
      {
        kind: "result",
        result: {
          finishReason: "tool_calls",
          toolCalls: [{
            id: "preview_call",
            name: "generate_studio_preview",
            arguments: {
              item_ids: [PACKET_ITEM],
              reference_image_id: PACKET_ITEM,
              resolution: scenario === "hi_res" ? "hi_res" : "draft",
            },
          }],
        },
      },
      { kind: "result", result: { message: goodJson() } },
    ]);
    const response = await handleKyraRespond(request({ text: "Can I see a preview?" }), {
      ...deps(
        provider,
        fakeStore(recording, {
          listOwnedItemIds: () => Promise.resolve(scenario === "missing_item" ? [] : [PACKET_ITEM]),
        }),
      ),
      studio: {
        referenceIDs: () => Promise.resolve(scenario === "missing_photo" ? [] : [PACKET_ITEM]),
        confirmations: {
          pending: () => Promise.resolve(null),
          close: () => {
            throw new Error("Unexpected closure");
          },
          prepare: () => {
            throw new Error("Unavailable selection cannot receive approval");
          },
        },
        preview: (turn) => ({
          userText: turn.userText,
          pending: null,
          currentConsentTermsVersion: "fixture",
          resolveOwnedConsentedReference: () => {
            throw new Error("No approval");
          },
          enqueue: () => {
            throw new Error("No approval");
          },
        }),
      },
    });
    assertEquals(response.status, 200);
    assertEquals(recording.assistantMessages[0]?.structuredPayload.cards, []);
    assert(!recording.assistantMessages[0]?.content.includes("uses one preview"));
  }
});

Deno.test("handler binds builder locks and owned-only policy from the authenticated request", async () => {
  const recording = emptyRecording();
  const top = "00000000-0000-4000-8000-000000000101";
  const bottom = "00000000-0000-4000-8000-000000000102";
  const shoes = "00000000-0000-4000-8000-000000000103";
  const competingTop = "00000000-0000-4000-8000-000000000104";
  const rows: ClosetItemMapperRow[] = [
    top,
    competingTop,
    bottom,
    shoes,
  ].map((id, index) => ({
    id,
    category: index < 2 ? "top" : index === 2 ? "bottom" : "shoes",
    primary_color: "navy",
    secondary_colors: [],
    pattern: "solid",
    material: [],
    fit: "regular",
    seasonality: [],
    formality_score: 50,
    warmth_score: 40,
    water_resistance_score: 20,
    laundry_state: "clean",
    availability_state: "available",
  }));
  const inserted: Array<{ items: readonly { closetItemId: string | null; role: string }[] }> = [];
  const store = fakeStore(recording, {
    listItemsByIds: (ids) => Promise.resolve(rows.filter((row) => ids.includes(row.id))),
    insertOutfit: (_ownerID, record) => {
      inserted.push(record);
      return Promise.resolve("ffffffff-0000-4000-8000-000000000091");
    },
  });
  const provider = scriptedProvider([
    {
      kind: "result",
      result: {
        finishReason: "tool_calls",
        toolCalls: [{
          id: "builder_call",
          name: "create_outfit",
          arguments: {
            item_ids: [competingTop, bottom, shoes],
            reason: "The locked top anchors the look.",
          },
        }],
      },
    },
    { kind: "result", result: { message: goodJson() } },
  ]);

  const response = await handleKyraRespond(
    request({
      text: "Finish the outfit.",
      locked_closet_item_ids: [top],
      outfit_builder_completion: true,
    }),
    deps(provider, store),
  );

  assertEquals(response.status, 200);
  assertEquals(inserted.length, 1);
  assertEquals(
    inserted[0]?.items.filter((item) => item.role === "top").map((item) => item.closetItemId),
    [top],
  );
});
