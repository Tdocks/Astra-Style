// ============================================================================
// kyra/liveStylistProvider.ts
// ============================================================================
// The live `StylistReasoningProvider` adapter (OpenAI GPT-5.6 family) — the
// second implementation of the protocol after
// `style-dna/deterministicStylist.ts`. Lives beside the function that wires
// it, per `_shared/providers/stylistReasoning.ts`'s convention for
// implementations. Constructed ONLY from `kyra/index.ts` when
// `STYLIST_PROVIDER_API_KEY` (spec §25's per-capability name) is set; never
// imported by handler tests, which stay offline against a fake provider.
//
// Every vendor concept — model ids, `tool_calls` wire shape, finish reasons,
// the chat-completions envelope — stays inside this file. The interface's
// header forbids widening it with vendor-shaped fields, and nothing here
// does: tiers map to model ids HERE (`docs/09` §1 assigns tiers as policy;
// the adapter owns what a tier means this month), and the handler never
// sees a vendor string except the opaque `modelIdentifier` it stores for
// attribution.
//
// TEMPERATURE IS ACCEPTED AND NOT SENT, deliberately. The request carries
// `temperature` per the protocol, but the GPT-5.6 reasoning models reject
// any non-default value with HTTP 400 — `openaiVisionAnalysis.ts` documents
// hitting exactly this in production. Sending it would fail every turn; the
// choice is a working stylist versus none. Revisit only after verifying the
// pinned models accept it again.
//
// `completeStream` THROWS, per the protocol's own instruction for
// implementations that cannot stream. The iOS `AstraAPIClient` is a plain
// request/response decoder with no SSE path, so a streaming server would
// have no client to stream to; spec §20's <2.5s first-card target is
// therefore not met by this adapter and that is recorded in the README
// rather than simulated with a fake stream.
// ============================================================================

import type {
  StylistCompletionRequest,
  StylistCompletionResult,
  StylistReasoningProvider,
} from "../_shared/providers/stylistReasoning.ts";
import {
  type ModelTier,
  ProviderError,
  type ProviderRequestContext,
} from "../_shared/providers/types.ts";

export interface LiveStylistProviderDeps {
  readonly apiKey: string;
  /** Tier -> vendor model id. docs/09 §1's policy mapping, owned here. */
  readonly modelForTier: Readonly<Record<ModelTier, string>>;
  readonly fetchImpl?: typeof fetch;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

/** Model-emitted tool arguments arrive as a JSON string; a bad one becomes {}. */
function parseToolArguments(raw: unknown): Record<string, unknown> {
  if (typeof raw !== "string") return {};
  try {
    const parsed = JSON.parse(raw);
    return asRecord(parsed) ?? {};
  } catch {
    return {};
  }
}

export class LiveStylistProvider implements StylistReasoningProvider {
  private readonly apiKey: string;
  private readonly modelForTier: Readonly<Record<ModelTier, string>>;
  private readonly fetchImpl: typeof fetch;

  constructor(deps: LiveStylistProviderDeps) {
    this.apiKey = deps.apiKey;
    this.modelForTier = deps.modelForTier;
    this.fetchImpl = deps.fetchImpl ?? fetch;
  }

