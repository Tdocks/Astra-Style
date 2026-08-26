// ============================================================================
// style-dna/handler.ts
// ============================================================================
// `POST /style-dna/generate` (spec §14, ticket P2-CORE-02). Deployment wiring
// lives in `index.ts`; everything here takes injected dependencies and makes
// no network call of its own, so `handler_test.ts` exercises the whole
// request path — auth, rate limit, retrieval, provider call, validation,
// persistence — with no Supabase project and no provider key.
//
// Spec §14's six requirements, in the order they run:
//   1. Validate JWT           -> authenticateRequest(). The only id source.
//   2. Rate limit             -> keyed on that id, and tighter than the read
//      endpoints because a live provider call costs real money (index.ts).
//   3. Validate request schema-> parseEnvelope() / parseGenerateStyleDnaBody().
//   4. Validate ownership     -> `deps.profileRepository` is handed the
//      step-1 id and, in production, is backed by a caller-scoped client, so
//      Row Level Security decides which rows exist. The request body carries
//      nothing to substitute — it is empty by design (schema.ts).
//   5. Log request ID+latency -> on every path.
//   6. Avoid logging prompt contents -> the context packet is NEVER logged,
//      in whole or in part, and neither is any generated prose. Only counts,
//      booleans, the resolved tier and the model identifier.
//
// WHERE THE PROVIDER SEAM IS. `deps.provider` is a `StylistReasoningProvider`
// (spec §8). This handler builds a complete, real `StylistCompletionRequest`
// — system prompt, context packet, response schema, tier — and hands it over.
// Swapping `DeterministicStylistProvider` for a live adapter is one line in
// `index.ts`; nothing in this file, in the DTO, or on the client changes.
// That is P2-CORE-02's second acceptance criterion and ADR 0004's decision 4,
// made structural rather than promised.
// ============================================================================

import { CORS_HEADERS, handleCorsPreflight } from "../_shared/cors.ts";
import {
  AppError,
  badRequest,
  errorResponse,
  jsonResponse,
  methodNotAllowed,
  serverError,
} from "../_shared/errors.ts";
import { createLogger } from "../_shared/logger.ts";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { toIso8601Seconds } from "../_shared/time.ts";
import type { StylistReasoningProvider } from "../_shared/providers/stylistReasoning.ts";
import { ProviderError } from "../_shared/providers/types.ts";
import { buildStyleDnaContext, type StyleDnaContext } from "./context.ts";
import {
  parseEnvelope,
  parseGenerateStyleDnaBody,
  parseStyleDnaDocument,
  StyleDnaContractError,
  type StyleDnaDocument,
  type StyleDnaDTO,
  styleDnaResponseSchema,
} from "./schema.ts";

/**
 * The ten values of the `style_identity` Postgres enum
 * (20260728100100_core_enums.sql) and of `StyleIdentity` in Swift. Passed to
 * the response validator so a provider naming an eleventh is rejected here
 * rather than at the UPDATE.
 */
export const STYLE_IDENTITIES = [
  "modern_heritage",
  "quiet_luxury",
  "smart_casual",
  "minimalist",
  "luxury_streetwear",
  "rugged_utility",
  "classic_americana",
  "european_summer",
  "executive",
  "creative",
] as const;

/**
 * The versioned system prompt (`docs/06-kyra-orchestration.md` §2's
 * convention: prompts are versioned, not edited in place, so a quality change
 * can be attributed to one).
 *
 * It is passed to every provider, including the deterministic one that
 * ignores it. Keeping the caller honest about constructing a real request is
 * the point — a call site that only built a prompt when a live provider was
 * wired would be a call site nobody had tested.
 *
 * The guardrails in it are duplicated, not delegated: `parseStyleDnaDocument`
 * enforces the structural ones server-side regardless of what the model was
 * told, because ADR 0004's whole argument for the Edge Function boundary is
 * that guardrails must not depend on a model's cooperation.
 */
export const STYLE_DNA_SYSTEM_PROMPT_VERSION = "style-dna/2026-07-30.1";

export const STYLE_DNA_SYSTEM_PROMPT = [
  "You are Kyra, a personal stylist for men. You are writing a man's Style DNA:",
  "the six sections shown on his result screen — primary identity, secondary",
  "influences, preferred palette, best silhouette direction, signature item",
  "opportunities, and initial wardrobe priorities.",
  "",
  "Rules you may not break:",
  "1. Every claim must trace to an input in the context packet. If an input is",
  "   missing, produce a shorter result and name the gap in open_questions.",
  "   Never fill a section with generic advice to make the result look complete.",
  "2. The garment is the subject of every sentence, never the reader's body.",
  "   Describe what a cut does. Never use the word 'flattering'.",
  "3. Never imply an exact fit or a size. Measurements inform direction, not",
  "   a guarantee.",
  "4. Never give advice about changing the reader's body.",
  "5. A preference measured from one or two comparisons is a starting point,",
  "   not something the reader told you. Say so when you use it.",
  "6. Reply with one JSON document matching the provided schema. No prose",
  "   outside it.",
].join("\n");

