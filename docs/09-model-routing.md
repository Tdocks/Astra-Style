# 09 — Model Routing: Escalation Router Specification

**Status:** Implementation-ready
**Depends on:** `08-provider-abstraction.md` §1 (StylistReasoningProvider, incl. §1.5's vendor decision record), §2 (VisionAnalysisProvider), §5 (ProductExtractionProvider); `06-kyra-orchestration.md` §1 (context packet budget), §2 (system prompt), §3 (tool schemas), §4 (response schema), §7 (evaluation); `00-master-spec.md` §16 (subscription pricing), §18 (analytics/north-star metrics), §20 (performance targets), §28 (admin config)
**Owner surface:** A single component — the **escalation router** — invoked by every Edge Function that calls `StylistReasoningProvider`, `VisionAnalysisProvider`, or `ProductExtractionProvider` at the GPT-5.6 default tier. It is not a separate service; it's a shared TypeScript module (`core/routing/escalationRouter.ts`) that every relevant Edge Function imports, so the policy lives in one place instead of being reimplemented per endpoint.

---

## 0. Purpose and scope

`08-provider-abstraction.md` §1.5, §2.5, and §5.5 establish **that** GPT-5.6 is used at two operational tiers (Luna default, Terra escalation, Sol as a narrow ceiling) across three of the five providers. This document specifies **how a given request picks a tier**, precisely enough to implement without further judgment calls at the code level — and where a judgment call genuinely remains open, it is marked as such rather than papered over with a plausible-sounding default.

The router answers exactly one question per call: **given this call type and these signals, which tier does this attempt run on, and does a first attempt's result trigger a second attempt on a higher tier?** It does not decide *whether* to make a call (that's the calling Edge Function's job) and it does not implement retries for transient provider errors (that's `08` §0.1's shared retry/circuit-breaker baseline, which is orthogonal to tier selection and applies identically at every tier).

---

## 1. Routing policy per call type

Every distinct model call the app makes, its default tier, and why. "Default" means: absent any escalation trigger firing (§2), this is the tier the call runs on.

| # | Call type | Default tier | Volume shape | Why this default |
|---|---|---|---|---|
| 1 | Daily Brief generation | **Luna** | Highest frequency of any call type — up to once per DAU per day | Single-shot generation from an already-retrieved, already-ranked candidate set (the hard relevance work happened in retrieval/scoring, not in this call); the job is picking the strongest option and writing 1–2 sentences of why, which is squarely "everyday work" in Luna's positioning. At this volume, a tier upgrade is a direct multiplier on the single largest cost line by call count — see §5. |
| 2 | Conversational Kyra turns | **Luna** | High frequency — the bulk of interactive usage | Per the owner's resolved decision (`08` §1.5): Luna is the default for *all* conversational turns regardless of `intent`, not a per-intent tier table. The context packet (`06` §1) already does the work of narrowing what's relevant; most turns are applying stylist judgment to a pre-curated set, not solving an open-ended problem. Escalation (§2) is the mechanism that catches the turns that actually need more, rather than a static intent→tier table trying to guess in advance which turns those are. |
| 3 | Product verdicts (`analyze_product` / `POST /products/evaluate`) | **Luna**, with a pre-call routing escalation on price/budget signal (§2.6) | Moderate frequency, engaged-shopper-correlated | Most product evaluations are low-to-moderate price items where a wrong verdict costs the user little; the ones where it matters (a `buy` verdict the user will act on for real money) are identifiable *before* the call from the product's price alone — so this is designed as a pre-call routing decision, not a post-hoc retry, for the subset that's knowably high-stakes. |
| 4 | Garment classification (`VisionAnalysisProvider.analyzeGarment`, first pass) | **Luna** | High frequency at onboarding, moderate steady-state | Per `08` §2.5's resolved decision — bounded extraction/classification task against a fixed taxonomy, with the hardest sub-problem (label OCR) already handled on-device. Pending the pre-launch accuracy pilot noted in `08` §2.5. |
| 5 | Low-confidence garment re-analysis | **Terra** (always — this call type *is* the escalation) | 5–10% of scans (planning midpoint: 7.5%) | Not a "default tier" in the usual sense — it only exists because a Luna attempt already returned below-threshold confidence. Terra runs unconditionally when this path fires; there is no further escalation trigger logic for this specific call, since the confidence check that triggers it already happened. |
| 6 | Style DNA generation | **Terra** | Very low frequency — effectively once per user (onboarding), rare regeneration | Foundational, high-perceived-quality-stakes, and structurally low-volume — this is the Definition of Done's "receive a coherent Style DNA" moment (§30 of the master spec) and the first real demonstration of Kyra's judgment a new user sees. Low call volume means the Terra-vs-Luna cost delta here is immaterial to the monthly cost model (§5) even though the *per-call* cost is higher — an easy, low-risk place to default to the better tier. |
| 7 | Packing list generation (`create_packing_list` / `POST /packing/generate`) | **Luna**, with a pre-call routing escalation on multi-constraint complexity (§2.5) | Low-to-moderate frequency, trip-correlated | Most packing requests are single-destination, single-dress-code, and mechanically similar to a Daily Brief stretched over several days — Luna-appropriate. Multi-constraint asks (the "four-day trip with two dress codes" example) are a different, genuinely harder shape, identifiable from the request's own structured fields before the call runs. |
| 8 | Monthly review | **Terra** | Very low frequency — once per user per month | Same logic as Style DNA: low volume, high narrative/retrospective-judgment value, a retention-relevant premium touchpoint (§16: "Monthly reviews" is a named Premium-tier benefit). The cost delta at this volume is negligible (§5). |
| 9 | Product URL extraction (`ProductExtractionProvider.extract`) | **Luna** | Low-to-moderate frequency, paste-a-link-correlated | Per `08` §5.5's resolved decision — a bounded, mechanical extraction task where the failure modes (page didn't render, page didn't contain the field) are structural, not reasoning failures a bigger model fixes. Escalates only on schema-validation failure (§2.2), not on any content-based trigger. |
| 10 | Outfit ranking explanations (the natural-language `reason` accompanying `rank_outfits`/`OutfitCard` results) | **Luna** | Embedded in call types 1–2 above, not a separate top-level call in the common case | `rank_outfits`' `compatibility_score` and `component_breakdown` are **deterministic**, computed from the wardrobe-graph scoring weights (`00-master-spec.md` §10), not model output — the model's only job here is turning an already-computed score breakdown into 1–2 sentences of natural language, which is exactly the low-ambiguity, templated-shape work Luna is positioned for. Escalates only via the rejection-retry trigger (§2.4) if a user explicitly pushes back on a ranking and asks again. |

**Note on cost accounting:** call type 10 is not separately volume-modeled in §5 — its cost is already inside the Kyra-turn and Daily-Brief line items, since it's generated as part of those responses, not as an independent API call. Listing it here satisfies the routing-policy requirement (every call type needs an assigned tier and a justification) without double-counting cost.

---

## 2. Escalation triggers

Two structurally different kinds of trigger exist, and conflating them produces the wrong cost/latency model:

- **Retry triggers** (§2.1–2.3): the Luna call *already ran*, and its own result signals it should be redone on Terra. Cost is **additive** (both calls are paid for).
- **Routing triggers** (§2.4–2.6): the request's own properties are known *before* any call runs, so the router sends it straight to Terra and Luna never runs for that request. Cost is **substitutive** (only one call is paid for).

### 2.1 Self-reported confidence below threshold (retry)

```
condition: response.confidence < 0.55   (StylistReasoningProvider, KyraResponse.confidence)
        OR any field in fieldsBelowConfidenceThreshold that is also in a
           configured "escalation-worthy fields" list (VisionAnalysisProvider —
           see §2.7 below for which fields qualify)
        OR extractionConfidence < 0.55  (ProductExtractionProvider)

action: retry the SAME request on Terra. Use the Terra result outright — do not
        blend Terra and Luna outputs field-by-field; a blended result reintroduces
        the ambiguity this trigger exists to resolve.
```

**Why 0.55, not 0.5.** `06-kyra-orchestration.md` §4's response schema already treats `confidence < 0.5` as the point where the client should show hedged language. Setting the retry threshold at 0.55 — slightly above that — means the router gets a chance to produce a *better* answer before the user ever sees a hedged one, rather than only reacting after the fact. **This exact number is a judgment call, not a verified fact** — the research for this task confirmed GPT-5.6's confidence-reporting capability exists but not its calibration curve. Evidence that resolves it: the confidence-calibration metric in §7 below, run against real production data once volume exists; until then, 0.55 is the launch default and must be a config value (§8), not a hardcoded constant.

### 2.2 Structured-output schema validation failure (retry)

```
condition: the response fails JSON Schema validation against the call's
           response schema (KyraResponse, GarmentAnalysisResult, or
           ExtractedProduct) AND the same-tier repair-retry already specified
           in 06-kyra-orchestration.md §6 (re-prompt with the validation error,
           one attempt) has ALSO failed.

action: the repair-retry's SECOND attempt runs on Terra, not Luna again —
        i.e., the sequence is [Luna attempt 1] -> fails validation ->
        [Luna repair-retry] -> fails validation -> [Terra repair-retry,
        validation error still attached] -> if this also fails, fall through
        to the safe-fallback response (06 §6's malformed-JSON path) rather
        than trying a third tier.
```

This is the one trigger that's a strict tightening of an *existing* mechanism (`06` §6's repair-retry), not a new one — the only change is which tier the second repair attempt runs on.

