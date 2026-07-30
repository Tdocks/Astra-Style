// ============================================================================
// _shared/providers/stylistReasoning.ts
// ============================================================================
// `StylistReasoningProvider` — the first of spec §8's five provider
// protocols, specified in `docs/08-provider-abstraction.md` §1. This file is
// the interface ONLY. It contains no vendor SDK, no API key handling, and no
// HTTP: an implementation lives beside the function that wires it
// (`style-dna/deterministicStylist.ts` today), and a live adapter would live
// in `_shared/providers/` next to this file once one exists.
//
// WHY THE PROTOCOL IS SERVER-SIDE ONLY, AND HAS NO SWIFT COUNTERPART.
//
// The obvious symmetry — "there is a protocol on the server, so there should
// be one on the client" — is exactly what ADR 0004 forbids. Its decision 3 is
// explicit: "The iOS client never holds a provider API key and never
// constructs a request to a model vendor's endpoint. It calls Astra Edge
// Functions only." A Swift `StylistReasoningProvider` would be a client-side
// seam for something the client is structurally not allowed to do, and its
// existence would invite exactly the shortcut the ADR exists to prevent. The
// client's seam for this capability is `ProfileRepository.generateStyleDNA()`
// (`ios/AstraStyle/Domain/Repositories/ProfileRepository.swift`) — a
// repository protocol whose live implementation calls
// `POST /style-dna/generate` and whose mock returns a fixture. That is the
// Swift-side counterpart §8's "Dependency approach" asks for, and it already
// exists.
//
// WHAT A LIVE ADAPTER MUST NOT DO. It must not widen this interface to
// expose a vendor concept (a "system fingerprint", a vendor-specific
// finish reason, a raw response object). `docs/08` §1.5's portability
// argument only holds while every field below is Astra-shaped; the first
// vendor-shaped field added here silently converts the swap-a-vendor cost
// from "write an adapter" to "touch every call site".
// ============================================================================

import type { ModelTier, ProviderRequestContext } from "./types.ts";

/** One tool the model may call. JSON Schema per `docs/06-kyra-orchestration.md` §3. */
export interface StylistToolDefinition {
  readonly name: string;
  readonly description: string;
  readonly parametersSchema: Record<string, unknown>;
}

export interface StylistMessage {
  readonly role: "system" | "user" | "assistant" | "tool";
  readonly content: string;
  /** Present when `role === "tool"`. */
  readonly toolCallId?: string;
  readonly toolCalls?: ReadonlyArray<
    { id: string; name: string; arguments: Record<string, unknown> }
  >;
}

export interface StylistCompletionRequest {
  /** Versioned prompt — see `docs/06-kyra-orchestration.md` §2. */
  readonly systemPrompt: string;
  /** The retrieved, budgeted context — see `docs/06-kyra-orchestration.md` §1.6. */
  readonly contextPacket: Record<string, unknown>;
  /** Recent thread history, budgeted separately from `contextPacket`. */
  readonly messages: readonly StylistMessage[];
  readonly tools: readonly StylistToolDefinition[];
  /**
   * JSON Schema the output must satisfy, enforced via provider-native
   * structured output where supported and via the repair-retry path
   * (`docs/06` §6) where not. Passed even to implementations that ignore it,
   * because a caller that stopped sending it would silently disable
   * structured output the day a vendor swap made it load-bearing.
   */
  readonly responseSchema: Record<string, unknown>;
  readonly maxOutputTokens: number;
  /** Fixed per intent type, never user-configurable (`docs/08` §1). */
  readonly temperature: number;
  readonly stream: boolean;
  /**
   * Which tier `docs/09-model-routing.md` §1 assigns this call type. Part of
   * the REQUEST rather than of the provider instance so a single provider
   * can serve a Luna default and a Terra escalation of the same request
   * without a second adapter — `docs/08` §1.5: "one implementation
   * parameterized by tier, so the escalation router can move a single
   * request between tiers mid-flow."
   */
  readonly tier: ModelTier;
}

export interface StylistCompletionResult {
  /** The model's textual output. For a schema-constrained call, this is the JSON document. */
  readonly message: string;
  readonly toolCalls: ReadonlyArray<
    { id: string; name: string; arguments: Record<string, unknown> }
  >;
  readonly finishReason: "stop" | "tool_calls" | "length" | "content_filter";
  readonly usage: { readonly inputTokens: number; readonly outputTokens: number };
  /**
   * Exact model/version string, stored alongside anything the model
   * produced (`kyra_messages.model_metadata`, and echoed on the Style DNA
   * response) so a quality regression can be attributed to a version rather
   * than guessed at.
   */
  readonly modelIdentifier: string;
}

export interface StylistReasoningProvider {
  complete(
    request: StylistCompletionRequest,
    ctx: ProviderRequestContext,
  ): Promise<StylistCompletionResult>;

  /**
   * Streaming variant, required for the <2.5s first-token target (spec §20)
   * on Kyra's conversational turns.
   *
   * Deliberately NOT used by `POST /style-dna/generate`: Style DNA is a
   * single structured document rendered as one screen (§6.10), so there is
   * nothing to progressively render and streaming would only add a
   * reassembly step before validation. It is declared here because the
   * protocol is shared with `kyra/respond` (Phase 5), which does need it —
   * an implementation that cannot stream should throw
   * `ProviderError("INVALID_INPUT", false, ...)` rather than silently
   * falling back to a non-streaming call the caller believes is streaming.
   */
  completeStream(
    request: StylistCompletionRequest,
    ctx: ProviderRequestContext,
  ): AsyncIterable<{ delta: string; toolCallDelta?: unknown }>;
}
