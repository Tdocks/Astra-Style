// ============================================================================
// kyra/handler.ts
// ============================================================================
// `POST /kyra/respond` (P5-KYRA-02) — the orchestration loop: build the
// context packet, call the `StylistReasoningProvider` with the eleven-tool
// surface, execute tool calls, feed results back, validate the structured
// response, enforce guardrails, persist the turn, return a `kyra_messages`
// row the iOS client decodes as `KyraMessage`. Deployment wiring lives in
// `index.ts`; everything here takes injected dependencies (`HandlerDeps`)
// and makes no network call of its own, so `handler_test.ts` exercises the
// full path with a fake provider and a fake store.
//
// Spec §14's six requirements, in the order they run:
//   1. Validate JWT            -> authenticateRequest(); the only id source.
//   2. Rate limit              -> TWO limiters, deliberately different
//      shapes. (a) The shared in-memory burst limiter every function uses.
//      (b) The P5-KYRA-19 free-tier limit: three Kyra CONVERSATIONS per day
//      (spec §16). That is a per-day, per-tier, cross-isolate business rule
//      — bending `_shared/rateLimit.ts`'s per-isolate minute-window Map into
//      it would produce a limit that resets on every cold start, i.e. a lie.
//      Instead the daily gate counts `kyra_threads` rows created today in
//      Postgres: durable, tamper-proof from the client, and enforced even
//      if the app is bypassed. Premium users skip the gate entirely.
//   3. Validate request schema -> parseEnvelope() / parseKyraRespondBody().
//   4. Validate ownership      -> RLS via the caller-scoped client behind
//      `KyraStore`; a thread id the caller does not own simply is not found.
//      The body has no user-id-shaped field to substitute (schema.ts).
//   5. Log request ID+latency  -> every path, success or failure.
//   6. Avoid logging prompts   -> only counts/ids/booleans/tiers are logged;
//      never message text, packet contents, or model output.
//
// ESCALATION (docs/09 §2), implemented triggers:
//   §2.1 confidence < threshold (default 0.55)  -> one full retry on Terra;
//        Terra's result is used outright if it parses, else Luna's stands.
//   §2.2 schema-validation failure -> repair on the SAME tier once, then a
//        Terra repair, then the docs/06 §6 safe fallback.
//   §2.3 tool loop > 4 iterations on Luna -> abort, retry on Terra with the
//        tool-call history preserved, cap 6, then safe fallback.
// Not implemented (recorded, not hidden): §2.4 (needs analytics events that
// do not exist server-side yet), §2.5's constraint-dimension counting, §2.6
// (product verdicts are a Phase 6 tool), and the Sol tier (no implemented
// trigger can reach a second hop). The per-request ladder is Luna -> Terra,
// at most one hop, which respects §3.5's cap by construction.
//
// EVERY FAILURE PAST AUTH/RATE-LIMIT/SCHEMA RETURNS A WELL-FORMED KYRA
// RESPONSE (docs/06 §6): the chat UI must never render a raw error where a
// stylist should be speaking. Provider outage, double repair failure, tool
// loop exhaustion — each produces an in-voice fallback message with
// confidence 0 and the turn is persisted like any other.
// ============================================================================

import { CORS_HEADERS, handleCorsPreflight } from "../_shared/cors.ts";
import {
  AppError,
  badRequest,
  errorResponse,
  jsonResponse,
  methodNotAllowed,
  notFound,
  serverError,
} from "../_shared/errors.ts";
import { createLogger, type RequestLogger } from "../_shared/logger.ts";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { requireIso8601Seconds } from "../_shared/time.ts";
import type {
  StylistCompletionResult,
  StylistMessage,
  StylistReasoningProvider,
} from "../_shared/providers/stylistReasoning.ts";
import { ProviderError } from "../_shared/providers/types.ts";
import type { ModelTier } from "../_shared/providers/types.ts";
import type { ClosetItemMapperRow } from "../_shared/scoring/closetItemMapper.ts";
import { KYRA_SYSTEM_PROMPT, KYRA_SYSTEM_PROMPT_VERSION } from "./prompt.ts";
import {
  type BodyProfileSourceRow,
  buildContextPacket,
  type FeedbackSourceRow,
  type LifestyleProfileSourceRow,
  type MemorySourceRow,
  type OccasionSourceRow,
  type PacketClosetItemRow,
  type StyleProfileSourceRow,
} from "./contextPacket.ts";
import {
  KyraContractError,
  type KyraRespondRequestBody,
  kyraResponseSchema,
  type KyraStructuredResponse,
  MEMORY_TYPES,
  type MemoryProposalWire,
  type MemoryType,
  parseEnvelope,
  parseKyraRespondBody,
  parseKyraStructuredResponse,
} from "./schema.ts";
import { applyGuardrails } from "./guardrails.ts";
import { buildToolRegistry, type ToolExecution, type ToolRegistry } from "./tools/registry.ts";
import type { SearchClosetRow } from "./tools/searchCloset.ts";
import type { NewOutfitRecord } from "./tools/createOutfit.ts";
import type { ExistingMemoryRow } from "./tools/savePreference.ts";

