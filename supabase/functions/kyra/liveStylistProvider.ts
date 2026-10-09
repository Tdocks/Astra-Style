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
// the Responses envelope — stays inside this file. The interface's
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
  // Ephemeral, request/owner/model-scoped encrypted reasoning replay. Never
  // persisted in messages or logs. Hard bounds and TTL prevent isolate growth.
  private readonly replay = new Map<
    string,
    { expires: number; calls: Map<string, Record<string, unknown>[]> }
  >();

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

    const replayKey = JSON.stringify([ctx.userId, ctx.requestId, model]);
    for (const [key, entry] of this.replay) {
      if (entry.expires <= Date.now()) this.replay.delete(key);
    }
    const cache = this.replay.get(replayKey);
    const input: Array<Record<string, unknown>> = [
      { role: "system", content: request.systemPrompt },
      {
        role: "system",
        content: "CONTEXT PACKET (retrieved, budgeted; trust it over memory):\n" +
          JSON.stringify(request.contextPacket),
      },
    ];
    for (const message of request.messages) {
      if (message.role === "tool") {
        input.push({
          type: "function_call_output",
          call_id: message.toolCallId ?? "",
          output: message.content,
        });
      } else if (message.role === "assistant" && (message.toolCalls?.length ?? 0) > 0) {
        if (message.content) input.push({ role: "assistant", content: message.content });
        for (const call of message.toolCalls ?? []) {
          const saved = cache?.calls.get(call.id);
          input.push(
            ...(saved ??
              [{
                type: "function_call",
                call_id: call.id,
                name: call.name,
                arguments: JSON.stringify(call.arguments),
              }]),
          );
        }
      } else {
        input.push({ role: message.role, content: message.content });
      }
    }
    const body: Record<string, unknown> = {
      model,
      input,
      store: false,
      include: ["reasoning.encrypted_content"],
      reasoning: { effort: request.tier === "luna" ? "low" : "medium" },
      max_output_tokens: request.maxOutputTokens,
      text: {
        format: {
          type: "json_schema",
          name: "kyra_response",
          strict: false,
          schema: request.responseSchema,
        },
      },
      tools: request.tools.map((tool) => ({
        type: "function",
        name: tool.name,
        description: tool.description,
        parameters: tool.parametersSchema,
        strict: false,
      })),
    };

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), ctx.timeoutMs);
    try {
      const response = await this.fetchImpl("https://api.openai.com/v1/responses", {
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
        // Retain only bounded machine identifiers, never provider messages
        // which may echo private request content.
        const failure = asRecord(asRecord(await response.json().catch(() => null))?.["error"]);
        const safeIdentifier = (value: unknown): string | null =>
          typeof value === "string" && /^[a-zA-Z0-9_.\[\]-]{1,100}$/.test(value) ? value : null;
        throw new ProviderError(
          "PROVIDER_UNAVAILABLE",
          response.status >= 500,
          `Stylist provider returned ${response.status}.`,
          response.status,
          false,
          {
            code: safeIdentifier(failure?.["code"]),
            parameter: safeIdentifier(failure?.["param"]),
          },
        );
      }

      const json: unknown = await response.json();
      const root = asRecord(json);
      const output = root?.["output"];
      if (!Array.isArray(output)) {
        throw new ProviderError("INVALID_INPUT", false, "Stylist provider returned no output.");
      }
      const toolCalls: Array<{ id: string; name: string; arguments: Record<string, unknown> }> = [];
      const texts: string[] = [];
      let refused = false;
      const reasoningItems: Record<string, unknown>[] = [];
      const calls = new Map(cache?.calls ?? []);
      for (const raw of output) {
        const item = asRecord(raw);
        if (!item) continue;
        if (item.type === "reasoning") reasoningItems.push(item);
        if (
          item.type === "function_call" && typeof item.call_id === "string" &&
          typeof item.name === "string"
        ) {
          toolCalls.push({
            id: item.call_id,
            name: item.name,
            arguments: parseToolArguments(item.arguments),
          });
          calls.set(item.call_id, [...reasoningItems.splice(0), item]);
        }
        if (item.type === "message" && Array.isArray(item.content)) {
          for (const rawPart of item.content) {
            const part = asRecord(rawPart);
            if (part?.type === "output_text" && typeof part.text === "string") {
              texts.push(part.text);
            }
            if (part?.type === "refusal") refused = true;
          }
        }
      }
      if (toolCalls.length) {
        if (calls.size > 64 || JSON.stringify([...calls]).length > 512_000) {
          throw new ProviderError(
            "INVALID_INPUT",
            false,
            "Stylist tool history exceeded its limit.",
          );
        }
        if (!this.replay.has(replayKey) && this.replay.size >= 128) {
          const oldest = this.replay.keys().next().value;
          if (oldest !== undefined) this.replay.delete(oldest);
        }
        this.replay.set(replayKey, { expires: Date.now() + 300_000, calls });
      }
      const incomplete = asRecord(root?.incomplete_details);
      const finishReason: StylistCompletionResult["finishReason"] =
        incomplete?.reason === "max_output_tokens"
          ? "length"
          : refused || incomplete?.reason === "content_filter"
          ? "content_filter"
          : toolCalls.length
          ? "tool_calls"
          : "stop";
      const usage = asRecord(root?.usage);
      return {
        message: texts.join(""),
        toolCalls,
        finishReason,
        usage: {
          inputTokens: typeof usage?.input_tokens === "number" ? usage.input_tokens : 0,
          outputTokens: typeof usage?.output_tokens === "number" ? usage.output_tokens : 0,
        },
        modelIdentifier: typeof root?.model === "string" ? root.model : model,
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