export interface ProfileRows {
  style: Record<string, unknown> | null;
  body: Record<string, unknown> | null;
  lifestyle: Record<string, unknown> | null;
  /** ADR 0019. Absent → menswear. */
  wardrobeGraph: "menswear_3_role" | "womenswear";
}

/** The §6.10 summary this endpoint owns and writes back to `style_profiles`. */
export interface GeneratedSummary {
  formality_preference: string;
  logo_tolerance: number;
  trend_tolerance: number;
  accessory_preference: string;
  preferred_colors: string[];
  avoided_colors: string[];
  style_summary: string;
}

export interface StyleProfileRepository {
  /** The caller's own three profile rows. Any may be null. */
  load(userId: string): Promise<ProfileRows>;
  /**
   * Persists the four §6.10 summary columns plus the palette and the written
   * summary. Returns the row's `updated_at` if the store reports one, so the
   * response can carry a real generation timestamp rather than the handler's
   * own clock.
   */
  saveGeneratedSummary(userId: string, summary: GeneratedSummary): Promise<string | null>;
}

export interface HandlerDeps {
  authClient: AuthClient;
  profileRepository: StyleProfileRepository;
  provider: StylistReasoningProvider;
  rateLimiter: RateLimiter;
  now: () => Date;
}

/**
 * `docs/09-model-routing.md` §1, row 6: Style DNA generation defaults to
 * Terra. Not Luna — this is the first real demonstration of Kyra's judgment a
 * new user sees (spec §30's definition of done), and it runs roughly once per
 * account, so the tier's higher per-call cost is immaterial to the cost model
 * while the quality difference is the most visible one in the product.
 */
const STYLE_DNA_TIER = "terra" as const;

/** `docs/08-provider-abstraction.md` §1.4: timeout = 1.5x the provider budget. */
const PROVIDER_TIMEOUT_MS = 20_000;
const MAX_OUTPUT_TOKENS = 2_000;

async function readJsonBody(req: Request): Promise<unknown> {
  const text = await req.text();
  if (text.trim().length === 0) {
    // A GET-shaped call to a POST endpoint, or a client that forgot the
    // envelope. Treated as an empty envelope rather than an error would hide
    // a real client bug behind a working response.
    throw badRequest("Request body must not be empty.");
  }
  try {
    return JSON.parse(text);
  } catch {
    throw badRequest("Request body must be valid JSON.");
  }
}

function summaryFrom(document: StyleDnaDocument): GeneratedSummary {
  return {
    formality_preference: document.formality_preference,
    logo_tolerance: document.logo_tolerance,
    trend_tolerance: document.trend_tolerance,
    accessory_preference: document.accessory_preference,
    preferred_colors: document.palette.preferred_colors,
    avoided_colors: document.palette.avoided_colors,
    style_summary: document.summary,
  };
}

/**
 * Counts, not content. Everything here is a number or a boolean, so the log
 * line describes how much the generator had to work with without recording a
 * single thing the user said — spec §14's "avoid logging private images or
 * full prompt contents", applied to a call whose entire input is personal.
 */
function contextShape(context: StyleDnaContext): Record<string, number | boolean> {
  const readings = Object.values(context.vector.dimensions);
  return {
    has_primary_identity: context.identity.primary !== null,
    secondary_identity_count: context.identity.secondaries.length,
    goal_count: context.goals.length,
    has_preferred_fit: context.preferredFit !== null,
    preference_axes_present: readings.length,
    preference_axes_scored: readings.filter((reading) => reading.score !== null).length,
    has_any_measurement: context.body.hasAnyMeasurement,
    has_frame_axes: context.body.taper !== null || context.body.proportion !== null ||
      context.body.scale !== null,
    has_dress_code: context.lifestyle.dressCode !== null,
    has_typical_week: context.lifestyle.typicalWeek !== null,
    occasion_count: context.lifestyle.commonOccasions.length,
  };
}

