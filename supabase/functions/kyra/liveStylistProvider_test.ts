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
      assertEquals(req.url, "https://api.openai.com/v1/responses");
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
        status: "completed",
        output: [{ type: "message", content: [{ type: "output_text", text: '{"ok":true}' }] }],
        usage: { input_tokens: 120, output_tokens: 40 },
      }),
    captured,
  );
  const result = await live.complete(request(), CTX);

  const sent = captured[0]!;
  assertEquals(sent["model"], "model-luna");
  // No temperature on the wire — the pinned models reject non-default values.
  assertEquals(sent["temperature"], undefined);
  assertEquals(sent["store"], false);
  assertEquals(sent["reasoning"], { effort: "low" });
  assertEquals(sent["include"], ["reasoning.encrypted_content"]);
  const messages = sent["input"] as Array<Record<string, unknown>>;
  assertEquals(messages[0]!["role"], "system");
  assert(String(messages[1]!["content"]).includes("CONTEXT PACKET"));
  const tools = sent["tools"] as Array<Record<string, unknown>>;
  assertEquals(tools.length, 1);
  assertEquals(tools[0]!["name"], "get_weather");

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
        status: "completed",
        output: [{ type: "message", content: [{ type: "output_text", text: "{}" }] }],
        usage: { input_tokens: 1, output_tokens: 1 },
      }),
    captured,
  );
  await live.complete(request({ tier: "terra" }), CTX);
  assertEquals(captured[0]!["model"], "model-terra");
});

Deno.test("authorized Studio inspiration references become native image input", async () => {
  const captured: Array<Record<string, unknown>> = [];
  const live = provider(
    () =>
      okResponse({
        status: "completed",
        output: [{ type: "message", content: [{ type: "output_text", text: "{}" }] }],
        usage: { input_tokens: 1, output_tokens: 1 },
      }),
    captured,
  );
  await live.complete(
    request({
      messages: [{
        role: "user",
        content: "Please help me refine this flat lay.",
        images: [{
          url:
            "https://project.supabase.co/storage/v1/object/sign/user-content/users/u/studio/g/result.png?token=x",
        }],
      }],
    }),
    CTX,
  );

  const input = captured[0]?.["input"] as Array<Record<string, unknown>>;
  const userMessage = input.find((entry) => entry["role"] === "user");
  assertEquals(userMessage?.["content"], [
    { type: "input_text", text: "Please help me refine this flat lay." },
    {
      type: "input_image",
      image_url:
        "https://project.supabase.co/storage/v1/object/sign/user-content/users/u/studio/g/result.png?token=x",
    },
  ]);
});

Deno.test("vendor tool_calls parse into Astra-shaped tool calls with JSON arguments", async () => {
  const captured: Array<Record<string, unknown>> = [];
  const live = provider(
    () =>
      okResponse({
        status: "completed",
        output: [{
          type: "function_call",
          call_id: "call_abc",
          name: "search_closet",
          arguments: '{"category":["top"]}',
        }],
        usage: { input_tokens: 10, output_tokens: 5 },
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
        status: "completed",
        output: [{ type: "message", content: [{ type: "output_text", text: "{}" }] }],
        usage: { input_tokens: 1, output_tokens: 1 },
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
  const messages = captured[0]!["input"] as Array<Record<string, unknown>>;
  // [system, context, user, assistant(tool_calls), tool]
  const call = messages[3]!;
  assertEquals(call["type"], "function_call");
  assertEquals(call["arguments"], '{"date_range_days":3}');
  const tool = messages[4]!;
  assertEquals(tool["type"], "function_call_output");
  assertEquals(tool["call_id"], "call_1");
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

Deno.test("provider rejection diagnostics retain identifiers without echoed private text", async () => {
  const captured: Array<Record<string, unknown>> = [];
  const live = provider(() =>
    Response.json({
      error: {
        code: "unsupported_value",
        param: "response_format",
        message: "private prompt and token must never be retained",
      },
    }, { status: 400 }), captured);
  const error = await assertRejects(() => live.complete(request(), CTX), ProviderError);
  assertEquals(error.rejectionDetails, { code: "unsupported_value", parameter: "response_format" });
  assert(!error.message.includes("private prompt"));
});

Deno.test("encrypted reasoning is replayed with its tool call inside the same request", async () => {
  const captured: Array<Record<string, unknown>> = [];
  let step = 0;
  const live = provider(() =>
    okResponse(
      step++ === 0
        ? {
          status: "completed",
          output: [
            {
              type: "reasoning",
              id: "rs_fixture",
              summary: [],
              encrypted_content: "opaque-encrypted-fixture",
            },
            {
              type: "function_call",
              id: "fc_fixture",
              call_id: "call_1",
              name: "get_weather",
              arguments: "{}",
            },
          ],
        }
        : {
          status: "completed",
          output: [{ type: "message", content: [{ type: "output_text", text: "{}" }] }],
        },
    ), captured);
  const first = await live.complete(request(), CTX);
  const next = request({
    messages: [
      { role: "user", content: "What should I wear?" },
      { role: "assistant", content: "", toolCalls: first.toolCalls },
      { role: "tool", content: "{}", toolCallId: "call_1" },
    ],
  });
  await live.complete(next, CTX);
  const replay = captured[1]?.input as Array<Record<string, unknown>>;
  assert(
    replay.some((item) =>
      item.type === "reasoning" && item.encrypted_content === "opaque-encrypted-fixture"
    ),
  );
  await live.complete(next, { ...CTX, userId: "peer" });
  const peer = captured[2]?.input as Array<Record<string, unknown>>;
  assert(!peer.some((item) => item.type === "reasoning"));
});

Deno.test("terminal failed and cancelled responses cannot dispatch partial tools", async () => {
  for (const status of ["failed", "cancelled"]) {
    const live = provider(() =>
      Response.json({
        status,
        error: { message: "private provider details" },
        output: [{
          type: "function_call",
          call_id: "partial",
          name: "generate_studio_preview",
          arguments: "{}",
        }],
      }), []);
    const error = await assertRejects(() => live.complete(request(), CTX), ProviderError);
    assertEquals(error.code, "PROVIDER_UNAVAILABLE");
    assert(!error.message.includes("private provider details"));
  }
});
