# 08 — Provider Abstraction: Algorithmic Specification

**Status:** Implementation-ready. All five vendor decisions resolved 2026-07-28.
**Depends on:** `00-master-spec.md` §8 (technical architecture), §12 (CV pipeline), §13 (Style Studio pipeline), §16 (subscription model), §20 (performance targets), §25 (secrets), §29 (legal/privacy)
**Owner surface:** Supabase Edge Functions (Deno/TypeScript). The iOS client never talks to a model vendor directly — every provider call is proxied through an Edge Function per §8's "iOS client talks only to Astra Edge Functions" rule.

This document specifies the five provider protocols as TypeScript interfaces, the capability bar a vendor must clear to be pluggable behind each, failure/retry semantics, cost drivers, and the latency budget each interface must meet. Every provider section that previously ended in a `DECISION PENDING` block now ends in a **resolved decision** — vendor, rationale, rejected alternatives, cost arithmetic, and the specific conditions that should trigger revisiting it. **The interfaces above these decisions are unchanged and remain the actual contract Edge Functions code against** — per ADR 0004, these are default implementations plugged in behind provider-neutral protocols, not hardcoded dependencies. A vendor swap changes an Edge Function's dependency wiring, not the interface, the calling code, or this document's protocol definitions.

For the four StylistReasoningProvider-backed call types (StylistReasoningProvider itself, plus the Luna/Terra escalation logic that governs it), the day-to-day operational detail — routing policy per call type, escalation triggers, cost model, prompt-caching strategy, and quality measurement — lives in `09-model-routing.md`, not here. This document establishes *which* vendor and *why*; `09` establishes *how a given request picks a tier* and *how that choice is measured and tuned*.

---

## 0. Shared conventions

All five interfaces share a request envelope and error taxonomy so the Edge Functions that consume them (and their retry/circuit-breaker logic) can be written generically once, not per-provider.

```typescript
// core/providers/types.ts

/** Every provider call carries this envelope so logging, tracing, and retry
 *  logic are uniform across all five provider types. */
export interface ProviderRequestContext {
  requestId: string;          // propagated from the originating Edge Function request
  userId: string;
  timeoutMs: number;          // hard timeout for this call; see per-provider latency budgets
  idempotencyKey?: string;    // required for any call with a real-money or quota cost
}

export type ProviderErrorCode =
  | "TIMEOUT"
  | "RATE_LIMITED"
  | "AUTH_FAILED"
  | "INVALID_INPUT"
  | "CONTENT_MODERATION_REJECTED"
  | "PROVIDER_UNAVAILABLE"      // 5xx / outage
  | "PROVIDER_QUOTA_EXCEEDED"   // our own account limit, not the user's
  | "UNKNOWN";

export class ProviderError extends Error {
  constructor(
    public code: ProviderErrorCode,
    public retryable: boolean,
    message: string,
    public providerRawStatus?: number,
  ) {
    super(message);
  }
}
```

### 0.1 Retry semantics (shared baseline)

```
timeout = min(callerTimeoutMs, 1.5 × p95LatencyTargetForThisCall)
retries = 1 automatic retry on {TIMEOUT, PROVIDER_UNAVAILABLE, RATE_LIMITED}
backoff = jittered exponential: base 250ms, factor 2, max 2 retries total including the first attempt
non-retryable: {AUTH_FAILED, INVALID_INPUT, CONTENT_MODERATION_REJECTED} — fail fast, these won't
  succeed on retry and burning the retry budget on them just adds latency to a response the user
  is waiting on
circuit breaker: open after 5 consecutive failures within a 60s rolling window per provider;
  half-open probe after 30s (single test call); closes on success, reopens on failure
idempotency: any call that creates a billed job (image generation, provider calls with per-call
  cost) must pass idempotencyKey so a client-side or network-level retry does not double-charge
  or double-generate
```

### 0.2 Fallback ordering

