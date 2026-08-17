import { assert, assertEquals, assertRejects } from "@std/assert";
import { ProviderError } from "../_shared/providers/types.ts";
import type { StylistCompletionRequest } from "../_shared/providers/stylistReasoning.ts";
import { LiveStylistProvider } from "./liveStylistProvider.ts";

const CTX = { requestId: "req-1", userId: "user-1", timeoutMs: 5_000 };

function request(overrides: Partial<StylistCompletionRequest> = {}): StylistCompletionRequest {
  return {
    systemPrompt: "You are Kyra.",
    contextPacket: { packet_version: "1.0" },
    messages: [{ role: "user", content: "What should I wear?" }],
    tools: [{
      name: "get_weather",
      description: "Weather",
      parametersSchema: { type: "object", properties: {} },
    }],
    responseSchema: { type: "object" },
    maxOutputTokens: 800,
    temperature: 0.6,
    stream: false,
    tier: "luna",
    ...overrides,
  };
}

function provider(
  handler: (input: Request) => Response | Promise<Response>,
  captured: Array<Record<string, unknown>>,
): LiveStylistProvider {
  return new LiveStylistProvider({
    apiKey: "test-key",
    modelForTier: { luna: "model-luna", terra: "model-terra", sol: "model-terra" },
    fetchImpl: async (input, init) => {
      const req = new Request(input as string | URL, init);
      captured.push(JSON.parse(await req.clone().text()) as Record<string, unknown>);
      return await handler(req);
    },
  });
}

function okResponse(body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.test("maps the Astra-shaped request onto the vendor wire, tier onto model id", async () => {
  const captured: Array<Record<string, unknown>> = [];
  const live = provider(
    () =>
      okResponse({
        model: "model-luna-2026-08",
        choices: [{ message: { content: '{"ok":true}' }, finish_reason: "stop" }],
        usage: { prompt_tokens: 120, completion_tokens: 40 },
      }),
    captured,
  );
  const result = await live.complete(request(), CTX);

  const sent = captured[0]!;
  assertEquals(sent["model"], "model-luna");
  // No temperature on the wire — the pinned models reject non-default values.
  assertEquals(sent["temperature"], undefined);
  const messages = sent["messages"] as Array<Record<string, unknown>>;
  assertEquals(messages[0]!["role"], "system");
  assert(String(messages[1]!["content"]).includes("CONTEXT PACKET"));
  const tools = sent["tools"] as Array<Record<string, unknown>>;
  assertEquals(tools.length, 1);
  assertEquals((tools[0]!["function"] as Record<string, unknown>)["name"], "get_weather");

  assertEquals(result.message, '{"ok":true}');
  assertEquals(result.finishReason, "stop");
  assertEquals(result.usage, { inputTokens: 120, outputTokens: 40 });
  assertEquals(result.modelIdentifier, "model-luna-2026-08");
});

Deno.test("terra tier selects the terra model", async () => {
  const captured: Array<Record<string, unknown>> = [];
  const live = provider(
    () =>
      okResponse({
        choices: [{ message: { content: "{}" }, finish_reason: "stop" }],
        usage: { prompt_tokens: 1, completion_tokens: 1 },
      }),
    captured,
  );
  await live.complete(request({ tier: "terra" }), CTX);
  assertEquals(captured[0]!["model"], "model-terra");
});

Deno.test("vendor tool_calls parse into Astra-shaped tool calls with JSON arguments", async () => {
  const captured: Array<Record<string, unknown>> = [];
  const live = provider(
    () =>
      okResponse({
        choices: [{
          message: {
            content: null,
            tool_calls: [{
              id: "call_abc",
              type: "function",
              function: { name: "search_closet", arguments: '{"category":["top"]}' },
            }],
          },
          finish_reason: "tool_calls",
        }],
        usage: { prompt_tokens: 10, completion_tokens: 5 },
      }),
    captured,
  );
  const result = await live.complete(request(), CTX);
  assertEquals(result.finishReason, "tool_calls");
  assertEquals(result.toolCalls, [
    { id: "call_abc", name: "search_closet", arguments: { category: ["top"] } },
  ]);
});

Deno.test("assistant tool-call turns and tool results round-trip onto the vendor wire", async () => {
  const captured: Array<Record<string, unknown>> = [];
  const live = provider(
    () =>
      okResponse({
        choices: [{ message: { content: "{}" }, finish_reason: "stop" }],
        usage: { prompt_tokens: 1, completion_tokens: 1 },
      }),
    captured,
  );
  await live.complete(
    request({
      messages: [
        { role: "user", content: "hi" },
        {
          role: "assistant",
          content: "",
          toolCalls: [{ id: "call_1", name: "get_weather", arguments: { date_range_days: 3 } }],
        },
        { role: "tool", content: '{"available":false}', toolCallId: "call_1" },
      ],
    }),
    CTX,
  );
  const messages = captured[0]!["messages"] as Array<Record<string, unknown>>;
  // [system, context, user, assistant(tool_calls), tool]
  const assistant = messages[3]!;
  const toolCalls = assistant["tool_calls"] as Array<Record<string, unknown>>;
  assertEquals(
    (toolCalls[0]!["function"] as Record<string, unknown>)["arguments"],
    '{"date_range_days":3}',
  );
  const tool = messages[4]!;
  assertEquals(tool["role"], "tool");
  assertEquals(tool["tool_call_id"], "call_1");
});

Deno.test("vendor errors map onto the shared taxonomy with honest retryability", async () => {
  const statuses: Array<[number, string, boolean]> = [
    [429, "RATE_LIMITED", true],
    [401, "AUTH_FAILED", false],
    [503, "PROVIDER_UNAVAILABLE", true],
    [400, "PROVIDER_UNAVAILABLE", false],
  ];
  for (const [status, code, retryable] of statuses) {
    const live = provider(() => new Response("{}", { status }), []);
    const error = await assertRejects(() => live.complete(request(), CTX), ProviderError);
    assertEquals(error.code, code);
    assertEquals(error.retryable, retryable);
    assertEquals(error.providerRawStatus, status);
  }
});

Deno.test("completeStream throws rather than faking a stream", async () => {
  const live = provider(() => okResponse({}), []);
  const iterator = live.completeStream(request(), CTX)[Symbol.asyncIterator]();
  await assertRejects(() => iterator.next(), ProviderError);
});
