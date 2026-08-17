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
// PROVIDER WIRING. `STYLIST_PROVIDER_API_KEY` (spec §25's per-capability
// name — NOT `OPENAI_API_KEY`; see docs/08 §2.5's postmortem on that exact
// mistake) selects the live adapter. When it is absent, the wired provider
// throws `PROVIDER_UNAVAILABLE` on first use and the handler returns its
// docs/06 §6 in-voice fallback — Kyra says she can't reach her tools,
// honestly, instead of a deterministic fake pretending to converse. There
// is no mock stylist here on purpose: a scripted Kyra that looks finished
// is exactly the "looks done, is not" failure this repo's rules name.
//
// NOTE ON SERVICE-ROLE: never constructed here. RLS with the caller's own
// JWT covers every table this function touches — see store.ts's header.
// ============================================================================

import { createUserScopedClient, readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { ProviderError } from "../_shared/providers/types.ts";
import type {
  StylistCompletionRequest,
  StylistReasoningProvider,
} from "../_shared/providers/stylistReasoning.ts";
import type { ProviderRequestContext } from "../_shared/providers/types.ts";
import { handleKyraRespond, type KyraConfig } from "./handler.ts";
import { buildKyraStore } from "./store.ts";
import { LiveStylistProvider } from "./liveStylistProvider.ts";

const env = readEdgeEnv();

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
        "STYLIST_PROVIDER_API_KEY is not set; the live stylist provider is not configured " +
          "for this deployment.",
      ),
    );
  },
  // deno-lint-ignore require-yield
  async *completeStream(_request: StylistCompletionRequest, _ctx: ProviderRequestContext) {
    throw new ProviderError(
      "PROVIDER_UNAVAILABLE",
      false,
      "STYLIST_PROVIDER_API_KEY is not set.",
    );
  },
};

function buildProvider(): StylistReasoningProvider {
  const apiKey = Deno.env.get("STYLIST_PROVIDER_API_KEY");
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
  return new LiveStylistProvider({
    apiKey,
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

  return handleKyraRespond(req, {
    authClient: supabase,
    store: buildKyraStore(supabase),
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