// ---------------------------------------------------------------------------
// Store interface — one seam, implemented over Supabase in store.ts
// ---------------------------------------------------------------------------

export interface InsertedMessage {
  readonly id: string;
  readonly createdAt: string;
}

export interface HistoryMessageRow {
  readonly role: string;
  readonly content: string | null;
  readonly structured_payload: Record<string, unknown> | null;
}

export interface KyraStore {
  // Threads + messages
  createThread(userId: string, title: string): Promise<string>;
  threadExists(threadId: string): Promise<boolean>;
  /** Threads this user created at/after `sinceIso` — the daily-gate counter. */
  countThreadsCreatedSince(userId: string, sinceIso: string): Promise<number>;
  insertUserMessage(userId: string, threadId: string, content: string): Promise<InsertedMessage>;
  insertAssistantMessage(
    userId: string,
    threadId: string,
    content: string,
    structuredPayload: KyraStructuredResponse,
    modelMetadata: Record<string, unknown>,
  ): Promise<InsertedMessage>;
  listRecentMessages(threadId: string, limit: number): Promise<HistoryMessageRow[]>;

  // Subscription tier (P5-KYRA-19)
  hasActivePremiumSubscription(nowIso: string): Promise<boolean>;

  // Context-packet sources
  loadStyleProfile(): Promise<StyleProfileSourceRow | null>;
  loadBodyProfile(): Promise<BodyProfileSourceRow | null>;
  loadLifestyleProfile(): Promise<LifestyleProfileSourceRow | null>;
  listUpcomingOccasions(fromIso: string, toIso: string): Promise<OccasionSourceRow[]>;
  listPacketClosetItems(): Promise<PacketClosetItemRow[]>;
  listRecentFeedback(limit: number): Promise<FeedbackSourceRow[]>;
  listVisibleMemories(minConfidence: number): Promise<MemorySourceRow[]>;

  // Tool backends
  listClosetItems(): Promise<SearchClosetRow[]>;
  listItemsByIds(ids: readonly string[]): Promise<ClosetItemMapperRow[]>;
  listOutfitItemIds(outfitIds: readonly string[]): Promise<ReadonlyMap<string, string[]>>;
  getOccasionTitle(occasionId: string): Promise<string | null>;
  insertOutfit(userId: string, record: NewOutfitRecord): Promise<string>;
  listOwnedItemIds(ids: readonly string[]): Promise<string[]>;
  getOutfitItemIds(outfitId: string): Promise<string[] | null>;
  insertWornOutfit(userId: string, itemIds: readonly string[], wornDate: string): Promise<string>;
  findWearOnDate(outfitId: string, wornDate: string): Promise<{ id: string } | null>;
  insertWear(
    userId: string,
    record: { outfitId: string; wornAtIso: string; occasion: string | null },
  ): Promise<string>;
  readWearCounts(itemIds: readonly string[]): Promise<ReadonlyMap<string, number>>;
  listMemoriesByType(memoryType: MemoryType): Promise<ExistingMemoryRow[]>;
  insertMemory(
    userId: string,
    record: {
      memoryType: MemoryType;
      content: string;
      confidence: number;
      sourceMessageId: string;
    },
  ): Promise<string>;
  updateMemoryConfidence(memoryId: string, confidence: number): Promise<void>;
  deleteMemory(memoryId: string): Promise<void>;
}

export interface KyraConfig {
  /** Spec §16: free tier = 3 Kyra conversations/day. Env-configurable (P5-KYRA-19). */
  readonly freeDailyConversationLimit: number;
  /** docs/09 §2.1's launch default 0.55. Env-configurable, not hardcoded. */
  readonly confidenceEscalationThreshold: number;
  /** docs/06 §5.2's explicit-statement bar, 0.7. */
  readonly memoryMinimumConfidence: number;
}

export interface HandlerDeps {
  readonly authClient: AuthClient;
  readonly store: KyraStore;
  readonly provider: StylistReasoningProvider;
  /** The shared per-isolate burst limiter (see the header on the two shapes). */
  readonly rateLimiter: RateLimiter;
  readonly config: KyraConfig;
  readonly now: () => Date;
  /** Injected so the tool-retry backoff is instantaneous in tests. */
  readonly sleep: (ms: number) => Promise<void>;
}

// Loop caps per docs/09 §2.3.
const LUNA_TOOL_ITERATION_CAP = 4;
const TERRA_TOOL_ITERATION_CAP = 6;
// Conversational register: some warmth, not a fresh personality per retry.
const KYRA_TEMPERATURE = 0.6;
const MAX_OUTPUT_TOKENS = 1_200;
// docs/08 §1.4 convention: generous single-call ceiling; the burst limiter
// and loop caps bound total turn time.
const PROVIDER_TIMEOUT_MS = 30_000;
const HISTORY_LIMIT = 12;
const FEEDBACK_FETCH_LIMIT = 8;
const OCCASION_FETCH_WINDOW_DAYS = 60;
const TOOL_RETRY_BACKOFF_MS = 250;

