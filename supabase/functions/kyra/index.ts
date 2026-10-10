// ============================================================================
// kyra/index.ts
// ============================================================================
// Deployment entrypoint for the `kyra` Edge Function — the grouped function
// (ADR 0013) serving spec §14's `POST /kyra/respond`. One deployed function,
// slug `kyra`, dispatching the path remainder via `_shared/routing.ts` like
// every other grouped function; the route table has one row today and the
// router exists so the next Kyra endpoint is a one-line addition, not a
// second parser.
//
// This file is intentionally thin wiring: env is read once at cold start
// (a misconfigured deploy fails loudly at the first request, not
// confusingly later), and all request logic lives in `handler.ts`, which
// `handler_test.ts` exercises offline with fakes. This file is verified by
// `deno check`, `_shared/routing_test.ts`, and a live `supabase functions
// serve` round trip.
//
// PROVIDER WIRING. `STYLIST_PROVIDER_API_KEY` is the preferred capability
// key. Since this adapter calls OpenAI, it can reuse the already-configured
// `IMAGE_PROVIDER_API_KEY` only while `IMAGE_GENERATION_PROVIDER=openai`.
// This keeps an existing production install working without reading or
// copying a secret; a dedicated stylist key still takes precedence. The
// fallback is logged so operators can see that stylist and image usage share
// one OpenAI credential/project. If neither key is available, the handler
// returns its in-voice unavailable response rather than simulating a live
// conversation.
//
// SERVICE-ROLE: used only for private preview confirmation records. Wardrobe,
// messages and reference consent reads retain caller JWT/RLS authorization.
// ============================================================================

import {
  createServiceRoleClient,
  createUserScopedClient,
  readEdgeEnv,
} from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { ProviderError } from "../_shared/providers/types.ts";
import type {
  StylistCompletionRequest,
  StylistReasoningProvider,
} from "../_shared/providers/stylistReasoning.ts";
import type { ProviderRequestContext } from "../_shared/providers/types.ts";
import { handleKyraRespond, type KyraConfig } from "./handler.ts";
import { buildProductServices } from "./productServices.ts";
import { buildStudioConfirmationStore } from "./studioConfirmations.ts";
import { buildStudioPreviewServices } from "./studioServices.ts";
import {
  buildStudioInspirationReads,
  buildStudioReferenceReads,
  listConsentedStudioReferenceIDs,
  resolveCompletedStudioInspiration,
} from "./studioReferences.ts";
import { CURRENT_STUDIO_CONSENT_TERMS_VERSION } from "../studio/schema.ts";
import { buildKyraStore } from "./store.ts";
import { LiveStylistProvider } from "./liveStylistProvider.ts";
import { resolveLocalStylistProviderEndpoint } from "./localProviderEndpoint.ts";
import { finishGeneration, readGenerationPremium, reserveGeneration } from "../outfits/quota.ts";

const env = readEdgeEnv();
const localStylistEndpoint = resolveLocalStylistProviderEndpoint(
  Deno.env.get("SUPABASE_URL"),
  Deno.env.get("ASTRA_LOCAL_STYLIST_PROVIDER_URL"),
);

// Burst limiter, per isolate, shared across routes — the same best-effort
// shape every deployed function uses. The BUSINESS limit (3 free
// conversations/day, P5-KYRA-19) is NOT here: it is counted durably in
// Postgres inside handler.ts, because an in-memory counter that resets on
// every cold start cannot honestly enforce a per-day entitlement.
const rateLimiter = createRateLimiter({ limit: 10, windowMs: 60_000 });