Every provider protocol is implemented by at least a **mock/degraded implementation** behind the same interface (per §31's "use mock services only where an external provider key is unavailable, place each mock behind the same protocol" instruction), so local dev and CI never require live vendor keys. In production, if the circuit breaker is open for a *non-critical-path* provider, the system degrades gracefully per the failure modes in `06-kyra-orchestration.md` §6 rather than failing the whole request.

---

## 1. StylistReasoningProvider

The interface behind Kyra's conversational turns (`06-kyra-orchestration.md`). This is the highest-stakes provider: it must support structured tool calling and constrained/schema-validated output, not just free-text completion, because Kyra's entire response contract is the JSON schema in `06-kyra-orchestration.md` §4.

```typescript
// core/providers/StylistReasoningProvider.ts

export interface StylistToolDefinition {
  name: string;
  description: string;
  parametersSchema: Record<string, unknown>; // JSON Schema, see 06-kyra-orchestration.md §3
}

export interface StylistMessage {
  role: "system" | "user" | "assistant" | "tool";
  content: string;
  toolCallId?: string;   // present when role === "tool"
  toolCalls?: Array<{ id: string; name: string; arguments: Record<string, unknown> }>;
}

export interface StylistCompletionRequest {
  systemPrompt: string;             // versioned prompt, see 06-kyra-orchestration.md §2
  contextPacket: Record<string, unknown>; // see 06-kyra-orchestration.md §1.6
  messages: StylistMessage[];       // recent thread history, separately budgeted from contextPacket
  tools: StylistToolDefinition[];
  responseSchema: Record<string, unknown>; // 06-kyra-orchestration.md §4, enforced via
                                            // provider-native structured output if supported,
                                            // else via the repair-retry path (06 §6)
  maxOutputTokens: number;
  temperature: number;              // fixed per intent type, not user-configurable
  stream: boolean;
}

export interface StylistCompletionResult {
  message: string;
  toolCalls: Array<{ id: string; name: string; arguments: Record<string, unknown> }>;
  finishReason: "stop" | "tool_calls" | "length" | "content_filter";
  usage: { inputTokens: number; outputTokens: number };
  modelIdentifier: string; // exact model/version string, stored in kyra_messages.model_metadata
}

export interface StylistReasoningProvider {
  complete(
    request: StylistCompletionRequest,
    ctx: ProviderRequestContext,
  ): Promise<StylistCompletionResult>;

  /** Streaming variant — required for first-token latency; the Edge Function
   *  starts building the KyraResponse cards as tokens arrive rather than
   *  waiting for the full completion. */
  completeStream(
    request: StylistCompletionRequest,
    ctx: ProviderRequestContext,
  ): AsyncIterable<{ delta: string; toolCallDelta?: unknown }>;
}
```

### 1.1 Capability requirements

- Native tool/function calling with structured arguments (not "ask the model to emit JSON in prose and hope").
- Either native structured-output/JSON-schema-constrained generation, or reliable enough instruction-following that the repair-retry path (`06-kyra-orchestration.md` §6, malformed-JSON case) succeeds in practice — this is a hard evaluation gate before a candidate provider ships, not an assumption.
- Streaming token output (required for the <2.5s first-token/card target, §20).
- A context window sufficient for `contextPacket` (4,000 tokens, §1 of `06`) + system prompt (~1,200 tokens) + recent thread history (budgeted separately, target ≤ 3,000 tokens of trailing history) + tool schemas (~1,500 tokens for all 11) + response headroom — practical minimum ~16K tokens, comfortable at 32K+.
- Documented data retention / no-training-by-default policy compatible with §29's "no training on user images/data without explicit opt-in consent" requirement — this is a **hard legal gate**, not a nice-to-have, and disqualifies any candidate whose default terms retain or train on API content without an enterprise/opt-out agreement in place.

### 1.2 Failure and retry semantics

Uses the §0.1 baseline with one addition specific to this provider: on a `CONTENT_FILTER` finish reason (the model itself refused/filtered), do not retry — surface it through `06-kyra-orchestration.md`'s out-of-scope/guardrail failure path, since a content-filtered response is a signal the request needs guardrail handling, not a transient error to retry past.

### 1.3 Cost drivers and control

- **Input tokens dominate cost** here specifically because the context packet is rebuilt and resent every turn (no server-side conversation state on most providers' base APIs). The §1 token budget in `06-kyra-orchestration.md` is the primary cost lever — it was sized jointly for latency *and* cost.
- Tool schema tokens (~1,500 tokens, all 11 tools, every turn) are a fixed tax; if a provider supports cached/pinned system content (several do, at a cost discount for the cached portion), pin the system prompt + tool schemas as the cached prefix and only vary the context packet + messages per turn. GPT-5.6's cached-input pricing (90% off standard input, per §1.5's decision record) makes this the single most important cost lever for Kyra specifically — see `09-model-routing.md` §6 for the exact prefix/suffix structure that maximizes cache hits.
- Model tier selection is itself a cost lever: not every turn needs the largest available model. This is now a **resolved routing policy, not an open judgment call** — GPT-5.6 Luna is the default tier, with a defined escalation path to Terra (and a narrow Sol ceiling) per §1.5's decision record. The full intent-to-tier assignment, the precise escalation trigger conditions, and the server-configurable threshold table are specified in `09-model-routing.md` §1–2, §8 — a config table (call type + signals → model tier), not hardcoded, so it can be tuned against the eval metrics in `06-kyra-orchestration.md` §7.3 and the quality-measurement loop in `09` §7 without a redeploy.

### 1.4 Latency budget (derived from §20)

Target: **first token/card under 2.5s total.** Budget breakdown:

| Stage | Budget |
|---|---|
| Context packet assembly (retrieval + budgeting, `06` §1) | 400ms |
| Network round-trip to provider | 250ms |
| Provider time-to-first-token | 1,200ms |
| Client render of first card | 300ms |
| Margin | 350ms |

`timeoutMs` passed to `complete()`/`completeStream()` is set to 1.5× the provider TTFT budget (1,800ms) — if a provider can't produce a first token within that window, the call is treated as failed and the retry/fallback path in `06-kyra-orchestration.md` §6 engages rather than leaving the user staring at a spinner past the performance target.

### 1.5 DECISION — StylistReasoningProvider vendor

```
╔══════════════════════════════════════════════════════════════════╗
║ DECISION: OpenAI GPT-5.6, two-tier — Luna (default), Terra        ║
║ (escalation). Sol reserved as a narrow escalation ceiling.        ║
║ Resolved 2026-07-28. Owner: Tyler.                                ║
╚══════════════════════════════════════════════════════════════════╝
```

**What was chosen.** OpenAI GPT-5.6 backs `StylistReasoningProvider` in production. GPT-5.6 ships as three tiers on one API surface (Responses API), sharing the same tool-calling and structured-output contract:

| Tier | Input /1M | Output /1M | Cached input /1M | Used for |
|---|---|---|---|---|
| **Luna** | $1.00 | $6.00 | $0.10 | Default tier — the large majority of Kyra turns, Daily Briefs, garment classification, product extraction |
| **Terra** | $2.50 | $15.00 | $0.25 | Escalation tier — low-confidence/high-stakes/complex calls, per the router in `09-model-routing.md` |
| **Sol** | $5.00 | $30.00 | $0.50 | Escalation ceiling only — not used in normal operation (see below) |

This is not three separate vendor integrations; it's one `StylistReasoningProvider` implementation parameterized by tier, so the escalation router (`09-model-routing.md`) can move a single request between tiers mid-flow without a different adapter, different prompt format, or different tool-schema encoding.

**Why this clears the bar in §1.1 and the criteria in the original decision table:**

- **Tool-calling reliability.** All three tiers support native tool/function calling with structured arguments and native structured-output/JSON-schema-constrained generation — the hard requirement in §1.1 for avoiding the malformed-JSON repair path being a routine occurrence rather than a rare edge case. This must still be verified against the golden set and guardrail suite (`06` §7.1–7.2) before the first production prompt version ships, per this document's original evaluation gate — the tier choice does not substitute for that eval, it's a precondition for it being worth running.
- **Voice/instruction-following fidelity.** Not resolvable from a spec sheet — this is exactly what the guardrail regression suite (`06` §7.2) exists to check, and it remains a **hard gate** (100% pass rate) before any prompt version deploys, independent of vendor.
- **Data retention / training opt-out.** Per §29's "no training on user images/data without explicit opt-in consent," Astra's OpenAI API usage must run under API-tier terms (not a consumer product tier), which do not train on submitted content by default. This is a deployment/account-configuration requirement, not a code requirement — Edge Functions must call the API endpoint under Astra's business account with training opted out, and this is verified as part of provisioning, not assumed.
- **Context window and streaming.** All three tiers support streaming token output (needed for the <2.5s first-token/card target, §20) and support the Responses API's structured-output and tool-calling paths without a smaller-context fallback tier — no tier-specific capability cliff to design around.
- **Cost per turn.** See the arithmetic in `09-model-routing.md` §5 (Cost Model) — this is the section that models DAU × turns/day × tier mix, not restated here to avoid two sources of truth for the same number.
- **Latency consistency.** Not independently verified pre-launch; this is one of the "conditions to revisit" below, tracked against the p50/p95 metrics in `06` §7.3 once in production.
- **Multi-provider portability.** The interfaces in this document (`StylistCompletionRequest`/`Result`, `StylistToolDefinition`) are Astra-shaped, not OpenAI-shaped — the tool schema, message roles, and response contract are translated to/from OpenAI's Responses API format inside the adapter, not leaked into the protocol. A future swap to a different vendor changes the adapter, not the Edge Function call sites, per ADR 0004.

**Why two tiers by default, not one.** Not every Kyra call needs Sol-class reasoning, and paying Sol pricing for `mark_item_worn` confirmations or short follow-ups is pure cost with no quality benefit the user can perceive. Luna is priced and positioned for "cost-sensitive, fastest execution" — appropriate for the majority of Kyra's call volume, which is short, low-ambiguity, and grounded in retrieved context (the context packet already did the hard work of narrowing what's relevant; the model's job on most turns is applying stylist judgment to an already-curated set, not solving an open-ended reasoning problem). Terra is priced and positioned for "everyday work, strong general performance" — the right default for calls where getting it wrong is visibly worse to the user (a genuinely bad daily outfit recommendation, a wrong high-stakes product verdict) or where the request itself signals complexity (multi-constraint packing, multi-item outfit review). The full per-call-type assignment and the escalation triggers that move a request from Luna to Terra mid-request are specified in `09-model-routing.md` §1–2 — that table is the actual routing policy; this section only establishes that the two-tier split is the right shape.

**Why Sol is documented but not used in normal operation.** Sol is priced for "complex professional work, max capability" — a ceiling well above what a styling/wardrobe reasoning task structurally requires, since the domain (bounded closet, bounded taxonomy, bounded tool surface) doesn't present the kind of open-ended multi-domain complexity Sol is positioned for. Reserving Sol for *every* high-stakes call (e.g., every `buy` verdict) would be a blanket cost increase with no evidence it improves outcomes over Terra for this domain. Instead, Sol is reserved as a narrow **escalation ceiling** for a specific, rare pattern: a request that has *already* escalated to Terra and *still* fails validation (schema-invalid output, exceeded tool-call-loop iterations, or a second consecutive low-confidence self-report) — i.e., Terra genuinely struggled, not just "this happens to be an expensive item." This is a double-escalation case, expected to be a small fraction of a percent of total call volume; if production data shows Sol materially outperforms Terra on double-escalation cases, it stays. If it doesn't, drop it and let a Terra-repair-retry (same tier, one more attempt with the validation error appended) be the ceiling instead. See `09-model-routing.md` §2 for the exact trigger condition and §7 for how this gets measured rather than left as a permanent guess.

**Rejected alternatives:**

- **Single-tier Terra (or single-tier Sol) for everything.** Rejected on cost: per `09-model-routing.md`'s arithmetic, routing 100% of Kyra turns to Terra instead of the ~85/15 Luna/Terra split roughly doubles reasoning-provider cost per engaged subscriber with no corresponding quality signal that most turns need it — see `09` §5 for the sensitivity model. Single-tier Sol is materially worse on both dimensions.
- **A three-way *default* split (route different call types to Luna, Terra, and Sol as separate defaults) rather than two defaults plus one escalation ceiling.** Rejected because it multiplies the number of "why is this call type on this tier" decisions that need independent justification and independent monitoring, for a capability difference (Terra → Sol) that this domain has not been shown to need at default-routing scale. Two defaults plus a narrow, rare escalation ceiling is simpler to reason about, cheaper to monitor, and easy to widen later if evidence justifies it.
- **A different frontier vendor's tool-calling model as the primary, kept as an alternative to evaluate.** Out of scope for this document — the owner's vendor selection (GPT-5.6) is treated as resolved input, not relitigated here. The provider-neutral protocol in §1 above means this remains a real, exercisable option later without an architecture change; see "conditions to revisit" below.

**Cost model.** Full per-call-type breakdown, the 4,000-token context-packet arithmetic, the cached-vs-uncached comparison, and the monthly-subscriber roll-up are in `09-model-routing.md` §5 — restating them here would create two numbers that can silently drift out of sync as the routing policy is tuned. Headline: at the design-target ~85/15 Luna/Terra split for conversational turns and the assumed engaged-subscriber usage pattern, reasoning-provider cost lands at roughly 14–17% of net Premium revenue after Apple's platform cut — see `09` §5 for the full arithmetic and the escalation rate at which that stops being comfortable.

**Latency budget.** Unchanged from §1.4 above — the 1,200ms provider-TTFT allocation and 1,800ms `timeoutMs` apply per-call regardless of which tier serves a given request; Terra and Sol are not expected to blow that budget for a well-formed request (both are still fast, non-"thinking"-mode-by-default tiers at `medium` reasoning effort, GPT-5.6's default), but this is a launch assumption to validate against real p95s, not a guarantee — see "conditions to revisit."

**Conditions that should trigger revisiting this choice:**

- p95 time-to-first-token for Terra (or Sol, on the rare double-escalation path) measured in production exceeds the 1,800ms `timeoutMs` budget with enough frequency to be visible in `06` §7.3's latency metrics — this would mean the escalation tier itself is what's blowing the <2.5s target, not a general provider problem.
- The guardrail regression suite (`06` §7.2) fails to hold 100% on GPT-5.6 at any tier after a model version update on OpenAI's side — GPT-5.6 is not a static artifact; a silent model update behind a fixed API name is exactly the risk §4.5's "stability/versioning" criterion (written for EmbeddingProvider, but the same logic applies here) calls out. Pin a specific model snapshot where OpenAI's API supports it, re-run the guardrail suite on every OpenAI-side model refresh Astra opts into, and treat a refresh as a prompt-version-bump-worthy event even if Astra changed nothing.
- OpenAI's data retention/training terms change in a way that no longer satisfies §29 at Astra's account tier — a hard legal gate, not a quality judgment, and grounds for an immediate provider swap evaluation regardless of any other factor above.
- The measured Terra escalation rate for Kyra conversational turns (§7 of `09-model-routing.md`) sustains above ~40% for a full release cycle — at that point the "two-tier with Luna as the true default" cost model this decision rests on has stopped describing reality, and either the Luna prompt/context needs rework to bring quality up at the cheap tier, or the tier split itself needs to be reconsidered (e.g., Terra becomes the default and Luna becomes the exception for the very cheapest call types).
- A finding, from the offline eval harness (`09` §7), that Sol measurably and repeatedly outperforms Terra on the double-escalation case set — justifying widening Sol's role, or conversely, a finding that Sol shows no measurable improvement over a Terra repair-retry — justifying removing Sol as a distinct tier entirely and simplifying to Terra-only escalation.

---

## 2. VisionAnalysisProvider

The server-side leg of the CV pipeline (§12, detailed fully in §8 of this document). Takes an already-cropped, on-device-segmented garment image and returns fine-grained classification.

```typescript
// core/providers/VisionAnalysisProvider.ts

export interface GarmentAnalysisRequest {
  imageStoragePath: string;      // signed, private Supabase Storage path — never a public URL
  deviceHints?: {                // pre-computed on-device results, passed through as priors
    dominantColorsRgb: string[];
    detectedText: string[];      // OCR'd label text from the device pass
    approximateCategory?: string;
  };
}

export interface GarmentAnalysisResult {
  category: string;
  subcategory: string;
  confidence: number;
  colorLch: { l: number; c: number; h: number };
  secondaryColorsLch: Array<{ l: number; c: number; h: number }>;
  pattern: "solid" | "stripe" | "check" | "herringbone" | "print" | "texture-only";
  patternScale?: "micro" | "small" | "medium" | "large";
  material: string[];
  formalityAnchorLow: { label: string; score: number };  // see 05-wardrobe-graph.md §3
  formalityAnchorHigh: { label: string; score: number };
  formalityBlendFraction: number; // 0-1 between the two anchors
  formalityScore: number;         // resolved 0-100
  brandGuess: { name: string; confidence: number } | null;
  normalizedTitle: string;
  condition: "excellent" | "good" | "fair" | "worn" | "damaged";
  conditionConfidence: number;
  fieldsBelowConfidenceThreshold: string[]; // field names the client must visibly mark low-confidence, per §12
}

export interface VisionAnalysisProvider {
  analyzeGarment(
    request: GarmentAnalysisRequest,
    ctx: ProviderRequestContext,
  ): Promise<GarmentAnalysisResult>;

  /** Fallback background removal when the on-device pass is inadequate (§12). */
  removeBackground(
    imageStoragePath: string,
    ctx: ProviderRequestContext,
  ): Promise<{ resultStoragePath: string }>;
}
```

### 2.1 Capability requirements

- Fine-grained menswear taxonomy classification (not generic "clothing" object detection) — needs either a fashion-tuned model or a general vision-language model steerable via a detailed taxonomy prompt (the formality-anchor-blend output shape in §3 above is designed to work with the latter: ask for two nearest anchors + blend fraction rather than a free-form 0–100 number, which is both more consistent across calls and auditable).
- Structured/schema-constrained output, same requirement as §1.1 — this result is machine-consumed (feeds `05-wardrobe-graph.md`'s scoring), not displayed as prose.
- Acceptable accuracy on OCR-derived brand inference with calibrated confidence (a wrong high-confidence brand guess is worse than an honest low-confidence one, since it get surfaces to the user without a "verify" affordance below the confidence threshold, §12).

### 2.2 Failure and retry semantics

Standard §0.1 baseline. On exhausted retries: the Edge Function returns a **partial result** with whatever on-device hints are available promoted to top-level fields (category from `approximateCategory`, colors from `dominantColorsRgb`, converted to LCh) and every other field marked low-confidence/empty — the closet-scan flow (§6.3 of the master spec) is designed around "all inferred fields remain editable," so a degraded analysis is a worse first draft for the user to correct, not a hard failure of item creation.

### 2.3 Cost drivers and control

- Image resolution sent to the provider is the dominant cost/latency lever — send the on-device-cropped and compressed image (per §12's device-side pipeline), never the raw capture. Cap upload resolution at a fixed ceiling (e.g., 1024px longest edge) tuned against observed classification accuracy — going higher has rapidly diminishing accuracy return for a garment-classification task versus a fine-detail task.
- Batch scan (§6.16 batch closet scan mode) should use the provider's batch/async endpoint if available rather than N synchronous calls, both for cost and to avoid N× the rate-limit pressure.

### 2.4 Latency budget

Target: item analysis **under 8 seconds total** (§20), which includes the on-device leg (near-instant, already local, §8.1) and network transfer. Server VLM leg budget: **≤ 5.5s p50**, leaving margin for upload time and client-side result rendering within the 8s ceiling. Embedding generation (a separate call to `EmbeddingProvider`, §4) is explicitly **not** on this critical path — it's fired asynchronously after the classification result is already returned to the user for review, since the user needs the editable fields, not the embedding, to proceed.

### 2.5 DECISION — VisionAnalysisProvider vendor

```
╔══════════════════════════════════════════════════════════════════╗
║ DECISION: Apple Vision (on-device) + OpenAI GPT-5.6 Luna          ║
║ (server-side). Escalate to Terra only on low-confidence retry.    ║
║ Resolved 2026-07-28. Owner: Tyler.                                ║
╚══════════════════════════════════════════════════════════════════╝
```

**What was chosen.** This provider is already architecturally split across the device/server boundary (§7 below) — the vendor decision resolves the server-side leg only, since the on-device leg (§7.1's left column) is native Apple Vision/AVFoundation and was never a vendor question.

- **On-device (unchanged, Apple Vision framework):** blur/exposure rejection, garment-region detection, foreground segmentation where supported, care-label OCR (raw text extraction), dominant color extraction, resize/compress/strip-metadata. This is exactly §7.1's existing device-side column — nothing about the CV pipeline split changes as a result of this decision.
- **Server-side (`VisionAnalysisProvider.analyzeGarment`), GPT-5.6 Luna by default:** subtype/subcategory classification, material inference, pattern classification, condition estimation, normalized title generation — the fields in `GarmentAnalysisResult` that need semantic/holistic judgment rather than pixel-level signal processing, per §7.2's stated capability-ceiling rationale for why this leg is server-side at all.
- **Escalation to Terra:** only on a **low-confidence retry**, not as a default tier for any subset of scans. Expected at **5–10% of scans** (midpoint used for cost modeling: 7.5%, see `09-model-routing.md` §5). This is a genuine retry, not a routing decision made before the first call — the Luna call always runs first; a second Terra call only fires if the Luna result's `conditionConfidence` or per-field confidence lands below the threshold defined in `09-model-routing.md` §2, and the Terra result (not a blend) becomes the field values returned to the client.

**Why this clears the bar in §2.1 and the original criteria table:**

- **Fashion/apparel classification accuracy.** GPT-5.6 is a general-purpose multimodal model, not a fashion-tuned one — the design leans on the same mitigation §2.1 already specifies: steer it hard via the detailed taxonomy prompt and the formality-anchor-blend output shape (`05-wardrobe-graph.md` §3), which is deliberately designed to work with a general vision-language model rather than assuming a fashion-specific one. This is a **pilot-and-verify gate, not a settled fact** — before this ships, run GPT-5.6 Luna against a labeled sample of real (consented) user-scan photos and confirm subcategory-granularity accuracy (e.g., knit polo vs. piqué polo vs. performance polo) is acceptable. If it isn't, Terra becomes the *default* tier for classification, not just the low-confidence escalation, and the cost model in `09` §5 would need to be rerun at the higher tier. **This is the clearest judgment call in this section** — the research provided confirms GPT-5.6's general capabilities (vision input, structured output) but not menswear-specific subcategory accuracy, which no spec sheet reliably predicts per §2.5's own original criteria table. Evidence that would resolve it: the pilot accuracy numbers themselves, run before the closet-scan flow (§6.3) ships to real users.
- **Structured output reliability.** All three GPT-5.6 tiers support structured outputs (per the researched facts), satisfying §2.1's requirement that this is machine-consumed, not prose — same mechanism and same gate as §1.5.
- **Cost per image at onboarding-spike volume.** See `09-model-routing.md` §5 for the arithmetic; the headline is that Luna's per-image cost (image tokens + short structured output, no caching benefit on the image itself since each photo is unique) is low enough that an onboarding burst of 5–15 scans in one sitting is a few cents, not a meaningful spike cost.
- **Latency at the chosen resolution ceiling.** Unchanged from §2.3/§2.4 — the 1024px-longest-edge cap and the ≤5.5s p50 server-leg budget apply regardless of vendor; this needs end-to-end validation against real network conditions once the integration is live, per the existing latency budget section.
- **OCR quality for label text.** This is where the on-device/server split already does the right thing regardless of which VLM is server-side: raw OCR text extraction happens on-device (Apple Vision, a dedicated, fast, well-supported OCR path), and is passed to the server as a `deviceHints.detectedText` **prior**, not re-extracted by the VLM from the image. GPT-5.6 Luna's job on the OCR-derived signal is *brand inference reasoning* from already-extracted text (matching known brand name patterns, handling partial/garbled OCR gracefully) — not re-reading small angled label text from pixels, which sidesteps the "VLMs are weaker at small/angled text than dedicated OCR" concern from the original criteria table entirely, by construction of the existing pipeline split (§7.3).
- **Data retention / training opt-out.** Same account-level requirement and same hard gate as §1.5 — garment photos are personal data per §29, and Astra's OpenAI API usage runs under the same no-training-by-default API terms for both providers, since it's the same underlying vendor account.

**Why one vendor for both StylistReasoningProvider and VisionAnalysisProvider server-side leg.** This wasn't a foregone conclusion — §2.5's original criteria table treated this as an open question (dedicated fashion-classification API vs. general vision-language model) independent of the reasoning-provider choice. Using GPT-5.6 for both:
- Simplifies the vendor relationship and the account-level legal/retention gate to one negotiation instead of two (relevant to §29 and §25).
- Means the confidence-based escalation pattern (Luna → Terra on low confidence) is one mechanism, reusable across both providers' Edge Functions rather than two different retry/tier systems with different thresholds and different monitoring.
- Costs nothing in flexibility per ADR 0004 — `VisionAnalysisProvider` remains its own protocol with its own adapter; nothing in the interface couples it to `StylistReasoningProvider`'s vendor. A future finding that a dedicated fashion-classification vendor materially outperforms GPT-5.6 on subcategory accuracy is a swap of one adapter, not an architecture change.

**Rejected alternatives:**

- **A dedicated fashion-classification/fine-tuned vision API as the default.** Not rejected outright — genuinely evaluate this if the pilot accuracy check above comes back weak on subcategory granularity. Deferred rather than adopted at launch because: (a) it adds a second vendor relationship and a second data-retention/legal review before the app can ship at all, (b) no specific candidate was researched/verified for this task (the verified facts cover GPT-5.6 only), and (c) the taxonomy-steering approach is untested but plausible given the formality-anchor-blend design was built specifically to make a general VLM workable for this domain.
- **Terra as the default server-side tier (not just the low-confidence escalation).** Rejected on cost: per `09-model-routing.md` §5, this roughly 2.5× the per-scan reasoning cost for a capability gain that (pending the pilot above) may not be needed for the large majority of scans — garment classification is a bounded, well-specified extraction task, closer to the "everyday work" Luna is positioned for than the "complex professional work" Terra/Sol are priced for.
- **A two-model split (dedicated OCR service + separate VLM classification)** as suggested as an option in the original criteria table. Rejected as unnecessary given the pipeline already puts OCR on-device (Apple Vision) — adding a *third*, server-side OCR vendor on top of an already-working on-device OCR pass would be redundant, not complementary.

**Cost model.** Full per-scan arithmetic (image tokens, output tokens, Luna vs. Terra, the 7.5% escalation-retry rate) is in `09-model-routing.md` §5. Note the escalation here is **additive**, not substitutive — a low-confidence scan pays for *both* the Luna attempt and the Terra retry, since the Luna result is what determines whether the retry fires at all, unlike some of the routing-decision escalations in `09` (e.g., a known-expensive product triggering Terra directly) where only one call happens.

**Latency budget.** Unchanged from §2.4 — the ≤5.5s p50 server-leg budget is a per-call budget; a low-confidence retry that fires a second Terra call pays that budget twice in sequence for the ~5–10% of scans it affects, which is an accepted tradeoff (a slower, more accurate result beats a fast, wrong one for a field the user will otherwise have to hand-correct) but worth watching in the item-analysis-latency metric specifically for the retried subset, not just the aggregate.

**Conditions that should trigger revisiting this choice:**

- The pre-launch pilot (labeled real-scan-photo sample) shows GPT-5.6 Luna's subcategory classification accuracy is not acceptable against a defined bar (this bar itself is a product decision to set before the pilot runs, not defined by this document) — triggers either defaulting classification to Terra or evaluating a dedicated fashion-classification vendor per the rejected-alternative note above.
- The measured low-confidence escalation rate in production sustains materially outside the 5–10% planning range (either direction) — below the range may mean the confidence threshold is set too loosely (undercatching genuinely wrong results); above it may mean Luna's base accuracy is worse than the pilot suggested, or the threshold is too strict. Either way this is a `09-model-routing.md` §7 quality-loop signal, not a one-time check.
- OCR-derived brand-guess accuracy (calibrated against `brandGuess.confidence`) shows a pattern of confident-but-wrong guesses reaching users without the low-confidence marking the system is designed to attach — per §2.1's explicit concern that "a wrong high-confidence brand guess is worse than an honest low-confidence one." This is a P1-severity signal regardless of which vendor is in use.
- Data retention/training terms change per the same legal-gate logic as §1.5.

---

## 3. ImageGenerationProvider

Backs Style Studio (§13, detailed in §9 of this document).

```typescript
// core/providers/ImageGenerationProvider.ts

export interface StudioGenerationRequest {
  referenceImageStoragePath: string;
  identityRepresentation?: string; // provider-specific identity/reference token from a prior
                                    // preprocessing step, if the provider requires one (e.g. a
                                    // face/body embedding or LoRA reference), null if the
                                    // provider accepts the raw reference image directly
  structuredGarmentList: Array<{
    role: string;              // top | bottom | outerwear | shoes | accessory
    normalizedTitle: string;
    colorDescription: string;
    material: string[];
  }>;
  pose: string;
  background: string;
  lighting: string;
  formality: string;
  resolution: "draft" | "hi_res";
  preserveFace: boolean;
  preserveBodyProportions: boolean;
  preserveHairFacialHair: boolean;
}

export interface StudioGenerationResult {
  status: "queued" | "generating" | "complete" | "failed";
  resultStoragePath: string | null;
  providerJobId: string;
  errorMessage: string | null;
  isRetryableFailure: boolean;
}

export interface ImageGenerationProvider {
  /** Submits a job; does not block for completion — always async/queued
   *  per §13's cost controls, even for "draft" resolution. */
  submitGeneration(
    request: StudioGenerationRequest,
    ctx: ProviderRequestContext,
  ): Promise<{ providerJobId: string }>;

  pollStatus(
    providerJobId: string,
    ctx: ProviderRequestContext,
  ): Promise<StudioGenerationResult>;

  /** Some providers push completion via webhook instead of/in addition to
   *  polling — normalize both into the same StudioGenerationResult shape. */
  handleWebhook(payload: unknown): StudioGenerationResult;
}
```

### 3.1 Capability requirements

- Reference-image-conditioned generation that preserves identity (face, body proportions, skin tone, hair) while changing clothing — this is a narrower capability than general text-to-image, and not every image generation vendor supports it well; identity preservation quality is the single biggest differentiator for this use case.
- Structured/multi-garment prompt steerability (a single flattened text prompt describing multiple exact garments reliably is harder than it looks — test against outfits with 4+ distinct pieces, not just a single hero item).
- Async job submission with either webhook or poll-based completion (never a synchronous call — draft generation alone targets up to 30s, §20, incompatible with holding an Edge Function connection open synchronously).
- Content moderation on **both** the input reference image and the output, with a documented, checkable policy (feeds directly into the consent-validation step, §9.3).

### 3.2 Failure and retry semantics

Provider-side generation failures are common enough in this category (content policy edge cases, transient capacity, occasional garbled output) that the master spec explicitly calls for preserving the prompt and allowing retry **without consuming another credit when the failure is provider-side** (§21). Implementation:

```
on submitGeneration/pollStatus returning status="failed":
  isRetryableFailure = true  UNLESS the failure reason is CONTENT_MODERATION_REJECTED
    (a moderation rejection is not retried automatically — it routes to a user-facing
    explanation and does not silently retry the same rejected input)
  if isRetryableFailure:
    the studio_generations row's quota-consumption flag is NOT set until status="complete"
    — i.e., quota is debited on success, not on submission, so a provider-side failure
    never costs the user a credit
  the client retry re-submits the SAME prompt_payload (preserved in studio_generations,
    per §21) without requiring the user to reconfigure anything
```

### 3.3 Cost drivers and control

This is the most expensive provider per call by a wide margin, and §13's cost controls are specified precisely for that reason:

- **Queueing.** All generations go through a job queue (`studio_generations` table as the queue, or a dedicated queue if request volume outgrows polling the table directly), not direct synchronous provider calls — this is what makes rate limiting and cost smoothing possible at all.
- **Rate limiting by tier.** A token-bucket limiter keyed on `(user_id, subscription_tier)`, refilled per the tier's monthly quota (§16: one trial for Free, a higher monthly quota for Premium — exact quota numbers are a subscription-economics decision, not an algorithmic one, and live in the admin-configurable tier table, §28).
- **Caching repeated combinations.** Cache key = `hash(referenceImageStoragePath, structuredGarmentList, pose, background, lighting, resolution)`. An identical request (e.g., double-tap on "generate," or the same outfit viewed again) returns the cached result without a new provider call or quota debit. TTL: 90 days (long enough to cover realistic repeat-viewing, short enough to bound storage).
- **Draft before hi-res.** Draft resolution is the default and the only one that runs on the free/standard quota path; hi-res export is a distinct, explicitly more expensive action (separate quota bucket or a one-time upsell) gated behind the user having already seen and accepted a draft — nobody pays hi-res cost for a result they haven't previewed.
- **Abandoned reference image cleanup.** A scheduled job deletes reference images that were uploaded but never converted into a saved generation after a configurable retention window (default 30 days — matches the general retention posture implied by §29), reducing both storage cost and the standing privacy liability of holding personal photos indefinitely.

### 3.4 Latency budget

Target: **draft generation under 30 seconds, with progress state** (§20) — the "with progress state" qualifier is load-bearing: this is the one provider where the UI is explicitly designed around not needing sub-2.5s response, so the budget allocation is looser and queue-wait-aware:

| Stage | Budget |
|---|---|
| Consent + moderation validation (§9.3) | 800ms |
| Queue wait (varies with load; shown to user as position/ETA, not a blind spinner, once it would exceed ~3s) | variable, target p50 < 5s |
| Provider draft generation | ≤ 20s |
| Result storage + client fetch | 1.5s |
| Margin | remainder |

If provider generation itself is trending to exceed its 20s allocation under load (observed via the p95 metric), the queue-wait ETA shown to the user is adjusted to reflect reality rather than understating it — an inaccurate ETA is worse than a longer, honest one.

### 3.5 DECISION — ImageGenerationProvider vendor

```
╔══════════════════════════════════════════════════════════════════╗
║ DECISION: Higgsfield (Soul 2.0 / `soul_2`).                       ║
║ Resolved 2026-07-28. Owner: Tyler.                                ║
╚══════════════════════════════════════════════════════════════════╝
```

**What was chosen.** Higgsfield's Soul 2.0 model (`soul_2`) backs `ImageGenerationProvider` in production, satisfying the core requirement from §3.1: reference-image-conditioned generation that preserves identity (face, body proportions, skin tone, hair) while changing clothing, driven by the structured multi-garment prompt in §8.2 above.

**Rationale, in brief.** Soul 2.0 was selected against the criteria in the original decision table above — identity preservation quality across diverse subjects, multi-garment prompt steerability for the typical 3–5-piece outfit, async job API maturity (needed for the queueing architecture in §3.3 regardless of vendor), content moderation configurability (feeds §9.3's consent-validation gate), and data retention terms compatible with §29's hardest legal gate in this document, since reference photos are faces — the single most sensitive input class in the whole system.

**This document does not duplicate the full integration detail.** The Higgsfield-specific request/response mapping, job lifecycle, moderation configuration, pricing tier selection (draft vs. hi-res), and how Soul 2.0's specific API surface maps onto the `StudioGenerationRequest`/`StudioGenerationResult` protocol above is specified in **`docs/10-style-studio-integration.md`** — that document is the authoritative source for anything Higgsfield-specific (endpoint shapes, `soul_2` parameters, webhook payloads, rate limits, and the draft/hi-res cost split that feeds §16's tier quota economics). This section exists only to close out the decision record for §3 and keep this document's five-provider structure complete; **do not duplicate Style Studio integration detail here** — if this section and `docs/10` ever disagree, `docs/10` is the more specific and more current source for Higgsfield mechanics, and this section should be updated to match, not the other way around.

**What stays true regardless of the Higgsfield-specific detail living elsewhere:** the `ImageGenerationProvider` protocol in §3 above, the async submit/poll/webhook pattern in §3.1–3.2, the queueing/rate-limiting/caching cost controls in §3.3, the consent validation gate in §8.3, and the latency budget in §3.4 are all vendor-neutral by design (ADR 0004) and do not change based on which vendor implements them. A future Higgsfield pricing or policy change, or a full vendor swap, is scoped to `docs/10` and the concrete adapter — not a rewrite of this section or the interfaces above it.

**Conditions that should trigger revisiting this choice:** tracked in `docs/10-style-studio-integration.md`, not restated here — see that document for Higgsfield-specific triggers (identity-preservation quality regressions, cost-per-generation changes, moderation policy changes, determinism/caching behavior at a fixed seed). The general-purpose legal gate (§29 no-training-on-reference-photos) and the general cost-control levers (§3.3) remain this document's concern and apply to whichever vendor is in the `ImageGenerationProvider` slot.

---

## 4. EmbeddingProvider

Backs closet-item search/retrieval (`06-kyra-orchestration.md` §1.5), style-profile similarity, and product matching — all via `pgvector`.

```typescript
// core/providers/EmbeddingProvider.ts

export interface EmbeddingRequest {
  inputs: Array<{ id: string; kind: "text" | "image"; content: string }>;
  // content = raw text for kind="text"; a signed storage path for kind="image"
  purpose: "closet_item" | "style_profile" | "product" | "query"; // some vendors expose
    // purpose-tuned embedding modes (e.g. "search query" vs "document") — pass through if supported
}

export interface EmbeddingResult {
  embeddings: Array<{ id: string; vector: number[] }>;
  dimension: number;
  modelIdentifier: string;
}

export interface EmbeddingProvider {
  embed(request: EmbeddingRequest, ctx: ProviderRequestContext): Promise<EmbeddingResult>;
}
```

### 4.1 Capability requirements

- A single fixed output dimension for the life of the deployed schema (`vector` columns in `closet_items`, `outfits`, `style_profiles`, `style_memories` per §9 are dimension-locked at table creation). **Judgment call:** changing embedding model/dimension later requires a full re-embedding backfill migration of every existing vector column — this should be treated as a rare, deliberate migration, not a casual vendor swap, and the model identifier is stored alongside every embedding (`modelIdentifier` above) specifically so a future migration can detect and re-embed stale rows.
- Multimodal (text + image) support is preferred but not required as a single model — text and image embeddings may come from different underlying models as long as both land in the same fixed dimension and the same similarity space is meaningful for cross-modal queries (e.g., a text query matching an image-embedded closet item, per `06` §1.5). If a candidate vendor's text and image embeddings are not natively co-located in one space, this needs an explicit alignment step (e.g., embedding the VLM-generated `normalizedTitle` text instead of the raw image) rather than assuming cross-modal comparability.
- Batch embedding support (closet items are embedded in batches during batch scan, §6.16).

### 4.2 Failure and retry semantics

Standard §0.1 baseline. Embedding failures are lower-stakes than the other four providers — nothing in the critical user-facing path blocks on embedding completing synchronously (item analysis returns to the user before embedding runs, §2.4; Kyra's retrieval degrades to category/recency-only ranking if the query embedding call fails, rather than blocking the whole turn).

### 4.3 Cost drivers and control

- Volume-dominated cost (many small calls: every closet item, every outfit, every query). Batch wherever the call site allows it (batch scan, bulk backfills) rather than one call per item.
- Cache query embeddings within a single Kyra turn (the context-packet retrieval step, `06` §1.5, and any tool call that also needs a query embedding in the same turn should share one embedding call, not issue it twice).
- Re-embedding is only needed on meaningful content change (item edited, memory content changed) — not on every read, and not on `wear_count`/`availability_state` changes which don't affect the item's embedded description.

### 4.4 Latency budget

Not directly named in §20, but derived: embedding calls sit on the critical path only for Kyra's per-turn query embedding (part of the 2.5s first-card budget, §1.4) — allocate **≤ 150ms** for a single-text query embedding within that budget. Bulk/batch embedding (closet backfill, item analysis follow-up) is off the interactive critical path entirely and has no hard latency requirement beyond "completes before the item is needed for retrieval," typically within a few seconds of item creation.

### 4.5 DECISION — EmbeddingProvider vendor

```
╔══════════════════════════════════════════════════════════════════╗
║ DECISION: OpenAI text-embedding-3-small, 1536 dimensions.         ║
║ Resolved 2026-07-28. Owner: Tyler.                                ║
╚══════════════════════════════════════════════════════════════════╝
```

**What was chosen.** `text-embedding-3-small` — 1536 dimensions, **$0.02 per 1M tokens** — backs `EmbeddingProvider` in production.

**This decision requires no migration.** Every `vector` column already written into `/tmp/astra/supabase/migrations/` — `style_profiles.embedding`, `closet_items.embedding`, `outfits.embedding`, `style_memories.embedding` — is declared `extensions.vector(1536)` (see `20260728100200_profiles_and_identity.sql`, `20260728100300_closet.sql`, `20260728100400_outfits.sql`, `20260728100500_feedback_and_memory.sql`), and `docs/04-data-model.md` §3's own stated rationale for choosing 1536 was explicitly "the dimensionality of OpenAI's `text-embedding-3-small` and `text-embedding-ada-002`... the most common 'default' embedding size in production use today." Choosing `text-embedding-3-small` therefore **confirms the schema exactly as already written** — this is the case where the vendor decision and the pre-existing schema decision were made to agree by construction, and no backfill, dimensionality-projection workaround, or migration is required as a result of resolving this decision.

**Why this clears the bar in §4.1 and the original criteria table:**

- **Retrieval quality on short, attribute-dense fashion text.** Not independently verified against real closet-item titles in this research pass — this is a **judgment call carried over, not resolved by the researched facts**, which confirm price and dimensionality but not domain-specific retrieval quality on strings like "olive knit polo, regular fit." Evidence that would resolve it: a spot-check of `search_closet`'s semantic-query path (`06-kyra-orchestration.md` §1.5, §3.1) against a real (or realistic synthetic) closet-item corpus before the retrieval-quality metric in `09-model-routing.md` §7 has enough production data to say anything. Flagged here so it isn't silently assumed away by the fact that the dimension and price are well-established.
- **Cross-modal coherence.** `text-embedding-3-small` is text-only, so the design uses the alignment workaround §4.1 already specifies rather than assuming native cross-modal comparability: closet items are embedded from their `normalizedTitle` (the VLM-generated text output from `VisionAnalysisProvider`, §2 above) rather than from raw image bytes. This means the embedding space is coherent by construction — every embedded "thing" (closet item, product, style profile fragment, memory) is text, so `06`'s "text query matches image-described closet item" retrieval works without a separate cross-modal alignment step, at the cost of retrieval quality being bounded by how good the `normalizedTitle` text is, not by the embedding model itself.
- **Cost at high call volume.** At $0.02/1M tokens and short item-title-length inputs (~10–15 tokens per closet item, similarly small for outfits/queries/memories), this is the cheapest of the five providers by a wide margin — see `09-model-routing.md` §5 for the arithmetic, which shows embedding cost for an engaged subscriber's full monthly usage rounding to a fraction of a cent, effectively negligible next to the reasoning-provider cost that dominates the monthly total.
- **Dimension size vs. `pgvector` performance.** 1536 is within pgvector's practical indexed-dimension range (per `docs/04-data-model.md` §3's existing note) — no change needed here since the schema was already sized for exactly this model family.
- **Stability/versioning.** `modelIdentifier` is already required on every `EmbeddingResult` (§4 interface above) specifically so a future silent model change is detectable; this decision doesn't relax that requirement — it's the mechanism that makes this decision auditable and reversible without a schema-level surprise later.

**Why not the multimodal or "reuse the reasoning vendor's embedding endpoint" alternatives named in the original criteria table.** A GPT-5.6-family embedding endpoint was not part of the researched facts for this task (only `text-embedding-3-small` was verified), so evaluating it isn't possible from what's confirmed here — if OpenAI offers a GPT-5.6-generation embedding model with better domain retrieval quality at a comparable or lower cost, that's a legitimate future candidate to pilot against `text-embedding-3-small` on the retrieval-quality metric above, not a decision to make speculatively now. `text-embedding-3-small` is chosen as the concretely verified, already-schema-aligned option, not because multimodal or reasoning-vendor-reuse approaches were evaluated and rejected on merits.

**Cost model.** See `09-model-routing.md` §5 — embeddings are volume-dominated but individually cheap enough that they don't move the monthly-subscriber total in any visible way; batching (batch scan, §4.3 above) is still worth doing for rate-limit headroom, not primarily for cost.

**Latency budget.** Unchanged from §4.4 — the ≤150ms query-embedding allocation within Kyra's 2.5s first-card budget is a latency constraint independent of which embedding vendor is in the slot; `text-embedding-3-small` is a small, fast model well within that budget for the short query strings this system embeds.

**Conditions that should trigger revisiting this choice:**

- The retrieval-quality spot-check (above) or the production retrieval-quality signal in `09-model-routing.md` §7 shows `search_closet`'s semantic path meaningfully underperforming on real attribute-dense fashion text — the first concrete evidence this decision's one open judgment call needs resolving in the other direction.
- OpenAI ships a materially better or cheaper embedding model and a re-embedding backfill migration becomes worth the one-time cost — per §4.1, this is treated as a rare, deliberate migration, gated on the `modelIdentifier`-based staleness detection already specified, not a casual swap.
- OpenAI silently updates `text-embedding-3-small`'s behavior under the same model name in a way that changes similarity-score distributions for existing vs. newly-embedded rows — watch for this via `modelIdentifier` pinning if/when OpenAI's API supports requesting a specific snapshot.

---

## 5. ProductExtractionProvider

Backs pasted-link product analysis (§5.5, §17) and the `analyze_product`/`search_products` tools.

```typescript
// core/providers/ProductExtractionProvider.ts

export interface ProductExtractionRequest {
  url: string;
}

export interface ExtractedProduct {
  canonicalUrl: string;
  retailer: string;
  brand: string;
  name: string;
  category: string;
  price: number;
  currency: string;
  imageUrl: string;
  attributes: {
    color?: string;
    material?: string[];
    sizesAvailable?: string[];
    pattern?: string;
  };
  extractionConfidence: number;
  fieldsBelowConfidenceThreshold: string[];
}

export interface ProductExtractionProvider {
  extract(
    request: ProductExtractionRequest,
    ctx: ProviderRequestContext,
  ): Promise<ExtractedProduct>;
}
```

### 5.1 Capability requirements

- Reliable structured extraction from arbitrary retailer product pages (varied HTML/JS-rendered structure, not a fixed set of known retailers) — this is the hardest capability bar of the three ingestion options named in §17 (curated catalog, affiliate feeds, user-pasted URLs), because it has to work against pages Astra doesn't control and hasn't seen before.
- Graceful partial extraction: a page that yields brand/name/price but not material should return those fields with the rest correctly empty and flagged, not fail the whole request — mirrors the "all inferred fields remain editable, low-confidence fields visibly marked" principle from §12, applied to products instead of closet items.
- Respect for retailer terms of service and robots directives — per §17's explicit instruction not to rely on unrestricted scraping as the *only* source, this provider is one leg of a three-legged ingestion strategy (curated catalog + affiliate feeds + on-demand extraction), not the sole mechanism, and its implementation must not become a de facto scraper that undermines that stated design.

### 5.2 Failure and retry semantics

```
URL_NOT_EXTRACTABLE: non-retryable — a page structure the extractor can't parse won't parse
  better on retry. Surfaced to the user as a direct, specific message ("I couldn't read that
  page — try pasting the product name instead and I'll search for it"), routing into
  search_products as a fallback path rather than a dead end.
PROVIDER_UNAVAILABLE / TIMEOUT: standard §0.1 retry baseline applies.
```

### 5.3 Cost drivers and control

- Cache extraction results in `product_candidates` keyed on `canonical_url`, refreshed on a TTL (e.g., 24–72 hours for price/availability freshness, per `last_checked_at`) rather than re-extracting on every view of the same product — the dominant cost control for this provider, since the same popular product URL will be pasted or viewed by many users.
- Prefer the curated catalog / affiliate feed path over live extraction whenever a `product_candidates` row already exists and is fresh — live extraction is the fallback for products not already in the catalog, not the default path for everything.

### 5.4 Latency budget

Not named directly in §20; derived from the shopping flow's synchronous feel (§5.5 describes pasting a link and getting an evaluation in one flow). Target **≤ 6s p50** for `extract()` end-to-end (page fetch + structured parse), consistent with `analyze_product`'s overall budget which also includes the compatibility/redundancy/unlock-count computation from `05-wardrobe-graph.md` §6 within the same user-facing wait.

### 5.5 DECISION — ProductExtractionProvider vendor

```
╔══════════════════════════════════════════════════════════════════╗
║ DECISION: OpenAI GPT-5.6 Luna with structured outputs, fetching   ║
║ and parsing the retailer page server-side.                        ║
║ Resolved 2026-07-28. Owner: Tyler.                                ║
╚══════════════════════════════════════════════════════════════════╝
```

**What was chosen.** `ProductExtractionProvider.extract()` is implemented as an Edge Function step that fetches the URL server-side, reduces the page to its meaningful content (strip nav/scripts/styling, keep structured product-relevant markup and visible text), and hands that to GPT-5.6 Luna with structured outputs constrained to the `ExtractedProduct` schema in §5 above — the "candidate archetype" this resolves to is the fetch-and-structure-with-an-LLM approach named in the original decision table, using the same vendor and tier already in use for `StylistReasoningProvider`'s default path, at Luna pricing.

**Why Luna, not Terra, as the default here.** Product-page extraction is a bounded, mechanical task — turn a page's visible content into the fields of a fixed schema — closer to Luna's "cost-sensitive, fastest execution" positioning than to work requiring deep reasoning. The failure modes this provider actually has (§5.2: `URL_NOT_EXTRACTABLE`, partial extraction) are structural — the page didn't render, or didn't contain the field — not reasoning failures a bigger model would fix. Escalating to Terra on a schema-validation failure (structured output came back malformed) is still the right move per the shared retry semantics in §0.1 and the escalation-trigger table in `09-model-routing.md` §2, but that's a validation-failure retry, not a default-tier choice.

**Why this clears the bar in §5.1 and the original criteria table:**

- **Success rate across real retailer pages.** Not independently verified in this research pass for Astra's specific target retailers — flagged explicitly as an **open judgment call**: fetch-and-structure-with-an-LLM handles static/server-rendered pages well, but the original criteria table's concern about JS-rendered pages (common on fashion retail sites) is real and not resolved by choosing GPT-5.6 specifically — it's a property of the fetch step (does the Edge Function's fetch execute JS or not), independent of which model structures the result afterward. **This is the load-bearing design point**, addressed by the fallback below rather than assumed away.
- **Structured-output reliability.** Same mechanism and gate as §1.5/§2.5 — GPT-5.6 Luna's structured-output support satisfies §5.1's requirement; §5.2's `URL_NOT_EXTRACTABLE` non-retryable failure path already exists in this document for the case where the page itself can't be parsed regardless of model quality.
- **Terms-of-service compatibility.** This is about the *source retailer's* terms, not the model vendor's, and is unchanged by this vendor decision — see §17's constraint below, which this decision does not relax.
- **Cost per extraction.** See `09-model-routing.md` §5 — Luna pricing on a moderate-length cleaned-page input plus a short structured output keeps this cheap per paste-a-link action; caching extraction results by `canonical_url` (§5.3, unchanged) is still the dominant cost control regardless of vendor, since the same popular product URL is pasted by many users.
- **Latency for the ≤6s p50 target.** The fetch step (network-bound, page-dependent) and the Luna structuring step (fast, small-context) both need to fit inside the existing §5.4 budget; this is a per-integration validation item, not resolved by the vendor choice alone.

**The fallback this decision requires, per §17.** §17 is explicit: "Do not rely on unrestricted scraping as the only product source" — a rule this provider's implementation must not undermine regardless of which vendor structures the extracted content. Concretely:

1. **JS-rendered or fetch-blocked pages.** When the server-side fetch returns a page that's substantially empty of product content (JS-rendered, client-side-only rendering) or the retailer blocks the fetch (robots directive, bot-detection response, non-200 status), the extraction fails as `URL_NOT_EXTRACTABLE` per §5.2's existing non-retryable path — it is **not** escalated to a headless-browser/JS-execution fetch as a workaround. Adding JS execution to bypass a page's own rendering/access posture is exactly the "become a de facto scraper" risk §5.1 already warns against, and turns a bounded, ToS-conscious extraction feature into an arms race with individual retailers' anti-bot measures. The failure surfaces to the user via the existing specific, in-voice message ("I couldn't read that page — try pasting the product name instead") and routes into `search_products` (§3.5 of `06-kyra-orchestration.md`) as the recovery path.
2. **This provider is one leg of three, not the primary path.** Per §17's ingestion strategy (curated catalog, affiliate feeds, on-demand extraction) and §5.3's cache-and-prefer-catalog design (already specified above), on-demand extraction via this provider is the fallback for products *not already in* the curated catalog or affiliate feed, not the default ingestion mechanism for the product catalog as a whole. This decision does not change that priority order — it only resolves which model structures the fallback leg's output.

**Rejected alternatives:**

- **A dedicated general-purpose web-content-extraction/structured-scraping API**, named as a candidate in the original table. Not rejected on merits — genuinely worth piloting against real retailer URLs if the fetch-and-structure approach above shows a JS-rendered-page failure rate high enough to matter (see "conditions to revisit"). Not chosen at launch because it's a second vendor relationship and a second legal/ToS review, for a capability (JS rendering) this design deliberately does not want by default, per the §17 fallback rule above — a purpose-built extraction service that *does* execute JS would need the same ToS-compliance guardrail applied to it, not less.
- **Reusing `VisionAnalysisProvider`'s vendor with browsing/fetch tool access** to read and structure the page directly inside a tool-calling loop, rather than a dedicated fetch-then-structure Edge Function step. Rejected for this decision: it's operationally the same vendor either way (GPT-5.6), so the "one fewer vendor relationship" benefit named in the original table doesn't differentiate here — the real choice was fetch-then-structure (deterministic, one clean Edge Function step, easy to cache and test) vs. an agentic browsing loop (more flexible, harder to bound cost and latency against the ≤6s p50 target, harder to guarantee doesn't silently start executing JS or following redirects into ToS-questionable territory). The bounded, deterministic version was chosen for cost/latency predictability and for the §17 fallback rule being easier to enforce as a hard branch in code rather than as model-directed browsing behavior.

**Cost model.** See `09-model-routing.md` §5 — Luna-tier extraction, cleaned-page-content input, short structured output, with `canonical_url` caching (§5.3, unchanged) as the primary volume-cost control.

**Latency budget.** Unchanged from §5.4 — the ≤6s p50 target for `extract()` end-to-end includes both the fetch and the Luna structuring step; validate this against real retailer response times once the integration is live, since fetch latency (not model latency) is likely the larger, more variable component.

**Conditions that should trigger revisiting this choice:**

- The `URL_NOT_EXTRACTABLE` rate in production, sampled against Astra's actual user-pasted retailer URLs, is high enough that the JS-rendered-page gap materially hurts the shopping flow — this is the concrete trigger for piloting a dedicated extraction vendor (with JS-rendering capability and its own ToS-compliance review) as a second leg, not a replacement, for this provider.
- Schema-validation-failure rate (structured output not matching `ExtractedProduct`) is high enough that Terra should become the default tier rather than an escalation — tracked as a `09-model-routing.md` §7 metric, same mechanism as the other GPT-5.6-backed providers.
- A specific retailer's terms of service or robots directives change in a way that makes even the bounded, non-JS-executing fetch approach non-compliant for that retailer — handled per-retailer (exclude that retailer from on-demand extraction, rely on the catalog/affiliate-feed legs instead), not a reason to change the vendor.

---

## 6. Latency budget summary (cross-provider, vs. §20 targets)

| §20 target | Providers involved | This document's allocation |
|---|---|---|
| Item analysis < 8s | VisionAnalysisProvider | §2.4 — 5.5s server leg within the 8s total |
| Kyra first token/card < 2.5s | StylistReasoningProvider, EmbeddingProvider (query embed) | §1.4 — 1,200ms provider TTFT + 150ms query embed, within the 2.5s total |
| Draft Studio generation < 30s, with progress state | ImageGenerationProvider | §3.4 — ≤20s generation + queue/consent overhead, progress-state-aware |
| (Not named in §20, derived) Product link analysis, synchronous feel per §5.5 | ProductExtractionProvider | §5.4 — ≤6s p50 |

---

## 7. CV Pipeline Split (§12)

### 7.1 The boundary

| Runs on-device (Vision framework, AVFoundation) | Runs server-side (VisionAnalysisProvider) |
|---|---|
| Blur/exposure detection | Fine-grained category/subcategory classification |
| Garment-region detection | Material/pattern semantic cues |
| Foreground segmentation (where supported) | Brand inference from OCR text (needs broader reasoning, not just text matching) |
| OCR of label text (raw text extraction) | Condition estimation (holistic judgment call) |
| Dominant color extraction (color quantization, not semantic classification) | Formality anchor resolution (§3 of `05-wardrobe-graph.md`) |
| Resize/compress/strip metadata | Searchable embedding generation |
| — | Background-removal fallback if the on-device segmentation result is inadequate |

### 7.2 Why this boundary, specifically

1. **Capability ceiling.** Fine-grained menswear classification (distinguishing a knit polo from a piqué polo from a performance polo, or estimating condition from wear patterns) exceeds what's practical to run in an on-device model within a mobile app's size/battery/latency constraints. Blur detection, region detection, and color quantization are commodity, fast, well-supported natively by Vision, and don't need that ceiling.
2. **Embedding consistency.** All closet-item and product embeddings must come from the *same* canonical model version so `pgvector` similarity comparisons are meaningful across users and across the product catalog (`06-kyra-orchestration.md` §1.5's retrieval, `05-wardrobe-graph.md`'s scoring). A per-device, per-OS-version on-device embedding model would silently fragment that space — this has to be server-side and centrally versioned by construction, not as a preference.
3. **Update velocity without an App Store release.** The formality-anchor rubric, taxonomy, and classification prompt (`05-wardrobe-graph.md` §3) need to be tunable centrally — an admin-editable table plus a server-side prompt, per §28 — without shipping a new iOS build every time the anchor examples or category list are refined. Anything baked into an on-device model can't move at that speed.
4. **Cost and latency shaping.** Sending only the already-cropped, already-compressed image (post on-device segmentation) rather than a raw multi-megabyte capture is what makes the §2.4 latency budget and §2.3 cost model work at all — the on-device pass isn't just "the easy stuff," it's the thing that makes the expensive stuff affordable and fast by shrinking the payload before it ever reaches a paid API call.
5. **Instant local feedback loop.** Blur warning, lighting indicator, background-quality feedback, and shutter feedback (§6.16) all need to be immediate (no network round-trip) for the scanner UI to feel responsive — this is a hard product requirement (§20: "Scanner shutter feedback: immediate") that only an on-device pass can satisfy.

### 7.3 What crosses the boundary, and what doesn't

The device uploads: the cropped/segmented image, device-derived color hints, and raw OCR text (as `deviceHints` in the §2 request shape) — passed as **priors**, not blindly trusted; the server-side result can and does override a weak on-device guess (e.g., `approximateCategory` is a hint the VLM classification can disagree with, not a locked-in value). The device never uploads the raw, uncompressed original capture (§12 step 6/7: "resize and compress," "strip unnecessary metadata" happen before upload, not after).

---

## 8. Style Studio Pipeline (§13)

### 8.1 End-to-end flow, mapped to providers

```
1. User selects a reference image (from a prior consented capture/import).
2. Consent + content validation (§8.3 below) — gate, not optional.
3. ImageGenerationProvider.submitGeneration() with:
   - the structured garment list built from exact owned/candidate items (never a vague
     text description when exact item data is available — "olive knit polo, regular fit,
     ribbed collar" from the item's own analyzed attributes, not "a green shirt")
   - preserveFace / preserveBodyProportions / preserveHairFacialHair all defaulted true,
     per §13 step 5's "preserve proportions; do not beautify or alter body unless
     explicitly requested"
4. Job enters the queue (§3.3); status polled or pushed via webhook.
5. Draft resolution result returned first; hi-res only on explicit follow-up action.
6. Result stored with the studio_generations row; disclaimer text is attached to the
   result at storage time, not composed ad hoc at display time, so it can never be
   accidentally omitted by a client that forgets to add it.
7. Generation metadata (provider, prompt_payload, model identifier) stored for
   debugging/audit — never the reference image's raw biometric-adjacent data beyond
   what's needed to regenerate/retry, per §14's "avoid logging private images."
```

### 8.2 Prompt template, structured

The master spec's prompt template (§13) is a natural-language frame; the actual request built for `ImageGenerationProvider.submitGeneration()` populates it from structured fields rather than string-concatenating free text, so the same garment data that drives compatibility scoring (`05-wardrobe-graph.md`) also drives the visual — no separate, potentially-inconsistent description path:

```typescript
function buildStudioPrompt(req: StudioGenerationRequest): string {
  const garments = req.structuredGarmentList
    .map(g => `${g.role}: ${g.normalizedTitle}, ${g.colorDescription}, ${g.material.join("/")}`)
    .join("; ");
  return [
    "Create a realistic editorial menswear visualization using the provided",
    "authorized reference image. Preserve the person's recognizable facial",
    "features, body proportions, skin tone, hair, and facial hair.",
    `Dress him in: ${garments}.`,
    `Use ${req.pose} pose, ${req.background} background, and ${req.lighting} lighting.`,
    "The image is a visual styling estimate, not an exact representation of",
    "garment fit or color.",
  ].join(" ");
}
```

### 8.3 Consent validation step

A required gate before step 3 above, not a one-time checkbox at capture time only:

```
1. Ownership/permission attestation: captured once at reference-image capture/import
   time (§6.7, §29's "terms prohibit uploading images without permission"), stored as
   a consent record { userId, imageId, attestedAt, termsVersion }. Re-required if the
   image is re-imported or if termsVersion has changed since the original attestation.

2. Self-identity plausibility check: cannot be cryptographically verified, but the
   consent UI is explicit about what's being attested ("this is a photo of me, or of
   someone who has given me permission to use their photo here") rather than a vague
   generic ToS checkbox — this is a product/legal design choice, not an algorithmic one,
   but the validation STEP itself (checking the attestation record exists and is current
   before allowing generation) is enforced in code at the Edge Function, not left to
   client-side UI discipline alone.

3. Content moderation, server-side, on the reference image itself, BEFORE it is sent to
   ImageGenerationProvider: rejects images flagged for minors, non-consensual content
   categories, or content outside the "authorized personal reference photo" use case.
   With the vendor now resolved (§3.5: Higgsfield), whether Higgsfield's built-in
   moderation is sufficient for this specific gate on its own, or needs a dedicated
   moderation call layered in front of it, is Higgsfield-integration detail — specified
   in `docs/10-style-studio-integration.md`, not here. What does not move regardless of
   that detail: this gate is enforced in code at the Edge Function, runs before the
   image is ever sent to the provider, and must not have a blind spot.

4. Per-generation re-validation: the consent record is checked (not re-collected from
   the user) on every submitGeneration() call — an expired or missing consent record
   blocks the call before it reaches the provider, fails with a clear, specific
   in-product message, and does not consume quota.

5. Deletion propagation: deleting a reference image (user-initiated, §29's "delete
   individual reference and generated images") invalidates its consent record and
   removes it from the eligible-reference list immediately — a deleted image can never
   be the basis of a subsequent generation, including from a cached job reference.
```

**Judgment call:** step 2's "plausibility check" cannot be made cryptographically rigorous with current, reasonably-available tooling without adding friction disproportionate to the risk at this stage of the product — the design instead makes the attestation explicit and specific (rather than generic ToS boilerplate) and pairs it with the content-moderation gate (step 3) as the actual technical backstop, since moderation can catch categories of misuse that a self-attestation checkbox cannot.