export async function handleGenerateStyleDna(req: Request, deps: HandlerDeps): Promise<Response> {
  const startedAtMs = deps.now().getTime();

  const preflight = handleCorsPreflight(req);
  if (preflight) {
    return preflight;
  }

  let requestId = resolveRequestId(req);
  const logger = createLogger(requestId);

  try {
    if (req.method !== "POST") {
      throw methodNotAllowed("POST /style-dna/generate only accepts POST.");
    }

    // 1. Validate JWT.
    const userId = await authenticateRequest(req, deps.authClient);

    // 2. Rate limit.
    const rateLimitResult = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!rateLimitResult.allowed) {
      logger.warn("style_dna_generate.rate_limited", {
        user_id: userId,
        retry_after_seconds: rateLimitResult.retryAfterSeconds,
      });
      return errorResponse(
        new AppError("rate_limited", 429, "Too many requests. Please try again shortly."),
        requestId,
        { ...CORS_HEADERS, "Retry-After": String(rateLimitResult.retryAfterSeconds) },
      );
    }

    // 3. Validate request schema.
    const rawJson = await readJsonBody(req);
    const envelope = parseEnvelope(rawJson);
    requestId = resolveRequestId(req, envelope.requestId);
    logger.adoptRequestId(requestId);
    parseGenerateStyleDnaBody(envelope.body);

    // 4. Ownership: rows for the JWT-derived id, under RLS. Nothing in the
    // request body could name a different user even if it tried.
    const rows = await deps.profileRepository.load(userId);
    const context = buildStyleDnaContext(
      rows.style,
      rows.body,
      rows.lifestyle,
      rows.wardrobeGraph,
    );

    const result = await deps.provider.complete({
      systemPrompt: STYLE_DNA_SYSTEM_PROMPT,
      contextPacket: context as unknown as Record<string, unknown>,
      messages: [],
      // Style DNA is a single structured generation. It reads the profile the
      // Edge Function already retrieved and has nothing to look up, so it
      // needs none of the eleven Kyra tools (docs/06 §3).
      tools: [],
      responseSchema: styleDnaResponseSchema(STYLE_IDENTITIES),
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      // Fixed per call type, never user-configurable (docs/08 §1). Low, not
      // zero: this is generative prose, but two runs against an unchanged
      // profile should not read as two different opinions.
      temperature: 0.4,
      stream: false,
      tier: STYLE_DNA_TIER,
    }, {
      requestId,
      userId,
      timeoutMs: PROVIDER_TIMEOUT_MS,
      // Style DNA generation is explicitly re-runnable from the §6.10 screen
      // ("Allow user to edit and regenerate"), so a repeat is a feature
      // rather than a double-charge to guard against. A live adapter that
      // bills per call should still key on something stable per REGENERATION
      // (this request id), which is what is passed.
      idempotencyKey: requestId,
    });

    // The provider's output is validated before it is stored or returned —
    // see schema.ts on why this exists even though today's provider cannot
    // produce a bad document.
    const document = parseStyleDnaDocument(result.message, STYLE_IDENTITIES);

    const updatedAt = await deps.profileRepository.saveGeneratedSummary(
      userId,
      summaryFrom(document),
    );

    const generatedAt = toIso8601Seconds(updatedAt) ?? toIso8601Seconds(deps.now()) ??
      deps.now().toISOString();

    const payload: StyleDnaDTO = {
      ...document,
      generated_at: generatedAt,
      model_identifier: result.modelIdentifier,
    };

    const latencyMs = deps.now().getTime() - startedAtMs;
    logger.info("style_dna_generate.success", {
      user_id: userId,
      ...contextShape(context),
      tier: STYLE_DNA_TIER,
      prompt_version: STYLE_DNA_SYSTEM_PROMPT_VERSION,
      model_identifier: result.modelIdentifier,
      input_tokens: result.usage.inputTokens,
      output_tokens: result.usage.outputTokens,
      signature_count: document.signature_opportunities.length,
      priority_count: document.wardrobe_priorities.length,
      open_question_count: document.open_questions.length,
      measured_dimension_count: document.measured_dimensions.length,
      latency_ms: latencyMs,
    });

    return jsonResponse(payload, { status: 200, requestId, extraHeaders: CORS_HEADERS });
  } catch (err) {
    const latencyMs = deps.now().getTime() - startedAtMs;
    const appError = toAppError(err);

    if (err instanceof AppError) {
      logger.warn("style_dna_generate.rejected", {
        category: appError.category,
        status: appError.status,
        message: appError.message,
        latency_ms: latencyMs,
      });
    } else if (err instanceof StyleDnaContractError) {
      // The validation detail is logged (it names a field, never a value) so
      // a provider that starts drifting is diagnosable, while the client sees
      // only a generic, retryable provider failure.
      logger.error("style_dna_generate.provider_contract_violation", {
        detail: err.message,
        latency_ms: latencyMs,
      });
    } else if (err instanceof ProviderError) {
      logger.error("style_dna_generate.provider_error", {
        code: err.code,
        retryable: err.retryable,
        provider_status: err.providerRawStatus ?? null,
        latency_ms: latencyMs,
      });
    } else {
      logger.error("style_dna_generate.unexpected_error", {
        latency_ms: latencyMs,
        error_name: err instanceof Error ? err.name : "unknown",
      });
    }

    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}

/**
 * Maps a thrown value onto the wire error envelope.
 *
 * A provider failure is category "provider" (which
 * `AstraServerErrorPayload.asAstraError` maps to `.provider`, and
 * `AstraError.isRetryable` treats as retryable) rather than "validation".
 * That distinction is user-visible: "validation" sends a man back to change
 * an answer that was fine, while "provider" produces a retry of a request
 * that was correct. Getting it backwards would be a worse bug than the
 * failure itself.
 */
function toAppError(err: unknown): AppError {
  if (err instanceof AppError) {
    return err;
  }
  if (err instanceof StyleDnaContractError) {
    return new AppError(
      "provider",
      502,
      "Kyra couldn't finish reading your profile just now. Try again in a moment.",
    );
  }
  if (err instanceof ProviderError) {
    return err.retryable
      ? new AppError(
        "provider",
        502,
        "Kyra couldn't finish reading your profile just now. Try again in a moment.",
      )
      : serverError("Couldn't generate your Style DNA.");
  }
  return serverError();
}