### 2.3 Tool-call loop exceeding N iterations (retry)

```
condition: a single turn's tool-calling loop (successive finishReason ===
           "tool_calls" responses within one logical turn) exceeds
           N_luna = 4 iterations without reaching a "stop" finish reason.

action: abort the Luna attempt (do not let it run unbounded), retry the
        entire turn on Terra with the tool-call history preserved as
        context, capped at N_terra = 6 iterations. If the Terra attempt
        also exceeds its cap, fall through to the safe-fallback response
        (06 §6's tool-call-failure path) — do not escalate a third time.
```

**Why N=4 for Luna.** The documented multi-tool flows in `06`'s tool schemas (§3) — e.g., `get_weather` → `get_schedule` → `search_closet` → `rank_outfits` for a daily-outfit ask — chain 3–4 tools in the common case. Exceeding 4 on the default tier is a signal the model is thrashing (re-calling a tool with near-identical arguments, or oscillating between two tool choices) rather than legitimately working through a long chain, and Terra's iteration cap is set one notch higher (6) rather than unbounded, so a genuinely stuck Terra attempt still terminates into the safe-fallback path instead of consuming tool-call budget indefinitely.

### 2.4 User explicitly rejecting a recommendation and asking again (routing, deterministic — not sentiment-based)

```
condition: this is the 2nd or later consecutive user turn, within the same
           logical task/thread, requesting the same intent
           (daily_outfit | product_advice | outfit_review | packing)
        AND the prior turn's response in this thread received no positive
           action (no wear_this / save_outfit / purchase-adjacent
           suggested_action was taken, AND no outfit_marked_worn or
           affiliate_link_opened analytics event followed it within the
           thread's session).

action: route this turn directly to Terra (not a retry — this is a
        pre-call decision, since the prior turn's outcome is already known
        before this new call starts).
```

**Why deterministic rather than sentiment/NLU-based.** Detecting "the user is unhappy" from message text is itself a model-reasoning task with its own failure modes — using it as an escalation *precondition* would make the escalation decision only as reliable as an unverified sentiment classifier. The behavioral signal (repeated same-intent ask, no positive action on the prior turn) is directly observable from already-logged analytics events (`00-master-spec.md` §18) and needs no additional model call to compute.

### 2.5 Request complexity signals — multi-constraint asks (routing)

```
condition (packing lists): dress_codes.length >= 2
                         OR (end_date - start_date) >= 4 days AND
                            luggage_constraint is set
condition (Kyra turns generally): count of distinct constraint dimensions
   present in requested_task + attachments + occasions >= 2, where a
   "constraint dimension" is one of: multiple occasions in one ask,
   an explicit multi-item product comparison request, a stated hard
   budget ceiling combined with a stated brand/material preference, or
   a request that references >= 3 distinct closet_item/product
   attachments simultaneously.

action: route directly to Terra (pre-call decision — complexity is known
        from the request's own structure before any model call runs).
```

**Why this is knowable before the call.** Every signal above is derived from structured fields already present in the tool-call parameters or the context packet's `requested_task.attachments` — this is a lightweight rule evaluated in the Edge Function before constructing the `StylistCompletionRequest`, not a model judgment about the request's difficulty.

### 2.6 High-stakes calls — expensive product verdicts (routing)