// The wire shape of the assistant `kyra_messages` row — decodes into Swift's
// `KyraMessage` (id/thread_id/role/content/structured_payload/model_metadata/
// created_at, ISO-8601 whole-second timestamp; see `_shared/time.ts`).
export interface KyraMessageDTO {
  readonly id: string;
  readonly thread_id: string;
  readonly role: "assistant";
  readonly content: string;
  readonly structured_payload: KyraStructuredResponse;
  readonly model_metadata: Record<string, unknown>;
  readonly created_at: string;
}

async function readJsonBody(req: Request): Promise<unknown> {
  const text = await req.text();
  if (text.trim().length === 0) {
    throw badRequest("Request body must not be empty.");
  }
  try {
    return JSON.parse(text);
  } catch {
    throw badRequest("Request body must be valid JSON.");
  }
}

// ---------------------------------------------------------------------------
// Turn orchestration
// ---------------------------------------------------------------------------

/** docs/09 §2.3: the Luna loop hit its cap; Terra retries with this history. */
class ToolLoopExceededError extends Error {
  constructor(
    readonly messages: StylistMessage[],
    readonly trace: ToolExecution[],
  ) {
    super("Tool-call loop exceeded its iteration cap.");
    this.name = "ToolLoopExceededError";
  }
}

interface TurnAttempt {
  readonly result: StylistCompletionResult;
  readonly messages: StylistMessage[];
}

interface TurnContext {
  readonly deps: HandlerDeps;
  readonly registry: ToolRegistry;
  readonly packet: Record<string, unknown>;
  readonly requestId: string;
  readonly userId: string;
  readonly logger: RequestLogger;
  /** Accumulates across ALL attempts: a write during an abandoned Luna
   * attempt still happened, and memory proposals must reflect it. */
  readonly globalTrace: ToolExecution[];
}

async function executeToolWithRetry(
  ctx: TurnContext,
  name: string,
  args: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  // docs/06 §6: one automatic retry with backoff for transient failures.
  // Domain outcomes come back as structured results and never throw
  // (tools/registry.ts); a THROW here is infrastructure.
  try {
    return await ctx.registry.execute(name, args);
  } catch (firstError) {
    ctx.logger.warn("kyra_respond.tool_error", {
      tool: name,
      error_name: firstError instanceof Error ? firstError.name : "unknown",
      will_retry: true,
    });
    await ctx.deps.sleep(TOOL_RETRY_BACKOFF_MS);
    try {
      return await ctx.registry.execute(name, args);
    } catch (secondError) {
      ctx.logger.error("kyra_respond.tool_failed", {
        tool: name,
        error_name: secondError instanceof Error ? secondError.name : "unknown",
      });
      // The model is told plainly; docs/06 §6 requires it to degrade
      // specifically rather than guess silently.
      return {
        error: "TOOL_EXECUTION_FAILED",
        tool: name,
        detail:
          "This tool failed twice and its answer is unavailable for this turn. Proceed with " +
          "what you have, lower your confidence, and say specifically what you couldn't check " +
          "if it materially affects the answer.",
      };
    }
  }
}

async function runToolLoop(
  ctx: TurnContext,
  tier: ModelTier,
  iterationCap: number,
  seedMessages: readonly StylistMessage[],
): Promise<TurnAttempt> {
  const messages: StylistMessage[] = [...seedMessages];
  const localTrace: ToolExecution[] = [];

  for (let iteration = 0; iteration < iterationCap; iteration++) {
    const result = await ctx.deps.provider.complete({
      systemPrompt: KYRA_SYSTEM_PROMPT,
      contextPacket: ctx.packet,
      messages,
      tools: ctx.registry.definitions,
      responseSchema: kyraResponseSchema(),
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      temperature: KYRA_TEMPERATURE,
      stream: false,
      tier,
    }, {
      requestId: ctx.requestId,
      userId: ctx.userId,
      timeoutMs: PROVIDER_TIMEOUT_MS,
    });

    if (result.finishReason !== "tool_calls" || result.toolCalls.length === 0) {
      return { result, messages };
    }

    messages.push({
      role: "assistant",
      content: result.message,
      toolCalls: result.toolCalls.map((call) => ({ ...call })),
    });
    for (const call of result.toolCalls) {
      const outcome = await executeToolWithRetry(ctx, call.name, call.arguments);
      const execution: ToolExecution = { name: call.name, args: call.arguments, result: outcome };
      localTrace.push(execution);
      ctx.globalTrace.push(execution);
      messages.push({
        role: "tool",
        content: JSON.stringify(outcome),
        toolCallId: call.id,
      });
    }
  }

  throw new ToolLoopExceededError(messages, localTrace);
}

/**
 * docs/06 §6's repair retry: re-prompt with the validation error and the
 * original output, asking for a corrected document. Runs on `tier` —
 * docs/09 §2.2 puts the FIRST repair on the same tier and the second on
 * Terra; the caller sequences that.
 */