  async complete(
    request: StylistCompletionRequest,
    ctx: ProviderRequestContext,
  ): Promise<StylistCompletionResult> {
    const model = this.modelForTier[request.tier];

    const messages: Array<Record<string, unknown>> = [
      { role: "system", content: request.systemPrompt },
      {
        role: "system",
        content: "CONTEXT PACKET (retrieved, budgeted; trust it over memory):\n" +
          JSON.stringify(request.contextPacket),
      },
    ];
    for (const message of request.messages) {
      if (message.role === "tool") {
        messages.push({
          role: "tool",
          tool_call_id: message.toolCallId ?? "",
          content: message.content,
        });
      } else if (message.role === "assistant" && (message.toolCalls?.length ?? 0) > 0) {
        messages.push({
          role: "assistant",
          content: message.content.length > 0 ? message.content : null,
          tool_calls: (message.toolCalls ?? []).map((call) => ({
            id: call.id,
            type: "function",
            function: { name: call.name, arguments: JSON.stringify(call.arguments) },
          })),
        });
      } else {
        messages.push({ role: message.role, content: message.content });
      }
    }

    const body: Record<string, unknown> = {
      model,
      messages,
      max_completion_tokens: request.maxOutputTokens,
      // `strict: false`: the Kyra response schema uses optional properties
      // and anyOf card variants, which strict mode rejects wholesale.
      // Conformance is enforced server-side by parseKyraStructuredResponse
      // plus the docs/06 §6 repair path, which exists for exactly this.
      response_format: {
        type: "json_schema",
        json_schema: { name: "kyra_response", strict: false, schema: request.responseSchema },
      },
    };
    if (request.tools.length > 0) {
      body["tools"] = request.tools.map((tool) => ({
        type: "function",
        function: {
          name: tool.name,
          description: tool.description,
          parameters: tool.parametersSchema,
        },
      }));
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), ctx.timeoutMs);
    try {
      const response = await this.fetchImpl("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        signal: controller.signal,
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.apiKey}`,
          ...(ctx.idempotencyKey ? { "Idempotency-Key": ctx.idempotencyKey } : {}),
        },
        body: JSON.stringify(body),
      });

      if (response.status === 429) {
        throw new ProviderError("RATE_LIMITED", true, "Stylist provider rate limited.", 429);
      }
      if (response.status === 401 || response.status === 403) {
        throw new ProviderError(
          "AUTH_FAILED",
          false,
          "Stylist provider auth failed.",
          response.status,
        );
      }
      if (!response.ok) {
        throw new ProviderError(
          "PROVIDER_UNAVAILABLE",
          response.status >= 500,
          `Stylist provider returned ${response.status}.`,
          response.status,
        );
      }

      const json: unknown = await response.json();
      const root = asRecord(json);
      const choices = root?.["choices"];
      const firstChoice = Array.isArray(choices) ? asRecord(choices[0]) : null;
      const message = asRecord(firstChoice?.["message"]);
      if (message === null) {
        throw new ProviderError("INVALID_INPUT", false, "Stylist provider returned no message.");
      }

      const toolCalls: Array<{ id: string; name: string; arguments: Record<string, unknown> }> = [];
      const rawToolCalls = message["tool_calls"];
      if (Array.isArray(rawToolCalls)) {
        for (const rawCall of rawToolCalls) {
          const call = asRecord(rawCall);
          const fn = asRecord(call?.["function"]);
          if (call === null || fn === null) continue;
          const id = call["id"];
          const name = fn["name"];
          if (typeof id !== "string" || typeof name !== "string") continue;
          toolCalls.push({ id, name, arguments: parseToolArguments(fn["arguments"]) });
        }
      }

      const rawFinish = firstChoice?.["finish_reason"];
      const finishReason: StylistCompletionResult["finishReason"] =
        rawFinish === "tool_calls" || toolCalls.length > 0
          ? "tool_calls"
          : rawFinish === "length"
          ? "length"
          : rawFinish === "content_filter"
          ? "content_filter"
          : "stop";

      const usage = asRecord(root?.["usage"]);
      const inputTokens = typeof usage?.["prompt_tokens"] === "number" ? usage["prompt_tokens"] : 0;
      const outputTokens = typeof usage?.["completion_tokens"] === "number"
        ? usage["completion_tokens"]
        : 0;

      return {
        message: typeof message["content"] === "string" ? message["content"] : "",
        toolCalls,
        finishReason,
        usage: { inputTokens, outputTokens },
        modelIdentifier: typeof root?.["model"] === "string" ? root["model"] : model,
      };
    } catch (err) {
      if (err instanceof ProviderError) {
        throw err;
      }
      if (err instanceof DOMException && err.name === "AbortError") {
        throw new ProviderError("TIMEOUT", true, "Stylist provider timed out.");
      }
      throw new ProviderError(
        "UNKNOWN",
        true,
        err instanceof Error ? err.message : "Stylist provider failed.",
      );
    } finally {
      clearTimeout(timer);
    }
  }

  // deno-lint-ignore require-yield
  async *completeStream(
    _request: StylistCompletionRequest,
    _ctx: ProviderRequestContext,
  ): AsyncIterable<{ delta: string; toolCallDelta?: unknown }> {
    // See the header: no client can consume a stream yet, and the protocol
    // requires throwing over silently degrading to a non-stream.
    throw new ProviderError(
      "INVALID_INPUT",
      false,
      "LiveStylistProvider does not implement streaming yet; use complete().",
    );
  }
}