```
condition: product.price >= 150 (absolute USD threshold)
        OR product.price >= 0.5 * user.budget_constraints.monthly_budget

action: route the analyze_product verdict call directly to Terra.
```

**Why $150 and 0.5×.** $150 is set as an absolute floor because a wrong verdict below that is a low-consequence mistake regardless of a given user's budget (a $40 shirt misjudged as "buy" instead of "consider" doesn't meaningfully harm anyone). The 0.5× monthly-budget rule catches the case where an absolute floor alone would miss real stakes for a lower-budget user — a $120 item is "high-stakes" for someone with an $180/month clothing budget even though it's under the $150 floor. **The exact numbers are a judgment call** — the owner's own example ("a 'buy' verdict on a $600 jacket") is comfortably inside this trigger at either the absolute or the relative threshold, which is the calibration check used to set them, but neither number is independently verified against real user budget distributions; tune against the routing-decision golden set (§7) once representative budget data exists.

### 2.7 Which VisionAnalysisProvider fields qualify for the confidence retry (§2.1 detail)

Not every field in `fieldsBelowConfidenceThreshold` should trigger a full Terra re-analysis — some fields (e.g., a slightly uncertain secondary color) are fine left low-confidence-and-editable per §12's "all inferred fields remain editable" design, and escalating for them would be pure cost. The fields that **do** qualify: `category`, `subcategory`, `material`, `condition` — the fields that most directly feed the Wardrobe Graph's scoring (`05-wardrobe-graph.md`) and where a wrong-but-confident value is more damaging than a correctly-flagged low-confidence one. `brandGuess` and secondary color fields do **not** trigger escalation on their own — they stay low-confidence-and-editable, consistent with §2.1's original design intent in `08` §2.1 ("a wrong high-confidence brand guess is worse than an honest low-confidence one... below the confidence threshold").

---

## 3. Anti-patterns

Escalating when it doesn't help is pure cost with no quality gain — the following are explicit **do-not-escalate** rules, not just omissions from §2.