async function repairAttempt(
  ctx: TurnContext,
  tier: ModelTier,
  priorMessages: readonly StylistMessage[],
  malformedOutput: string,
  validationDetail: string,
): Promise<StylistCompletionResult> {
  const messages: StylistMessage[] = [
    ...priorMessages,
    { role: "assistant", content: malformedOutput },
    {
      role: "user",
      content: "Your previous reply failed schema validation: " + validationDetail +
        " Return ONLY a corrected JSON document matching the response schema. Fix only the " +
        "malformed portion; do not change your styling judgment.",
    },
  ];
  return await ctx.deps.provider.complete({
    systemPrompt: KYRA_SYSTEM_PROMPT,
    contextPacket: ctx.packet,
    messages,
    // No tools on a repair pass: the work is reformatting, and a tool call
    // in response to a formatting instruction would itself be a defect.
    tools: [],
    responseSchema: kyraResponseSchema(),
    maxOutputTokens: MAX_OUTPUT_TOKENS,
    temperature: KYRA_TEMPERATURE,
    stream: false,
    tier,
  }, {
    requestId: ctx.requestId,
    userId: ctx.userId,
    timeoutMs: PROVIDER_TIMEOUT_MS,
  });
}

interface OrchestrationOutcome {
  readonly response: KyraStructuredResponse;
  readonly tierUsed: ModelTier;
  readonly escalated: boolean;
  /** Why the fallback fired, when it did. Null on a normal turn. */
  readonly fallbackReason: string | null;
  readonly modelIdentifier: string | null;
  readonly usage: { inputTokens: number; outputTokens: number };
}

/** docs/06 §6's safe fallback — a normal, well-formed response, confidence 0. */
function safeFallbackResponse(message: string): KyraStructuredResponse {
  return {
    message,
    intent: "general",
    cards: [],
    suggested_actions: [],
    memory_proposals: [],
    confidence: 0,
  };
}

const FALLBACK_MALFORMED = "I lost my train of thought there — could you ask that again?";
const FALLBACK_PROVIDER_DOWN =
  "I couldn't reach my styling tools just now. Give me a moment and ask again.";
const FALLBACK_LOOP_EXHAUSTED =
  "That one tangled me up more than it should have. Ask me again — a little more specifically " +
  "if you can — and I'll take another run at it.";

/**
 * Parses an attempt's final output; on contract failure runs the §2.2 repair
 * ladder (same-tier repair, then Terra repair). Returns null when both
 * repairs fail — the caller falls back.
 */
async function parseWithRepairs(
  ctx: TurnContext,
  attempt: TurnAttempt,
  tier: ModelTier,
): Promise<{ response: KyraStructuredResponse; result: StylistCompletionResult } | null> {
  try {
    const parsed = parseKyraStructuredResponse(attempt.result.message);
    if (parsed.droppedEntries > 0) {
      ctx.logger.warn("kyra_respond.entries_dropped", { count: parsed.droppedEntries, tier });
    }
    return { response: parsed.response, result: attempt.result };
  } catch (err) {
    if (!(err instanceof KyraContractError)) throw err;
    ctx.logger.warn("kyra_malformed_response", {
      tier,
      prompt_version: KYRA_SYSTEM_PROMPT_VERSION,
      model_identifier: attempt.result.modelIdentifier,
      detail: err.message,
    });

    const repairTiers: ModelTier[] = tier === "terra" ? ["terra"] : [tier, "terra"];
    let lastOutput = attempt.result.message;
    let lastDetail = err.message;
    for (const repairTier of repairTiers) {
      try {
        const repaired = await repairAttempt(
          ctx,
          repairTier,
          attempt.messages,
          lastOutput,
          lastDetail,
        );
        try {
          const parsed = parseKyraStructuredResponse(repaired.message);
          return { response: parsed.response, result: repaired };
        } catch (repairErr) {
          if (!(repairErr instanceof KyraContractError)) throw repairErr;
          lastOutput = repaired.message;
          lastDetail = repairErr.message;
        }
      } catch (providerErr) {
        if (!(providerErr instanceof ProviderError)) throw providerErr;
        ctx.logger.error("kyra_respond.repair_provider_error", {
          tier: repairTier,
          code: providerErr.code,
        });
      }
    }
    return null;
  }
}