function positiveIntFromEnv(name: string, fallback: number): number {
  const raw = Deno.env.get(name);
  if (raw === undefined) return fallback;
  const parsed = Number(raw);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function fractionFromEnv(name: string, fallback: number): number {
  const raw = Deno.env.get(name);
  if (raw === undefined) return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed > 0 && parsed <= 1 ? parsed : fallback;
}

// P5-KYRA-19: configurable values, not hardcoded constants (the roadmap's
// unknown-LLM-cost risk note; docs/09 §2.1's "must be a config value").
const config: KyraConfig = {
  freeDailyConversationLimit: positiveIntFromEnv("KYRA_FREE_DAILY_CONVERSATION_LIMIT", 3),
  confidenceEscalationThreshold: fractionFromEnv("KYRA_CONFIDENCE_ESCALATION_THRESHOLD", 0.55),
  memoryMinimumConfidence: fractionFromEnv("KYRA_MEMORY_MINIMUM_CONFIDENCE", 0.7),
};

/**
 * Wired when no provider key is configured: every call fails with a typed,
 * retryable-false provider error the handler converts into the docs/06 §6
 * fallback response. Announces itself as unconfigured in the message.
 */
const unconfiguredProvider: StylistReasoningProvider = {
  complete(_request: StylistCompletionRequest, _ctx: ProviderRequestContext) {
    return Promise.reject(
      new ProviderError(
        "PROVIDER_UNAVAILABLE",
        false,
        "No OpenAI key is configured for the stylist provider. Set " +
          "STYLIST_PROVIDER_API_KEY, or configure IMAGE_GENERATION_PROVIDER=openai " +
          "with IMAGE_PROVIDER_API_KEY.",
        undefined,
        true,
      ),
    );
  },
  // deno-lint-ignore require-yield
  async *completeStream(_request: StylistCompletionRequest, _ctx: ProviderRequestContext) {
    throw new ProviderError(
      "PROVIDER_UNAVAILABLE",
      false,
      "No OpenAI key is configured for the stylist provider.",
      undefined,
      true,
    );
  },
};

function buildProvider(): StylistReasoningProvider {
  const dedicatedApiKey = Deno.env.get("STYLIST_PROVIDER_API_KEY")?.trim();
  const imageProvider = Deno.env.get("IMAGE_GENERATION_PROVIDER")?.trim().toLowerCase();
  const sharedOpenAIApiKey = imageProvider === "openai"
    ? Deno.env.get("IMAGE_PROVIDER_API_KEY")?.trim()
    : undefined;
  const apiKey = dedicatedApiKey || sharedOpenAIApiKey ||
    (localStylistEndpoint ? "local-qa-provider-stub" : undefined);
  if (!apiKey) {
    console.error(
      JSON.stringify({
        level: "error",
        event: "kyra.provider_not_configured",
        detail: "STYLIST_PROVIDER_API_KEY missing; /kyra/respond will return in-voice " +
          "fallback responses until it is set.",
      }),
    );
    return unconfiguredProvider;
  }
  if (!dedicatedApiKey && sharedOpenAIApiKey) {
    console.info(
      JSON.stringify({
        level: "info",
        event: "kyra.provider_key_reused",
        detail: "Using IMAGE_PROVIDER_API_KEY for the OpenAI stylist adapter; " +
          "stylist and image calls share provider billing and limits.",
      }),
    );
  }
  return new LiveStylistProvider({
    apiKey,
    ...(localStylistEndpoint ? { endpointURL: localStylistEndpoint } : {}),
    modelForTier: {
      luna: Deno.env.get("STYLIST_PROVIDER_MODEL_LUNA") ?? "gpt-5.6-luna",
      terra: Deno.env.get("STYLIST_PROVIDER_MODEL_TERRA") ?? "gpt-5.6-terra",
      // No implemented escalation trigger reaches Sol (docs/09 §3.5 caps the
      // ladder; handler.ts implements one hop). Mapped so a future trigger
      // cannot dereference undefined, to Terra rather than an unverified
      // model id this project has never called.
      sol: Deno.env.get("STYLIST_PROVIDER_MODEL_TERRA") ?? "gpt-5.6-terra",
    },
  });
}

const provider = buildProvider();

function kyraRespondRoute(req: Request): Promise<Response> {
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  const supabase = createUserScopedClient(env, authorizationHeader);
  const quotaClient = createServiceRoleClient(env);

  return handleKyraRespond(req, {
    authClient: supabase,
    store: buildKyraStore(supabase, quotaClient),
    outfitGenerationQuota: {
      isPremium: (userID, now) => readGenerationPremium(quotaClient, userID, now),
      reserve: (userID, requestID, fingerprint, now) =>
        reserveGeneration(quotaClient, userID, requestID, fingerprint, now),
      finish: (userID, reservationID, succeeded, result, now) =>
        finishGeneration(quotaClient, userID, reservationID, succeeded, result, now),
    },
    resolveStudioInspiration: async (userID, generationID) => {
      const reference = await resolveCompletedStudioInspiration(
        userID,
        generationID,
        buildStudioInspirationReads(supabase, userID),
        env.supabaseUrl,
        new Date(),
      );
      return reference?.imageURL ?? null;
    },
    analyzeProduct: buildProductServices(env, authorizationHeader, supabase),
    studio: {
      confirmations: buildStudioConfirmationStore(quotaClient),
      referenceIDs: (userID) =>
        listConsentedStudioReferenceIDs(
          userID,
          CURRENT_STUDIO_CONSENT_TERMS_VERSION,
          buildStudioReferenceReads(supabase, userID),
        ),
      preview: (turn) => {
        const proposal =
          /^(yes|yeah|yep|sure|go ahead|please do|do it)[.!\s]*$/i.test(turn.userText.trim())
            ? turn.proposal
            : null;
        return buildStudioPreviewServices(env, authorizationHeader, supabase, {
          ...turn,
          pending: proposal
            ? { selectionKey: proposal.selectionKey, askedAboutGenerationCost: true }
            : null,
          confirmedProposal: proposal,
        });
      },
    },
    provider,
    rateLimiter,
    config,
    now: () => new Date(),
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  });
}

Deno.serve(createRouter("kyra", [
  { method: "POST", pattern: "/respond", handler: kyraRespondRoute },
]));