1. **Do not escalate a well-formed cheap answer.** `mark_item_worn` confirmation flows, short yes/no follow-ups, and `general`/`education`-intent turns with no styling stakes stay on Luna even at moderate confidence — the cost of being slightly imprecise on "got it, marked worn" is near zero, and none of §2's triggers should fire for these in practice; if telemetry shows them firing anyway, that's a bug in the trigger logic, not evidence these call types need Terra.
2. **Do not escalate merely because `truncation_applied` (`06` §1.6) is non-empty.** Context-packet truncation is an information-*availability* problem — Terra cannot reason about closet items it was never given any more than Luna can. Escalating in response to truncation burns money without fixing the actual gap; the correct fix is retrieval tuning (`06` §1.3/§1.5) or budget reallocation, not a tier bump. `anti_pattern_guards.no_escalation_on_truncation_alone` (§8) enforces this as a config-level guard, not just a documented intention.
3. **Do not let escalation get "sticky" across turns.** A turn that escalated does not put the rest of the session into a Terra-default mode — every turn re-evaluates §2's triggers fresh from that turn's own signals. Carrying escalation state forward as a session flag would silently multiply cost for the remainder of a conversation over one hard question early in it. `anti_pattern_guards.escalation_sticky_across_turns` (§8) defaults to `false` and should stay that way absent a specific, measured reason to change it.
4. **Do not use category-level heuristics as a substitute for the actual per-request signal.** E.g., do not escalate every product evaluation in a category that's "usually expensive" (outerwear, tailoring) — gate strictly on the specific product's price (§2.6), not its category, since plenty of items in an expensive-leaning category are still inexpensive individual products.
5. **Escalation-loop guard.** A single logical request may escalate **at most twice** (Luna → Terra → Sol), enforced by a per-request escalation ledger the router maintains for the duration of one call, regardless of how many independent triggers in §2 fire simultaneously — a turn that matches three different escalation conditions still only moves up the tier ladder once per condition-class, capped at two total hops. After the cap is reached, any further failure falls through to the relevant safe-fallback path (`06` §6) rather than attempting a third tier or repeating an already-failed tier. This is what keeps a genuinely pathological request (e.g., a malformed context packet that fails validation at every tier) from becoming an unbounded cost sink instead of a fast, cheap failure.
6. **System-level circuit breaker on escalation rate.** Independent of the per-request cap above, the router tracks a rolling 5-minute escalation rate across all requests. If that rate exceeds roughly 3× the configured target rate for a call type (§8's `defaults`/target escalation rates), this is treated as a signal of a systemic issue — a bad prompt-version deploy, a provider-side quality regression, or a miscalibrated threshold — not something to silently keep paying for. It pages/alerts rather than continuing to escalate at the elevated rate unexamined; see §7's metrics table for the exact threshold and action.

---

## 4. Programmatic tool calling

**What it is, per the researched facts:** the Responses API supports the model writing and running lightweight programs that coordinate tool calls, rather than the Edge Function scripting every round-trip explicitly. Reported benefits: ~24% fewer output tokens and ~28% faster execution on tool-heavy tasks.

**Where it fits Kyra's 11-tool surface.** The benefit scales with how many tool round-trips a flow needs — a single-tool call (`get_weather` alone, `mark_item_worn` alone) has nothing to coordinate and gets no benefit. The flows that plausibly do:

- **"What should I wear tonight/tomorrow"** → `get_weather` → `get_schedule` → `search_closet` → `rank_outfits` (and often `create_outfit` for the winning candidate) — a 4–5-tool chain, the single most common Kyra flow shape.
- **Packing list generation** → repeated `search_closet` calls per day/dress-code combination, feeding into `create_packing_list` — a naturally multi-round-trip flow that scales with trip length.
- **Product comparison / shopping decisions** → `search_products` and/or `analyze_product` called multiple times across candidates the user is weighing, sometimes combined with a `search_closet` call to check redundancy against owned items.

**Recommendation: adopt it, but scoped to the read-only, non-consequential tool chains only.**

- **Adopt for:** `get_weather`, `get_schedule`, `search_closet`, `rank_outfits`, `search_products`, `analyze_product` — all read-only or low-stakes-mutating per `06`'s own tool table (§3), where a coordination bug produces a slightly worse recommendation, not a data-integrity or consent problem.
- **Do not extend to:** `generate_studio_preview` and `mark_item_worn` — both are `requires_confirmation: true` per `06` §3's tool table specifically because they have real consequences (quota spend, real wear-history writes). A model-authored program autonomously deciding when to call these would bypass the confirmation-gate design that `06` §3.2 and `08`'s guardrail posture depend on. **This is a hard boundary, not a trust assumption**: Astra's tool-execution layer must intercept these two tool names at the execution layer and force the existing confirmation flow regardless of what the model's program does internally — the program can *propose* calling them, but the Edge Function's dispatcher, not the model's program, is what actually gates execution on a confirmed user turn.

**Costs, named honestly:**

- **Debuggability.** A model-authored program is harder to trace step-by-step than an explicit sequence of `tool_calls` entries in a response stream — when something goes wrong mid-chain, the failure surface is "somewhere inside the program" rather than "this specific tool_call at this specific step." Structured logging of each individual tool invocation the program makes (not just the program's final result) is a prerequisite for shipping this, not an optional nicety — without it, `06` §7.3's "tool-call precision/recall vs. golden set" metric becomes much harder to compute per-step.
- **Error handling.** If a program-internal step fails (e.g., `search_closet` returns `EMPTY_CLOSET`), the model's own in-program logic decides how to recover — Astra's Edge Function has less direct control over that recovery path than it does over the developer-orchestrated retry semantics in `08` §0.1. Test this explicitly against the golden set's failure-mode fixtures (`06` §7.1's empty-wardrobe, tool-failure cases) before defaulting programmatic tool calling on, not just against the happy path.

**Rollout:** pilot behind a feature flag on the six read-only tool names above, compare token count, latency, and tool-call precision/recall (`06` §7.3) against the current developer-orchestrated baseline on the golden set (`06` §7.1), and only default it on for production traffic once that comparison is favorable — this is exactly the kind of change the offline eval harness in §7 exists to gate.

---

## 5. Cost model

All arithmetic below uses the researched GPT-5.6 pricing table and the token budgets already specified in `06-kyra-orchestration.md` §1.2 and `08-provider-abstraction.md` §1.1. Every number is shown as a computation, not just a result, so it can be checked and re-derived if an assumption changes.

### 5.1 Token-budget inputs (from `06` and `08`, not re-derived here)

| Component | Tokens | Source |
|---|---|---|
| System prompt | 1,200 | `08` §1.1 |
| Tool schemas (all 11) | 1,500 | `08` §1.1 |
| Context packet (full cap) | 4,000 | `06` §1.2 |
| — of which `style_profile` + `body_fit_profile` | 450 | `06` §1.2 (300 + 150) |
| Trailing thread history (cap) | 3,000 | `08` §1.1 |

### 5.2 Two scenarios, to bound the estimate honestly

Using the full documented caps for every turn (a **ceiling**, unlikely to reflect steady-state reality since most turns don't need the maximum retrieved closet-item count or the maximum trailing-history window) versus a **realistic average** that assumes partial utilization of each cap. Both are shown so the realistic figure used for the monthly roll-up (§5.4) can be sanity-checked against the upper bound.

**Ceiling, per Kyra turn (Luna, with caching):** cacheable prefix = system + tools + durable profile = 1,200 + 1,500 + 450 = 3,150 tokens. Everything else at full cap: (4,000 − 450) + 3,000 = 6,550 non-cached input tokens. Output assumed 600 tokens (message + multiple cards + tool-call args).

```
cached:     3,150 × $0.10 / 1,000,000 = $0.000315
non-cached: 6,550 × $1.00 / 1,000,000 = $0.006550
output:       600 × $6.00 / 1,000,000 = $0.003600
                                total  = $0.010465  (≈ $0.0105)
```

**Realistic average, per Kyra turn (Luna, with caching):** assumes the context packet is typically used at roughly 45% of its cap outside the always-included durable-profile section (~1,800 of the remaining 3,550-token budget) and trailing history at roughly 13% of its cap (~400 tokens) — most turns are shorter exchanges about a specific, already-narrowed ask, not maximal closet dumps with long back-and-forth. Non-cached input ≈ 1,800 + 400 = 2,200 tokens; output assumed 700 tokens (a bit higher than the ceiling-scenario mid-estimate to account for tool-call argument tokens on multi-tool turns).

```
cached:     3,150 × $0.10 / 1,000,000 = $0.000315
non-cached: 2,200 × $1.00 / 1,000,000 = $0.002200
output:       700 × $6.00 / 1,000,000 = $0.004200
                                total  = $0.006715  (≈ $0.0067)
```

Both scenarios use the **same cacheable prefix** (3,150 tokens) — the difference between them is entirely in the volatile suffix, which is exactly the part prompt caching (§6) cannot help with. The realistic-average figure ($0.0067) is used for §5.4's monthly roll-up; the ceiling figure ($0.0105) confirms the roll-up isn't understating cost by an order of magnitude.

**Same realistic-average turn, at Terra:**

```
cached:     3,150 × $0.25 / 1,000,000 = $0.0007875
non-cached: 2,200 × $2.50 / 1,000,000 = $0.0055000
output:       700 × $15.00 / 1,000,000 = $0.0105000
                                 total  = $0.0167875  (≈ $0.0168)
```

**Without caching at all (for comparison — the "why caching matters" number):** total input 5,350 tokens.

```
Luna, no caching: 5,350 × $1.00/1M = $0.00535 (input) + $0.0042 (output) = $0.00955
Terra, no caching: 5,350 × $2.50/1M = $0.013375 (input) + $0.0105 (output) = $0.023875
```

Caching cuts the realistic-average Luna turn from $0.00955 to $0.0067 (≈30% reduction) and the Terra turn from $0.023875 to $0.0168 (≈30% reduction) — the reduction is capped at roughly (cached-prefix-share × 90%) rather than the full 90% headline discount, because only the 3,150-token prefix qualifies for the cache discount; the volatile suffix never does, by construction (§6).

### 5.3 Per-call-type cost, all ten call types

Using the same method as §5.2 (stated assumptions per call type, shown as arithmetic). Where a call type's tokens weren't already fixed by `06`/`08`, the assumption is stated explicitly and flagged as a modeling input to revisit once production telemetry exists (§7).

| Call type | Luna cost/call | Terra cost/call | Key assumption |
|---|---|---|---|
| Daily Brief | $0.0050 | $0.0123 | Same cacheable 3,150 prefix; volatile ≈2,200 (today's weather/occasions/closet subset, no trailing history since it's single-shot); output ≈400 |
| Kyra conversational turn | $0.0067 | $0.0168 | §5.2 realistic average |
| Product verdict (`analyze_product`) | $0.0042 | $0.0106 | Cached instructions 400; volatile (product attrs + closet subset) 1,800; output 400 |
| Garment classification (first pass) | $0.0036 | — | Cached taxonomy prompt 600; image ≈1,600 (1024px cropped, not cacheable — unique per photo); device hints text 100; output 300. **Image-token estimate is a judgment call** — GPT-5.6's per-image tokenization at this resolution was not part of the verified facts; 1,600 tokens is a reasonable planning estimate for a cropped/compressed garment photo consistent with `08` §2.3's 1024px ceiling, to be corrected against actual billed usage once live. |
| Low-confidence re-analysis (Terra retry) | — | $0.0089 | Same token shape as garment classification, at Terra rates |
| Style DNA generation | — | $0.0171 | Cached instructions 500; onboarding-answers input 2,000; output 800 (structured identity + narrative) |
| Packing list | $0.0091 | $0.0227 | Cached 450 (profile only, no tool schemas needed beyond `create_packing_list`); volatile (trip dates/dress codes/multi-day closet retrieval/weather) 3,050; output 1,000 (list + daily plan + missing essentials) |
| Monthly review | — | $0.0257 | Cached 450; volatile (aggregated month of wear/feedback stats) 3,050; output 1,200 (narrative + recommendations) |
| Product URL extraction | $0.0042 | $0.0106 | Cached schema instructions 300; cleaned page content 3,000 (unique per page, not cacheable); output 200 |
| Outfit ranking explanations | — (embedded) | — | Cost already inside rows 1–2 (§1's note) |

### 5.4 Monthly cost for a realistic engaged Premium subscriber

**Stated usage assumptions** (engaged, not power-user or minimal-user — the middle of the expected Premium distribution):

| Call type | Volume/month | Escalation model | Escalation rate |
|---|---|---|---|
| Daily Brief | 30 (1/day) | Routing (substitutive) | 5% |
| Kyra conversational turns | 150 (5/day) | Blended — modeled as substitutive for simplicity (flagged below) | 15% |
| Garment classification | 15 (steady-state scanning) | Retry (additive) | 7.5% (midpoint of the researched 5–10%) |
| Product verdicts | 10 | Routing (substitutive) | 25% |
| Product URL extraction | 6 (subset of product evaluations reached via pasted link) | Retry (additive, rare) | 2% |
| Style DNA | 1 one-time event, amortized over a 12-month assumed customer lifetime | Terra always | n/a |
| Packing list | 1 | Routing (substitutive) | 20% |
| Monthly review | 1 | Terra always | n/a |

**Modeling simplification, stated explicitly:** conversational-turn escalation is a mix of retry-triggers (§2.1–2.3, additive) and routing-triggers (§2.4–2.6, substitutive). Modeling it as purely substitutive at a blended 15% rate slightly *understates* true cost for the retry-driven subset. This is an acceptable planning approximation, not a claim of precision — once in production, actual per-call billing metadata (tagged by trigger type) replaces this estimate entirely, per §7.

**Arithmetic:**

```
Daily Brief:        0.95 × $0.0050 + 0.05 × $0.0123 = $0.005365/call ×30 = $0.1610
Kyra turns:          0.85 × $0.0067 + 0.15 × $0.0168 = $0.008226/call ×150 = $1.2339
Garment classify:    $0.0036 + 0.075 × $0.0089 (additive retry) = $0.004228/call ×15 = $0.0634
Product verdicts:    0.75 × $0.0042 + 0.25 × $0.0106 = $0.00583/call ×10 = $0.0583
URL extraction:      $0.0042 + 0.02 × $0.0106 (additive retry) = $0.004412/call ×6 = $0.0265
Style DNA:           $0.0171 / 12 months (amortized)                              = $0.0014
Packing list:        0.80 × $0.0091 + 0.20 × $0.0227 = $0.01182/call ×1           = $0.0118
Monthly review:      $0.0257 ×1                                                    = $0.0257
Embeddings:          negligible (see §5.5)                                         ≈ $0.0001
─────────────────────────────────────────────────────────────────────────────────────────
TOTAL                                                                          ≈ $1.583/month
```

### 5.5 Embedding cost (for completeness — it does not move the total)

`text-embedding-3-small` at $0.02/1M tokens: 150 Kyra-turn query embeddings (~20 tokens each) + 15 item embeddings (~40 tokens each, on scan) ≈ 3,600 tokens/month × $0.02/1M = **$0.000072/month**. This is genuinely a rounding error next to the $1.58 reasoning-provider total — batching (§4.3 of `08`) is worth doing for rate-limit headroom, not cost.

### 5.6 Comparison against the $12.99/month price point

Net revenue after Apple's platform cut (per this task's stated figures — 30% standard rate, 15% reduced rate for Small Business Program participants or year-2+ subscribers):

```
Monthly plan ($12.99):  net @30% cut = $12.99 × 0.70 = $9.093/month
                        net @15% cut = $12.99 × 0.85 = $11.0415/month

Annual plan ($79.99/yr = $6.6658/month-equivalent):
                        net @30% cut = $6.6658 × 0.70 = $4.6660/month-equivalent
                        net @15% cut = $6.6658 × 0.85 = $5.6659/month-equivalent
```

Reasoning-provider cost ($1.583/month, from §5.4) as a share of net revenue:

| Plan | Apple cut | Net revenue/mo | Inference cost / net revenue |
|---|---|---|---|
| Monthly | 30% | $9.093 | **17.4%** |
| Monthly | 15% | $11.042 | **14.3%** |
| Annual | 30% | $4.666 | **33.9%** |
| Annual | 15% | $5.666 | **27.9%** |

**This is the clearest finding in this document, and it complicates the plan as stated:** at baseline, non-escalated-beyond-design-target usage, reasoning-provider inference cost alone (excluding Style Studio image generation, infra, support, and payment processing — all real additional COGS lines) already consumes **28–34% of net revenue on the annual plan**, versus a comfortable 14–17% on the monthly plan. The escalation router's tier-selection policy has essentially no ability to fix this on its own — even at **zero** Terra escalation across every call type (all-Luna, the cheapest the current design can be), the total only drops to roughly $1.36/month (§5.7's sensitivity floor), which is still ~29% of net annual-plan revenue at the 30% Apple cut. This is a pricing/plan-structure question, not a routing-policy question, and is flagged here because it surfaced directly from this arithmetic — see the "conditions to revisit" note below.

### 5.7 Sensitivity: escalation rate vs. margin, and where it becomes uncomfortable

Holding every other assumption in §5.4 fixed and varying only the Kyra-turn escalation rate `X` (the single largest and most policy-controllable cost lever, since Kyra turns are 78% of the baseline total):

```
Kyra-turn cost(X) = 150 × [(1−X) × $0.0067 + X × $0.0168]
                  = 150 × [$0.0067 + X × $0.0101]
                  = $1.005 + $1.515·X

Other call types (fixed, from §5.4, excluding Kyra turns):
  $0.1610 + $0.0634 + $0.0583 + $0.0265 + $0.0014 + $0.0118 + $0.0257 + $0.0001 = $0.3482

Total(X) = $0.3482 + $1.005 + $1.515·X = $1.3532 + $1.515·X
```

(Check: at X = 0.15, Total = $1.3532 + $0.2273 = $1.5805 ≈ the $1.583 computed directly in §5.4, small difference from rounding — consistent.)

**Defining "uncomfortable."** No spec section sets an inference-cost-as-%-of-revenue target — this is this document's own judgment call: **20% of net revenue spent on reasoning-provider inference alone** is used as the discomfort line, leaving headroom for Style Studio generation cost (per `08` §3.3, "the most expensive provider per call by a wide margin" — not included in this total at all), Supabase infra, App Store/payment overhead, and support cost, plus actual margin. A reader who disagrees with 20% can resolve `X` at their own preferred threshold using the formula above directly.

| Scenario | Net revenue/mo | 20%-of-net threshold | Solve for X | Interpretation |
|---|---|---|---|---|
| Monthly, 30% Apple cut | $9.093 | $1.8186 | `X = ($1.8186 − $1.3532) / $1.515 ≈ 0.307` | **≈31% Kyra-turn escalation rate** is the headline "margin gets uncomfortable" number for the flagship $12.99 monthly price point |
| Monthly, 15% Apple cut | $11.042 | $2.2083 | `X ≈ 0.564` | ≈56% — comfortably above any planned escalation rate (§8's launch defaults) |
| Annual, 30% Apple cut | $4.666 | $0.9332 | `X` — already exceeded at **X = 0** | The 20% line is crossed even with zero escalation; escalation policy cannot fix this scenario, only pricing or usage-volume assumptions can |
| Annual, 15% Apple cut | $5.666 | $1.1332 | `X` — already exceeded at **X = 0** | Same conclusion as above |

**Headline number:** at the monthly-plan, 30%-Apple-cut scenario (the conservative, standard-rate case for the named $12.99 price point), reasoning-provider inference cost crosses this document's own 20%-of-net-revenue discomfort line at approximately **31% Kyra-turn escalation rate** — well above the ~15% design target in §5.4, meaning there's real headroom before the router's tuning becomes a margin problem on the monthly plan specifically. The annual plan does not have that headroom at all under the stated usage assumptions, independent of escalation policy.

---

## 6. Prompt caching strategy

This is where most of the savings in §5 come from, and getting the structure wrong silently forfeits them without any error or warning — a broken cache doesn't fail, it just quietly charges full price.

### 6.1 Structure: three tiers, strict order, nothing dynamic before the volatile tier

```
┌─────────────────────────────────────────────────────────────────┐
│ TIER 1 — globally static (identical across every user, every    │
│ turn, for a given deployed prompt version)                       │
│   • System prompt (06 §2), pulled verbatim from the versioned    │
│     prompt table — no runtime string interpolation of anything   │
│     user-specific inside it                                      │
│   • All 11 tool schemas (06 §3), generated once per prompt-      │
│     version deploy as a static asset, not regenerated per-request│
│   ≈ 2,700 tokens                                                 │
├─────────────────────────────────────────────────────────────────┤
│ TIER 2 — per-user static (identical across one user's turns      │
│ until they edit their profile)                                   │
│   • style_profile + body_fit_profile (06 §1.6)                   │
│   ≈ 450 tokens                                                   │
│   → Tier 1 + Tier 2 = 3,150 tokens, the cacheable prefix used    │
│     throughout §5's arithmetic                                   │
├─────────────────────────────────────────────────────────────────┤
│ TIER 3 — volatile, rebuilt every turn, placed last               │
│   • weather, occasions, closet_items (retrieved per-turn),       │
│     recent_feedback, budget_constraints, durable_memories        │
│     (top-K per-turn), requested_task                             │
│   • the bounded trailing-history window (06 §1.2's ≤3,000-token  │
│     cap — a sliding window, not a strictly append-only prefix,   │
│     so it does not itself stay cache-stable turn to turn)        │
│   • the new user message                                         │
└─────────────────────────────────────────────────────────────────┘
```

**Ordering constraint:** Tier 1 → Tier 2 → Tier 3, strictly, on every single call, with nothing dynamic appearing anywhere before the start of Tier 3. Prefix caching works by exact byte-for-byte prefix match up to the point of divergence — a single differing token anywhere in Tiers 1–2 invalidates the cache benefit for everything after that point, not just for the differing token itself.

**Assumption flagged:** the exact cache-hit window (how long a prefix stays cached after last use) and minimum-matched-prefix-length behavior of GPT-5.6's Responses API caching were not part of the verified facts for this task. The design above assumes a cache window on the order of minutes (long enough to cover an active back-and-forth conversation, short enough that Tier 2's per-user benefit is realized mostly *within* a session rather than *across* days) and a minimum matched-prefix length comfortably below the ~3,150-token Tier 1+2 block. **Confirm both against OpenAI's GPT-5.6 API documentation before finalizing the Edge Function implementation** — if the actual cache window is materially shorter than assumed, sparse/infrequent users get less of the caching benefit than §5's arithmetic assumes, and the realistic monthly-cost estimate in §5.4 becomes a lower bound rather than a central estimate.

### 6.2 What would accidentally break caching (concrete anti-patterns)

- **Embedding `requestId` or a timestamp anywhere in Tier 1 or Tier 2.** Tempting for tracing, but it must live in an out-of-band field (a request header, a `ProviderRequestContext` field per `08` §0's envelope) — never string-concatenated into the prompt text itself.
- **Non-deterministic JSON key ordering when serializing `style_profile`/`body_fit_profile` into Tier 2.** Use a fixed field order (a hand-written serializer or an explicit key list), not `JSON.stringify` on an object literal whose key-insertion order could vary across code paths — two functionally-identical objects serialized in different key orders are byte-different and break the match.
- **Per-request prompt A/B testing via call-time randomization.** Randomly interleaving two system-prompt variants call-to-call defeats caching for *both* variants, since neither gets a stable, repeated prefix. A/B tests must use sticky per-user variant assignment (the same user gets the same variant for the duration of the test), not per-call randomization — and this is also required for the quality-feedback loop in §7 to attribute outcomes to a variant correctly in the first place.
- **Reordering the 11 tool definitions per call** (e.g., "put the most relevant tool first for this intent" as a cleverness to help the model). This directly breaks the Tier 1 cached prefix. If tool-relevance signaling is wanted, express it via a field *within* each tool's schema (e.g., a priority hint) rather than by physically reordering the array.
- **Unnecessary prompt-version churn.** Every version bump changes Tier 1's content, which means a full cache miss on the first call after each deploy for every affected user — bump the version when content actually changes, not reflexively.

---

## 7. Quality measurement

The owner asked explicitly for "an engine to determine result quality" — this section specifies it as four connected pieces: an offline eval harness, an online behavioral signal, a routing-decision feedback loop, and the guardrail tie-in. None of these are one-time checks; together they're what lets the routing policy in §1–2 get *tuned from data* rather than guessed once and left alone.

### 7.1 Offline eval harness (extends `06` §7.1)

Augment `kyra_eval_golden.jsonl` with routing-specific fields on each golden case:

```json
{
  "id": "golden_042",
  "...": "... existing fields per 06 §7.1 ...",
  "expected_tier": "luna | terra",
  "expected_escalation_trigger": "none | confidence | schema_failure | tool_loop | rejection_retry | complexity | high_stakes_price | null"
}
```

New metric: **routing-decision accuracy** = % of golden cases where the router's actual tier choice matches `expected_tier`. Golden cases must cover, at minimum: one clearly-Luna case per call type in §1's table, one clearly-Terra (routing-trigger) case for each of §2.4–2.6, and one retry-trigger case for each of §2.1–2.3 (a fixture engineered to produce a low-confidence/invalid-schema/loop-prone first attempt). This runs on every prompt-version bump *and* every router-config change (§8), gated the same way `06` §7.2's guardrail suite gates a prompt deploy.

**Guardrail tie-in:** the guardrail regression suite (`06` §7.2, 100%-pass-bar) must run against **both** Luna and Terra outputs, not just whichever tier a given eval fixture happens to route to by default — a routing bug that sends a guardrail-relevant request (body-shaming bait, medical-advice bait) to the "wrong" tier should never be how a guardrail regression is first discovered in production.

### 7.2 Online quality signal (from `00-master-spec.md` §18's analytics events)

Every relevant analytics event is tagged with the `modelIdentifier`/tier that produced the response it relates to (already required to be stored per `08` §1's `StylistCompletionResult.modelIdentifier`), enabling tier-segmented behavioral analysis:

| Signal | Event(s) | What it measures per tier |
|---|---|---|
| Outfit acceptance | `outfit_marked_worn` vs. `outfit_rejected` | Direct behavioral quality proxy for `daily_outfit`/`outfit_review` responses — a recommendation the user actually wore is a strong positive signal regardless of the response's self-reported confidence |
| Daily Brief acceptance rate | (north-star metric, §18) | The single most important tier-segmented number for call type #1 — Daily Brief is the highest-volume call type and the one most sensitive to a Luna-vs-Terra quality gap being invisible in aggregate but visible per-tier |
| `confidence` calibration | `06` §7.3's existing metric, sliced by tier | Confirms self-reported confidence is actually predictive *per tier* — the §2.1 confidence-based retry trigger's entire premise depends on this being true for Luna specifically |
| Verdict outcome correlation | `product_evaluated` → later save/purchase vs. skip, sliced by tier | Tier-specific version of `06` §7.3's existing "verdict-to-outcome correlation" metric — isolates whether Terra's higher-stakes verdicts are actually more accurate, not just more expensive |
| Correction rate | `scan_corrected`, sliced by tier (Luna-only scans vs. scans that hit the Terra low-confidence retry) | Measures whether the retry path (§1's call type #5) is actually reducing user corrections relative to Luna alone — this is the entire justification for that retry existing, and it's directly falsifiable |

### 7.3 Routing-decision feedback loop

A recurring (weekly, at minimum) batch job:

1. **Bucket** each call type by request shape — e.g., product verdicts by price band, packing lists by dress-code count, Kyra turns by `intent`.
2. **Compare** the §7.2 behavioral proxy (worn-rate, acceptance-rate, correction-rate) between Luna-served and Terra-served requests within each bucket, restricted to buckets with sufficient sample size on *both* tiers (minimum 500 requests per arm, to avoid over-reacting to noise).
3. **The comparison-group problem:** if escalation is purely trigger-driven, "requests that escalated" are systematically different (harder, by construction) from "requests that didn't," which confounds any quality comparison. To get a clean comparison, a small **random escalation holdout** — `random_holdout_sample_rate` (§8), launch default 2–3% — randomly escalates a slice of Luna-default calls to Terra *regardless of whether any §2 trigger fired*, purely to generate an unconfounded Luna-vs-Terra comparison for buckets that otherwise rarely escalate.
4. **Surface a recommendation, not an automatic change:** a bucket where Terra's behavioral-proxy delta exceeds a defined threshold (§7.4) is flagged as a candidate for either widening that bucket's escalation trigger or moving its default tier. A bucket showing no meaningful delta despite a non-trivial escalation rate is flagged as a candidate for *tightening* the trigger (a direct cost-saving finding). Both are surfaced to whoever owns the routing config (§8) for a human decision — not auto-applied, since real subscription-economics stakes (§5.6–5.7) mean this should have a person in the loop, not a fully automated policy that could drift the cost model without anyone noticing until the monthly bill does.

### 7.4 Metrics, thresholds, and actions

| Metric | Threshold | Action |
|---|---|---|
| Routing-decision accuracy vs. golden set (§7.1) | < 90% | Block deploy of the prompt-version or router-config change; investigate before proceeding |
| Guardrail suite pass rate, either tier | < 100% | Block deploy — same gate as `06` §7.2, applied per-tier |
| Hallucinated-closet-item rate (`06` §7.3), sliced by tier | any non-zero rate | P1 regardless of tier — routing/tier choice is never an acceptable explanation for this failure mode |
| Escalation rate for a call type, sustained | > 3× or < 0.3× its configured target (§8) for 7 consecutive days | Alert for review — either the trigger threshold is miscalibrated or there's an underlying quality regression worth investigating before assuming it's just noise |
| Terra-vs-Luna behavioral delta for a bucket (§7.3) | < 2 percentage points, ≥500 samples/arm | Candidate for tightening that bucket's escalation trigger (cost-saving) |
| Terra-vs-Luna behavioral delta for a bucket (§7.3) | > 8 percentage points, ≥500 samples/arm | Candidate for widening that bucket's escalation trigger or moving its default tier |
| `confidence` calibration in the 0.4–0.6 "escalation zone," sliced by tier (§7.2) | calibration curve deviates > 15% from the diagonal in that zone | Recalibrate or replace the §2.1 confidence threshold — miscalibration exactly where the trigger fires directly breaks the trigger's precision |
| System-level escalation-rate circuit breaker (§3, item 6) | rolling 5-minute rate > 3× configured target, any call type | Page on-call; treat as a possible bad-deploy or provider-quality-regression signal, not routine variance |

---

## 8. Configuration

Per the same principle that governs the compatibility weights in `00-master-spec.md` §10 (see `docs/adr/0003-relational-wardrobe-graph.md`) and CLAUDE.md's explicit rule ("Don't change the compatibility scoring weights in code... it's a server-side config change, not a client or Edge Function code change with a new hardcoded constant") — **every threshold in this document is server-configurable, not compiled into the app or hardcoded in an Edge Function.** It lives in an admin-editable table (`00-master-spec.md` §28's "prompt versions" / "feature flags" surface is the natural home for this alongside them), loaded into Edge Functions with a short in-memory cache (TTL on the order of 60s, matching the pattern already used for prompt versions and compatibility weights) so a threshold change takes effect without a redeploy but doesn't cost a database round-trip on every single call.

```typescript
// core/routing/config.ts — shape of the admin-editable model_routing_config row.
// Loaded server-side only; never shipped to or readable by the iOS client.

type ModelTier = "luna" | "terra" | "sol";

type CallType =
  | "daily_brief" | "kyra_turn" | "product_verdict" | "garment_classification"
  | "garment_reanalysis" | "style_dna" | "packing_list" | "monthly_review"
  | "product_url_extraction";

interface ModelRoutingConfig {
  version: string;           // bumped on every change; stored on every routed call's
                              // log line so a routing-policy regression is traceable
                              // to the exact config version active when it happened
  updated_at: string;

  defaults: Record<CallType, ModelTier>;

  escalation_triggers: {
    confidence_retry_threshold: number;          // §2.1 — launch default 0.55
    tool_call_loop_max_iterations_luna: number;   // §2.3 — launch default 4
    tool_call_loop_max_iterations_terra: number;  // §2.3 — launch default 6
    rejection_retry_enabled: boolean;             // §2.4 — launch default true
    complexity: {
      min_dress_codes: number;                    // §2.5 — launch default 2
      min_trip_days_with_luggage_constraint: number; // §2.5 — launch default 4
      min_constraint_dimensions_kyra_turn: number;   // §2.5 — launch default 2
    };
    high_stakes_product: {
      absolute_price_usd: number;                 // §2.6 — launch default 150
      budget_fraction: number;                     // §2.6 — launch default 0.5
    };
    vision_escalation_fields: string[];            // §2.7 — launch default
      // ["category", "subcategory", "material", "condition"]
    double_escalation_ceiling_tier: ModelTier;      // launch default "sol"
    max_escalations_per_request: number;            // §3 item 5 — launch default 2, hard cap
  };

  random_holdout_sample_rate: number;   // §7.3 — launch default 0.025 (2.5%)

  anti_pattern_guards: {
    no_escalation_on_truncation_alone: boolean;    // §3 item 2 — must be true
    escalation_sticky_across_turns: boolean;        // §3 item 3 — must be false
  };

  circuit_breaker: {
    target_escalation_rate: Record<CallType, number>;  // e.g. kyra_turn: 0.15
    alert_multiplier: number;                           // §3 item 6 — launch default 3.0
    rolling_window_minutes: number;                      // launch default 5
  };
}
```

**Launch defaults** (matching §1's routing policy and §2's trigger thresholds throughout this document):

```json
{
  "version": "1.0.0",
  "defaults": {
    "daily_brief": "luna",
    "kyra_turn": "luna",
    "product_verdict": "luna",
    "garment_classification": "luna",
    "garment_reanalysis": "terra",
    "style_dna": "terra",
    "packing_list": "luna",
    "monthly_review": "terra",
    "product_url_extraction": "luna"
  },
  "escalation_triggers": {
    "confidence_retry_threshold": 0.55,
    "tool_call_loop_max_iterations_luna": 4,
    "tool_call_loop_max_iterations_terra": 6,
    "rejection_retry_enabled": true,
    "complexity": {
      "min_dress_codes": 2,
      "min_trip_days_with_luggage_constraint": 4,
      "min_constraint_dimensions_kyra_turn": 2
    },
    "high_stakes_product": { "absolute_price_usd": 150, "budget_fraction": 0.5 },
    "vision_escalation_fields": ["category", "subcategory", "material", "condition"],
    "double_escalation_ceiling_tier": "sol",
    "max_escalations_per_request": 2
  },
  "random_holdout_sample_rate": 0.025,
  "anti_pattern_guards": {
    "no_escalation_on_truncation_alone": true,
    "escalation_sticky_across_turns": false
  },
  "circuit_breaker": {
    "target_escalation_rate": {
      "daily_brief": 0.05, "kyra_turn": 0.15, "product_verdict": 0.25,
      "garment_classification": 0.075, "packing_list": 0.20
    },
    "alert_multiplier": 3.0,
    "rolling_window_minutes": 5
  }
}
```

Every numeric default above is a **launch estimate**, explicitly flagged throughout §2 and §5 as a judgment call where the underlying research didn't settle it precisely — the config shape exists specifically so §7's feedback loop can move these numbers based on real production data without a client release or an Edge Function redeploy, which is the entire point of treating this as configuration rather than code.