async function orchestrateTurn(
  ctx: TurnContext,
  baseMessages: readonly StylistMessage[],
): Promise<OrchestrationOutcome> {
  const usage = { inputTokens: 0, outputTokens: 0 };
  const addUsage = (result: StylistCompletionResult) => {
    usage.inputTokens += result.usage.inputTokens;
    usage.outputTokens += result.usage.outputTokens;
  };

  let attempt: TurnAttempt;
  let tierUsed: ModelTier = "luna";
  let escalated = false;
  try {
    try {
      attempt = await runToolLoop(ctx, "luna", LUNA_TOOL_ITERATION_CAP, baseMessages);
      addUsage(attempt.result);
    } catch (err) {
      if (!(err instanceof ToolLoopExceededError)) throw err;
      // §2.3: abort, retry on Terra with the tool-call history preserved.
      ctx.logger.warn("kyra_respond.escalated", { trigger: "tool_loop", from: "luna" });
      escalated = true;
      tierUsed = "terra";
      try {
        attempt = await runToolLoop(ctx, "terra", TERRA_TOOL_ITERATION_CAP, err.messages);
        addUsage(attempt.result);
      } catch (terraErr) {
        if (!(terraErr instanceof ToolLoopExceededError)) throw terraErr;
        ctx.logger.error("kyra_respond.tool_loop_exhausted", {});
        return {
          response: safeFallbackResponse(FALLBACK_LOOP_EXHAUSTED),
          tierUsed: "terra",
          escalated: true,
          fallbackReason: "tool_loop_exhausted",
          modelIdentifier: null,
          usage,
        };
      }
    }

    let parsed = await parseWithRepairs(ctx, attempt, tierUsed);
    if (parsed === null) {
      return {
        response: safeFallbackResponse(FALLBACK_MALFORMED),
        tierUsed,
        escalated,
        fallbackReason: "malformed_response",
        modelIdentifier: attempt.result.modelIdentifier,
        usage,
      };
    }

    // §2.1: low self-reported confidence -> one full Terra retry; use the
    // Terra result outright when it parses, never a field-by-field blend.
    if (
      tierUsed === "luna" &&
      parsed.response.confidence < ctx.deps.config.confidenceEscalationThreshold
    ) {
      ctx.logger.warn("kyra_respond.escalated", {
        trigger: "low_confidence",
        confidence: parsed.response.confidence,
        from: "luna",
      });
      escalated = true;
      try {
        const terraAttempt = await runToolLoop(
          ctx,
          "terra",
          TERRA_TOOL_ITERATION_CAP,
          baseMessages,
        );
        addUsage(terraAttempt.result);
        const terraParsed = await parseWithRepairs(ctx, terraAttempt, "terra");
        if (terraParsed !== null) {
          parsed = terraParsed;
          tierUsed = "terra";
        }
        // A failed Terra retry leaves the valid-but-hedged Luna answer
        // standing: it was correct, just uncertain — better than a fallback.
      } catch (terraErr) {
        if (
          !(terraErr instanceof ToolLoopExceededError) && !(terraErr instanceof ProviderError)
        ) {
          throw terraErr;
        }
        ctx.logger.warn("kyra_respond.terra_retry_failed", {
          error_name: terraErr.name,
        });
      }
    }

    return {
      response: parsed.response,
      tierUsed,
      escalated,
      fallbackReason: null,
      modelIdentifier: parsed.result.modelIdentifier,
      usage,
    };
  } catch (err) {
    if (err instanceof ProviderError) {
      // docs/06 §6: never a raw error where a stylist should be speaking.
      ctx.logger.error("kyra_respond.provider_error", {
        code: err.code,
        retryable: err.retryable,
        provider_status: err.providerRawStatus ?? null,
      });
      return {
        response: safeFallbackResponse(FALLBACK_PROVIDER_DOWN),
        tierUsed,
        escalated,
        fallbackReason: "provider_error",
        modelIdentifier: null,
        usage,
      };
    }
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Post-turn assembly: honest memory proposals + guardrails
// ---------------------------------------------------------------------------

/**
 * `memory_proposals` is rebuilt from the tool trace — what `save_preference`
 * ACTUALLY did — never from the model's own claims. A model-claimed proposal
 * with no matching write would show the user a note that does not exist in
 * their inspectable memory list; a write without a proposal would be the
 * silent storage docs/06 §4.4 forbids. Deriving from the trace makes both
 * impossible at once.
 */
function memoryProposalsFromTrace(trace: readonly ToolExecution[]): MemoryProposalWire[] {
  const proposals: MemoryProposalWire[] = [];
  for (const execution of trace) {
    if (execution.name !== "save_preference") continue;
    const result = execution.result;
    const action = result["action_taken"];
    if (
      action !== "created" && action !== "updated_existing" && action !== "superseded_conflict"
    ) {
      continue;
    }
    const memoryId = result["memory_id"];
    const content = result["content"];
    const confidence = result["confidence"];
    const rawType = execution.args["memory_type"];
    if (typeof memoryId !== "string" || typeof content !== "string") continue;
    const memoryType = typeof rawType === "string" &&
        MEMORY_TYPES.includes(rawType as MemoryType)
      ? rawType as MemoryType
      : "general";
    const proposal: {
      memory_type: MemoryType;
      content: string;
      confidence: number;
      memory_id: string;
      action_taken: "created" | "updated_existing" | "superseded_conflict";
      supersedes_memory_id?: string | null;
    } = {
      memory_type: memoryType,
      content,
      confidence: typeof confidence === "number" ? confidence : 0.7,
      memory_id: memoryId,
      action_taken: action,
    };
    const supersedes = result["supersedes_memory_id"];
    if (typeof supersedes === "string") proposal.supersedes_memory_id = supersedes;
    proposals.push(proposal);
  }
  return proposals;
}

/** Ids that verifiably exist this turn — the hallucination guard's ground truth. */
function collectKnownIds(
  packetClosetIds: ReadonlySet<string>,
  trace: readonly ToolExecution[],
): { closetItemIds: Set<string>; outfitIds: Set<string>; productCandidateIds: Set<string> } {
  const closetItemIds = new Set(packetClosetIds);
  const outfitIds = new Set<string>();
  const productCandidateIds = new Set<string>();
  for (const execution of trace) {
    const result = execution.result;
    if (result["error"] !== undefined && result["error"] !== "DUPLICATE_ENTRY_SAME_DAY") continue;
    const items = result["items"];
    if (Array.isArray(items)) {
      for (const item of items) {
        if (typeof item === "object" && item !== null && !Array.isArray(item)) {
          const id = (item as Record<string, unknown>)["id"];
          if (typeof id === "string") closetItemIds.add(id);
        }
      }
    }
    const outfitId = result["outfit_id"];
    if (typeof outfitId === "string") outfitIds.add(outfitId);
    const ranked = result["ranked"];
    if (Array.isArray(ranked)) {
      for (const entry of ranked) {
        if (typeof entry === "object" && entry !== null && !Array.isArray(entry)) {
          const ref = (entry as Record<string, unknown>)["outfit_ref"];
          // Saved-outfit candidates rank under their real id; ad-hoc
          // combinations rank under a synthetic ref that is not a UUID and
          // deliberately never becomes card-able.
          if (typeof ref === "string" && /^[0-9a-f-]{36}$/i.test(ref)) outfitIds.add(ref);
        }
      }
    }
    const products = result["products"];
    if (Array.isArray(products)) {
      for (const product of products) {
        if (typeof product === "object" && product !== null && !Array.isArray(product)) {
          const id = (product as Record<string, unknown>)["product_candidate_id"];
          if (typeof id === "string") productCandidateIds.add(id);
        }
      }
    }
  }
  return { closetItemIds, outfitIds, productCandidateIds };
}

// ---------------------------------------------------------------------------
// The endpoint
// ---------------------------------------------------------------------------

function historyToStylistMessages(rows: readonly HistoryMessageRow[]): StylistMessage[] {
  const messages: StylistMessage[] = [];
  for (const row of rows) {
    if (row.role === "user") {
      if (row.content !== null && row.content.length > 0) {
        messages.push({ role: "user", content: row.content });
      }
    } else if (row.role === "assistant") {
      // Prefer the structured payload's message: that is what the user saw.
      const payloadMessage = row.structured_payload?.["message"];
      const content = typeof payloadMessage === "string" && payloadMessage.length > 0
        ? payloadMessage
        : row.content ?? "";
      if (content.length > 0) {
        messages.push({ role: "assistant", content });
      }
    }
    // system/tool rows are per-turn artifacts, not conversation history.
  }
  return messages;
}

/**
 * Context sources degrade independently (docs/06 §6): a failed profile read
 * makes that section absent — and logged — rather than failing the turn.
 */
async function fetchOrNull<T>(
  logger: RequestLogger,
  source: string,
  fetcher: () => Promise<T>,
  empty: T,
): Promise<T> {
  try {
    return await fetcher();
  } catch {
    logger.warn("kyra_respond.context_source_failed", { source });
    return empty;
  }
}

function startOfUtcDayIso(now: Date): string {
  return `${now.toISOString().slice(0, 10)}T00:00:00Z`;
}

function threadTitleFrom(text: string): string {
  const collapsed = text.replace(/\s+/g, " ").trim();
  return collapsed.length <= 60 ? collapsed : `${collapsed.slice(0, 57)}...`;
}

export async function handleKyraRespond(req: Request, deps: HandlerDeps): Promise<Response> {
  const startedAtMs = deps.now().getTime();

  const preflight = handleCorsPreflight(req);
  if (preflight) {
    return preflight;
  }

  let requestId = resolveRequestId(req);
  const logger = createLogger(requestId);

  try {
    if (req.method !== "POST") {
      throw methodNotAllowed("POST /kyra/respond only accepts POST.");
    }

    // 1. Validate JWT — the ONLY source of `userId`.
    const userId = await authenticateRequest(req, deps.authClient);

    // 2a. Burst rate limit (per-isolate, best-effort — _shared/rateLimit.ts).
    const burst = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!burst.allowed) {
      logger.warn("kyra_respond.rate_limited", {
        user_id: userId,
        kind: "burst",
        retry_after_seconds: burst.retryAfterSeconds,
      });
      return errorResponse(
        new AppError("rate_limited", 429, "Too many requests. Please try again shortly."),
        requestId,
        { ...CORS_HEADERS, "Retry-After": String(burst.retryAfterSeconds) },
      );
    }

    // 3. Validate request schema.
    const rawJson = await readJsonBody(req);
    const envelope = parseEnvelope(rawJson);
    requestId = resolveRequestId(req, envelope.requestId);
    logger.adoptRequestId(requestId);
    const body: KyraRespondRequestBody = parseKyraRespondBody(envelope.body);

    const now = deps.now();

    // 2b. P5-KYRA-19: the per-day, per-tier conversation gate. A
    // "conversation" is a thread; only STARTING one consumes the allowance
    // (continuing an allowed thread is part of the same conversation).
    // Counted durably in Postgres — see the file header for why the shared
    // in-memory limiter is the wrong shape and would quietly lie here.
    const isNewConversation = body.threadId === undefined;
    if (isNewConversation) {
      const premium = await deps.store.hasActivePremiumSubscription(now.toISOString());
      if (!premium) {
        const startedToday = await deps.store.countThreadsCreatedSince(
          userId,
          startOfUtcDayIso(now),
        );
        if (startedToday >= deps.config.freeDailyConversationLimit) {
          logger.warn("kyra_respond.rate_limited", {
            user_id: userId,
            kind: "daily_conversation_limit",
            limit: deps.config.freeDailyConversationLimit,
          });
          return errorResponse(
            new AppError(
              "rate_limited",
              429,
              `You've used your ${deps.config.freeDailyConversationLimit} Kyra conversations ` +
                "for today. Upgrade to Astra Style Premium for unlimited conversations with " +
                "Kyra.",
            ),
            requestId,
            CORS_HEADERS,
          );
        }
      }
    }

    // 4. Resolve the thread. RLS makes someone else's thread indistinguishable
    // from a nonexistent one — both are "not found".
    let threadId: string;
    if (body.threadId !== undefined) {
      const exists = await deps.store.threadExists(body.threadId);
      if (!exists) {
        throw notFound("No such conversation.");
      }
      threadId = body.threadId;
    } else {
      threadId = await deps.store.createThread(userId, threadTitleFrom(body.text));
    }

    // History is read BEFORE the new user message is inserted, so the turn's
    // own text appears exactly once in the provider messages.
    const historyRows = await fetchOrNull(
      logger,
      "history",
      () => deps.store.listRecentMessages(threadId, HISTORY_LIMIT),
      [] as HistoryMessageRow[],
    );
    const userMessage = await deps.store.insertUserMessage(userId, threadId, body.text);

    // Context packet sources — each independently degradable.
    const occasionWindowEnd = new Date(
      now.getTime() + OCCASION_FETCH_WINDOW_DAYS * 86_400_000,
    );
    const [
      styleProfile,
      bodyProfile,
      lifestyleProfile,
      occasions,
      closetItems,
      feedback,
      memories,
    ] = await Promise.all([
      fetchOrNull(logger, "style_profile", () => deps.store.loadStyleProfile(), null),
      fetchOrNull(logger, "body_profile", () => deps.store.loadBodyProfile(), null),
      fetchOrNull(logger, "lifestyle_profile", () => deps.store.loadLifestyleProfile(), null),
      fetchOrNull(
        logger,
        "occasions",
        () => deps.store.listUpcomingOccasions(now.toISOString(), occasionWindowEnd.toISOString()),
        [] as OccasionSourceRow[],
      ),
      fetchOrNull(
        logger,
        "closet_items",
        () => deps.store.listPacketClosetItems(),
        [] as PacketClosetItemRow[],
      ),
      fetchOrNull(
        logger,
        "recent_feedback",
        () => deps.store.listRecentFeedback(FEEDBACK_FETCH_LIMIT),
        [] as FeedbackSourceRow[],
      ),
      fetchOrNull(
        logger,
        "durable_memories",
        () => deps.store.listVisibleMemories(deps.config.memoryMinimumConfidence),
        [] as MemorySourceRow[],
      ),
    ]);

    const packetResult = buildContextPacket({
      now,
      requestText: body.text,
      attachments: body.attachments,
      styleProfile,
      bodyProfile,
      lifestyleProfile,
      weather: body.weatherSnapshot,
      occasions,
      closetItems,
      recentFeedback: feedback,
      memories,
    });
    if (packetResult.overflowed) {
      logger.warn("context_packet_overflow", { user_id: userId });
    }

    // Tool registry, bound to this request's caller and this turn's message.
    const registry = buildToolRegistry({
      searchCloset: { listClosetItems: () => deps.store.listClosetItems() },
      rankOutfits: {
        listItemsByIds: (ids) => deps.store.listItemsByIds(ids),
        listOutfitItemIds: (ids) => deps.store.listOutfitItemIds(ids),
        getOccasionTitle: (id) => deps.store.getOccasionTitle(id),
      },
      createOutfit: {
        listItemsByIds: (ids) => deps.store.listItemsByIds(ids),
        insertOutfit: (record) => deps.store.insertOutfit(userId, record),
      },
      getWeather: { weatherSnapshot: body.weatherSnapshot, now: deps.now },
      getSchedule: {
        listOccasions: (fromIso, toIso) => deps.store.listUpcomingOccasions(fromIso, toIso),
        now: deps.now,
      },
      savePreference: {
        sourceMessageId: userMessage.id,
        minimumConfidence: deps.config.memoryMinimumConfidence,
        listMemoriesByType: (memoryType) => deps.store.listMemoriesByType(memoryType),
        insertMemory: (record) => deps.store.insertMemory(userId, record),
        updateMemoryConfidence: (id, confidence) =>
          deps.store.updateMemoryConfidence(id, confidence),
        deleteMemory: (id) => deps.store.deleteMemory(id),
      },
      markItemWorn: {
        triggeringUserText: body.text,
        now: deps.now,
        listOwnedItemIds: (ids) => deps.store.listOwnedItemIds(ids),
        getOutfitItemIds: (id) => deps.store.getOutfitItemIds(id),
        insertWornOutfit: (ids, date) => deps.store.insertWornOutfit(userId, ids, date),
        findWearOnDate: (outfitId, date) => deps.store.findWearOnDate(outfitId, date),
        insertWear: (record) => deps.store.insertWear(userId, record),
        readWearCounts: (ids) => deps.store.readWearCounts(ids),
      },
    });

    const ctx: TurnContext = {
      deps,
      registry,
      packet: packetResult.packet,
      requestId,
      userId,
      logger,
      globalTrace: [],
    };

    const baseMessages: StylistMessage[] = [
      ...historyToStylistMessages(historyRows),
      { role: "user", content: body.text },
    ];

    const outcome = await orchestrateTurn(ctx, baseMessages);

    // Honest memory proposals + guardrail enforcement.
    const withProposals: KyraStructuredResponse = {
      ...outcome.response,
      memory_proposals: memoryProposalsFromTrace(ctx.globalTrace),
    };
    const knownIds = collectKnownIds(packetResult.closetItemIds, ctx.globalTrace);
    const guarded = applyGuardrails({
      response: withProposals,
      toolTrace: ctx.globalTrace,
      knownClosetItemIds: knownIds.closetItemIds,
      knownOutfitIds: knownIds.outfitIds,
      knownProductCandidateIds: knownIds.productCandidateIds,
    });
    if (guarded.violations.length > 0) {
      logger.warn("kyra_respond.guardrail_violations", {
        violations: guarded.violations.join(","),
      });
    }
    const finalResponse = guarded.response;

    const modelMetadata: Record<string, unknown> = {
      model_identifier: outcome.modelIdentifier,
      tier: outcome.tierUsed,
      escalated: outcome.escalated,
      prompt_version: KYRA_SYSTEM_PROMPT_VERSION,
      input_tokens: outcome.usage.inputTokens,
      output_tokens: outcome.usage.outputTokens,
      confidence: finalResponse.confidence,
      fallback_reason: outcome.fallbackReason,
      guardrail_violations: guarded.violations,
      truncation_applied: packetResult.truncationApplied,
    };

    const assistantMessage = await deps.store.insertAssistantMessage(
      userId,
      threadId,
      finalResponse.message,
      finalResponse,
      modelMetadata,
    );

    const payload: KyraMessageDTO = {
      id: assistantMessage.id,
      thread_id: threadId,
      role: "assistant",
      content: finalResponse.message,
      structured_payload: finalResponse,
      model_metadata: modelMetadata,
      created_at: requireIso8601Seconds(assistantMessage.createdAt, deps.now()),
    };

    const latencyMs = deps.now().getTime() - startedAtMs;
    // 5 & 6. Request id + latency; counts and categories only, never content.
    logger.info("kyra_respond.success", {
      user_id: userId,
      thread_id: threadId,
      new_conversation: isNewConversation,
      intent: finalResponse.intent,
      tier: outcome.tierUsed,
      escalated: outcome.escalated,
      fallback_reason: outcome.fallbackReason,
      tool_calls: ctx.globalTrace.length,
      cards: finalResponse.cards.length,
      memory_proposals: finalResponse.memory_proposals.length,
      guardrail_violation_count: guarded.violations.length,
      confidence: finalResponse.confidence,
      packet_truncations: packetResult.truncationApplied.length,
      had_weather_snapshot: body.weatherSnapshot !== null,
      prompt_version: KYRA_SYSTEM_PROMPT_VERSION,
      latency_ms: latencyMs,
    });

    return jsonResponse(payload, { status: 200, requestId, extraHeaders: CORS_HEADERS });
  } catch (err) {
    const latencyMs = deps.now().getTime() - startedAtMs;
    const appError = err instanceof AppError ? err : serverError();
    if (err instanceof AppError) {
      logger.warn("kyra_respond.rejected", {
        category: appError.category,
        status: appError.status,
        message: appError.message,
        latency_ms: latencyMs,
      });
    } else {
      logger.error("kyra_respond.unexpected_error", {
        latency_ms: latencyMs,
        error_name: err instanceof Error ? err.name : "unknown",
      });
    }
    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}
