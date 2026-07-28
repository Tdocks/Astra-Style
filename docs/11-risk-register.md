# 11. Risk Register

This is a working document, not a compliance artifact. Each risk below is written
to be actionable: what it is, how likely and how damaging, what early signal would
tell us it's happening, what we do about it, and which build phase (§24 of
`docs/00-master-spec.md`: Phase 1 Foundation → Phase 7 Monetization and Hardening)
owns addressing it. Likelihood/Impact are High/Medium/Low, assessed against the
pre-launch build, not a mature-product baseline.

Risks are grouped; within each group, most-dangerous first. Read the **Cost risk**
and **Product risk** entries first — they are the two most likely to actually kill
this project, for different reasons (one is slow and quiet, one is a spreadsheet
problem that becomes real the day usage grows).

---

## 1. Product risk — outfit recommendations that are merely plausible, not genuinely good

**Description.** The entire product promise (§1: "Kyra will tell you what to wear,
why it works, and what you should buy next") rests on Kyra's picks actually being
good — not just syntactically valid (weather-appropriate, not-two-shirts) but
genuinely well-styled in a way a discerning man would agree with. A recommendation
engine can pass every unit test in §22 (compatibility score computed correctly,
JSON parses, no crash) while producing outfits that are technically coherent and
stylistically boring, off, or generic. This is the single most dangerous failure
mode because **it produces no error, no crash, and no support ticket** — a user who
finds Kyra's picks mediocre simply stops opening the app. The app dies quietly.

- **Likelihood:** H — "plausible but uninspired" is the default output of a
  weighted-scoring system (§10) tuned only against synthetic/internal test cases,
  before real user taste data exists.
- **Impact:** H — this is not a bug to fix later; if the core loop isn't good, no
  amount of polish elsewhere saves retention.
- **Leading indicator:** Watch **Daily Brief acceptance rate** (§18 north-star
  metric — "Wear This" / accept vs. "Alternatives" / reject) from day one, segmented
  by user tenure. A flat or declining acceptance rate over a user's first 2–3 weeks,
  even while raw usage (opens) holds steady, is the earliest quiet signal — it means
  users are still opening the app out of habit but no longer trusting Kyra's first
  pick. Also watch: rate of "explain" taps followed immediately by a swap (user
  wants a reason before rejecting, a sign the pick didn't earn trust) and unprompted
  qualitative feedback in App Store reviews mentioning "boring," "same," or "doesn't
  get my style."
- **Mitigation.** Before broad launch, run a structured taste-eval: have real
  stylists (not just engineers) rate a sample of generated outfits against the
  target style identities (§6.5) blind, and treat "does a person with actual taste
  agree" as a release gate, not a nice-to-have. Instrument compatibility-score
  distribution against actual user accept/reject signal (§9 `style_feedback`) from
  week one and retrain/retune weights (§10, server-configurable) against real
  behavior, not synthetic assumptions. Weight the "historical co-wear/feedback"
  (§10, 10%) component up over time as real signal accumulates — it is the only
  component grounded in what this specific user actually likes, versus the other
  90% being generic rules. Ship a fast, low-friction feedback loop (thumbs up/down
  per outfit, not just accept/swap) so the signal exists to detect this early rather
  than inferring it from silence.
- **Owner-phase:** Phase 4 (Outfit intelligence) for the scoring/feedback loop
  infrastructure; ongoing from Phase 4 through Phase 7 as a standing metric, not a
  one-time gate.

---

## 2. Cold-start risk — the app is useless until ~15 garments are scanned

**Description.** Outfit generation, the Wardrobe Graph, and the Daily Brief are all
meaningless against an empty or near-empty closet. §6.11's empty state ("Add five
pieces and Kyra can begin building real outfits") acknowledges a minimum, but real
usefulness — enough variety for 3 distinct ranked outfits, meaningful redundancy
detection, a credible Wardrobe Score — realistically needs closer to 15–20 items.
Scanning 15 garments one at a time (§6.3: capture front, optional back/label/detail,
review, correct) is real friction — plausibly 15–30 minutes of deliberate effort
before the product delivers its core value once.

- **Likelihood:** H — this is a structural property of the product, not an edge
  case; every new user hits it.
- **Impact:** H — this is the most likely point of first-session abandonment, before
  the product has had any chance to prove itself.
- **Leading indicator:** Funnel drop-off between "onboarding completed" and
  "10th closet item added" (§18 lists "closet_item_added" and "closet items added
  per activated user" as tracked events/metrics already — the specific signal to
  watch is the item-count histogram at session 1 end, not just the aggregate mean).
  A bimodal distribution (many users at 0–2 items, a smaller group who push through
  to 15+) indicates the friction is real and most users aren't crossing it.
- **Mitigation.** Make batch scanning (§6.16 "Batch closet scan," listed in §23 as
  "can follow shortly after," not MVP) a higher build priority than its current
  placement suggests if early data shows single-item scanning is the drop-off
  cause — this is a case where the spec's phasing should be revisited against real
  funnel data, not treated as fixed. Let Kyra generate a partial, honestly-labeled
  outfit from as few as 3–5 items rather than gating all value behind 15 (deliver
  *some* value early, escalate quality as the closet grows, rather than an
  all-or-nothing threshold). Consider photo-import from camera roll (PhotosUI, §8)
  for users with existing product photos/receipts rather than requiring a fresh
  physical photo of every item. Track and directly optimize "time to first Daily
  Brief a user actually likes," not just "time to N items," since the real goal is
  perceived value, not a scan count.
- **Owner-phase:** Phase 3 (Closet) for batch scanning and partial-closet outfit
  generation; Phase 2 (Identity/onboarding) for whether onboarding nudges users to
  scan enough before first exit.

---

## 3. Computer-vision accuracy risk — classification, OCR, and background removal will be wrong often

**Description.** §12's pipeline (device-side blur/segmentation/OCR/color, then
server-side category/material/brand/condition classification) will misclassify
category, guess the wrong brand from label OCR, and produce visibly bad background
removal (stray shadows, cut-off sleeves, wrong crop) at a real, non-trivial rate —
this is true of every production CV pipeline, not a sign of a bad build. §12
correctly anticipates this ("all inferred fields remain editable," "low-confidence
fields should be visibly marked") but that correction UX is load-bearing
infrastructure, not a nicety: if correction is tedious or confusing, users either
give up mid-scan (compounding cold-start risk above) or leave wrong data in the
system, which then silently corrupts every downstream recommendation that trusts it.

- **Likelihood:** H — brand OCR in particular (small, stylized, sometimes absent
  label text, poor lighting) is one of the harder CV sub-problems in this pipeline
  and will have a meaningfully lower accuracy rate than category classification.
- **Impact:** M–H — wrong category/color data doesn't crash anything, but it
  quietly degrades compatibility scoring (§10) and wardrobe score (§10) for every
  outfit involving that item, compounding risk 1 (mediocre recommendations) with a
  root cause that's fixable at the data layer.
- **Leading indicator:** §18 already tracks `scan_corrected` — the metric to watch
  is correction rate *by field* (brand corrected far more often than category, for
  example, tells you exactly where confidence calibration or the model itself needs
  work) and correction abandonment (user starts editing, backs out without saving —
  a sign the correction UI itself is the friction, not just the underlying CV
  accuracy).
- **Mitigation.** Surface confidence per field visibly (§12 requires this) and
  default the review screen's cursor/focus to the lowest-confidence field first, not
  a uniform form. Make correction genuinely fast — large tap targets, common-value
  quick-pick chips (common brands, common colors) rather than free-text entry for
  every field, since free-text correction on a phone keyboard is itself a source of
  drop-off. Treat brand OCR confidence as low-trust by default (visibly marked, per
  §12) rather than presenting a guessed brand with the same visual weight as a
  high-confidence category guess — an overconfident-looking wrong brand guess is
  worse than an honest "not sure, tap to add" empty field. Feed correction data back
  into provider prompt/model tuning on a regular cadence (this is explicitly a
  provider-abstraction concern, ADR 0004 — a vision provider swap should be
  evaluated partly on whether it reduces the correction rate).
- **Owner-phase:** Phase 3 (Closet) for the correction UX itself; ongoing
  provider-tuning responsibility from Phase 3 onward.

---

## 4. Generative image risk — Style Studio outputs that look wrong, unflattering, or uncanny

**Description.** §13's Style Studio pipeline generates a visualization of the user
wearing an outfit from a reference selfie. Generated-human-image pipelines have a
well-known failure mode: subtly wrong faces, uncanny-valley proportions, garments
that render with impossible drape or color-shift, or — worse for this specific
product — an image that a user reasonably reads as "this is what I'd look like,"
when §11's guardrail is explicit that the app must never imply exact fit or a
guaranteed body outcome. A bad generation here is not just a technical miss; it's a
premium-positioned app (§3: "luxury stylist's editorial notebook") producing
something that looks cheap or off, which does disproportionate reputational damage
given the product's positioning, and a generation that looks *too* authoritative
about fit does real harm if a user makes a purchase decision based on a misleading
visual estimate.

**Update (vendor decided — `docs/10-style-studio-integration.md`): this is no
longer only a generic, industry-wide concern — there is a specific, verified
capability gap.** Higgsfield's Soul 2.0/Soul ID (the decided provider, `soul_2`
model) documents identity preservation as covering "facial structure, hair,
expression style, and identity features." It does **not** document preservation of
body proportions or skin tone beyond the face. §13 step 5 requires preserving
proportions and not beautifying/altering the body without request; §11 forbids
promising fit from imagery alone. That requirement sits directly on top of a gap
the vendor has not documented as covered — this is now a confirmed vendor-capability
mismatch, not a speculative "generative image models are inconsistent" concern.
`docs/10` §5 lays out the recommended mitigation in full (always attach a
concurrent reference photo even on the trained-identity path, since Soul ID and a
reference image are not mutually exclusive in the same `soul_2` call; nudge toward
half/full-body references over headshots when proportion preservation is on;
sampled offline proportion-consistency QA rather than a synchronous per-generation
gate, given the §20 latency budget; and — the piece that actually satisfies the
disclosure requirement — a body-specific disclaimer distinct from the generic
"visual estimate" label, since the generic label doesn't tell the user *which* axis
is uncertain). The mitigation narrows what Astra promises (recognizable face and
faithful garment rendering; body proportions and skin tone as directional, not
precise) rather than pretending the gap doesn't exist.

- **Likelihood:** H (raised from M–H) — this is now a documented, verified vendor
  limitation rather than a general industry pattern, so the likelihood of it
  surfacing in real generations is a near-certainty for any generation where the
  reference photo's build isn't trivially close to a generic average — not a
  probabilistic "may happen with some providers."
- **Impact:** H — a user's own likeness rendered badly is personal and memorable in
  a way a generic bad AI image isn't; screenshots of bad generations are exactly the
  kind of content that circulates on social media as mockery, which is acutely bad
  for a premium brand. Unchanged from the original assessment — the impact was
  already correctly rated high; what changed is confidence in the likelihood.
- **Leading indicator:** Studio generation retry rate (§21 "Studio failed: preserve
  prompt and allow retry... without consuming another credit when failure is
  provider-side" already implies retry is expected — track retry rate *and*
  post-generation engagement, i.e. does the user save/share/proceed to shop, or
  immediately abandon the result). A high "generate then immediately close, no
  save/share/shop" rate on technically-successful (non-error) generations is the
  signal that outputs are technically fine but qualitatively unconvincing. Add,
  specifically for the proportion gap: the sampled proportion-consistency check
  (`docs/10` §5.2) run weekly against a random sample of completed generations —
  this is the one leading indicator in this register that's a designed, deliberate
  measurement rather than an inferred behavioral signal, precisely because the
  underlying gap is now known rather than suspected.
- **Mitigation.** Always render the estimate-badge/disclaimer (§6.17, §13, §29 —
  this is non-negotiable and covered further in CLAUDE.md) so no output is ever
  presented as a guarantee — and, per `docs/10` §5.2, make that disclaimer
  body-specific on first view, not just the generic "visual estimate" line, since
  the verified gap is on a specific axis (body/skin tone) the generic label doesn't
  name. Offer a low-cost draft generation before any higher-cost high-res export
  (§13 already specifies this for cost reasons — it also functions as a quality
  gate, since a user can bail before consuming a premium credit on a bad result).
  Build an internal quality-review sample process before enabling a new provider or
  prompt-template version in production (`docs/10` §9's bake-off protocol is that
  process, made concrete, including a proportion-honesty scoring criterion
  specifically because of this gap). Provide an easy, fast "this doesn't look
  right, don't count this against my quota" reporting path distinct from ordinary
  retry, both to preserve goodwill and to generate a labeled dataset of bad outputs
  for provider evaluation. Structurally: always attach a fresh reference photo even
  on the trained-Soul-ID path (`docs/10` §5.2) so body/skin-tone grounding never
  depends solely on a capability the vendor hasn't documented as reliable.
- **Owner-phase:** Phase 6 (Studio and commerce) for the pipeline and quality gates;
  Phase 7 (Hardening) for the disclaimer/labeling audit before launch.

---

## 5. Cost risk — per-user inference cost against $12.99/month pricing

**Description.** Every meaningful Kyra interaction, every closet scan analysis, and
every Style Studio generation is a paid call to a reasoning, vision, or image
provider (§8's five provider protocols). At $12.99/month (§16), the margin for
provider cost, Apple's cut, and everything else is fixed and thin. This needs actual
arithmetic, not a vague "AI is expensive" concern.

### Update — verified pricing pass (supersedes the original estimated model below)

The original version of this section used a flat $0.02/reasoning-call placeholder
and a $0.04/$0.10 Style Studio placeholder pending vendor selection. Real pricing is
now available for the cost drivers that matter most:

- **Reasoning (`StylistReasoningProvider`, `08` §1 — still formally
  `DECISION PENDING`, ADR 0004/`08` §1.5, Tyler's call):** modeled here against a
  concrete three-tier model family with published pricing — **Luna** $1/1M input,
  $6/1M output; **Terra** $2.50/1M input, $15/1M output; **Sol** $5/1M input,
  $30/1M output — because that's the pricing data available to model against, not
  because the reasoning vendor decision has actually been made. `08` §1.3 already
  recommends routing cheap/simple intents to a smaller tier and reserving the top
  tier for judgment-heavy intents (`daily_outfit`/`product_advice`/`outfit_review`);
  this update prices that routing table concretely for the first time. **Cached
  input is 90% off** on this family — directly rewards `08` §1.3's suggestion to
  pin the system prompt + tool schemas (§1.2 of `06-kyra-orchestration.md`: ~1,200
  + ~1,500 = ~2,700 tokens) as a cached prefix.
- **Embeddings:** `text-embedding-3-small`, $0.02/1M tokens, 1,536 dims.
- **Style Studio (Higgsfield, decided — `docs/10-style-studio-integration.md`):**
  Soul ID training verified at 25 credits ≈ $1.25 → **$0.05/credit**.
  **Per-generation cost is now verified too, via a live `get_cost` preflight run
  directly against the Higgsfield API** — this section previously carried an
  explicitly-flagged, unverified assumption (4 credits/draft, 6 credits/hi-res) that
  turned out to be too pessimistic: the real figure is **0.12 credits exact per
  generation, billed as 1 credit, identical at both `1.5k` and `2k`** (`docs/10`
  §7.6). At $0.05/credit that's **$0.05/generation at the conservative, billed rate**
  (used as the planning number below, consistent with `docs/10`) or **$0.006 at the
  exact metered rate**. This resolves what the previous version of this section
  called "the single most important number to confirm" — it's confirmed, and the
  correction flows through the entire arithmetic below.

### Redone arithmetic

**Kyra turn cost, from the actual token budget (`06-kyra-orchestration.md` §1.2, `08` §1.4):**
cached prefix (system prompt + tool schemas) ≈ 2,700 tokens; variable input (context
packet up to 4,000 + trailing history up to 3,000, typically less than the ceiling)
≈ 5,500 tokens for a full-context turn; assumed output ≈ 500–600 tokens (message +
structured cards/tool-call arguments — not separately budgeted in `06`, estimated
here). Per-model-call cost:

```
Luna:  (2,700 × $0.0000001) + (5,500 × $0.000001) + (550 × $0.000006)
     = $0.00027 + $0.0055 + $0.0033  ≈ $0.0091/call

Terra: (2,700 × $0.00000025) + (5,500 × $0.0000025) + (550 × $0.000015)
     = $0.000675 + $0.01375 + $0.00825 ≈ $0.0227/call

Sol:   (2,700 × $0.0000005) + (5,500 × $0.000005) + (550 × $0.00003)
     = $0.00135 + $0.0275 + $0.0165 ≈ $0.0454/call
```

A single-call Luna turn (~$0.009) is well under the original flat $0.02 assumption.
But a real Kyra turn is not always one model call — a turn that resolves via
`search_closet` → `rank_outfits` → final answer (§11's tool list) is plausibly 1.5–3
model calls, not 1, each resending the cached prefix and most of the variable
context. **Revised baseline: ~$0.012/turn**, assuming a Luna-dominant mix with
realistic tool-call chaining (roughly 1.3 calls/turn on average, most turns simple).
**Revised heavy scenario: ~$0.03/turn**, assuming more chaining and a larger share
routed to Terra for the judgment-heavy intents `08` §1.3 flags for top-tier routing.
Both are inside, not above, the original $0.02–$0.05/turn assumption — **the
original per-turn number was pessimistic for the common case**, confirming the
instruction that prompted this update, though not by as wide a margin as the raw
Luna single-call number alone would suggest, once chaining and tier-routing are
accounted for realistically.

**Embeddings:** a closet item's embedded text (`normalizedTitle`, ~15–20 tokens) costs
roughly 20 × $0.02/1,000,000 ≈ $0.0000004 — effectively free at any realistic volume;
15 items/month ≈ $0.000006/month, rounds to $0.00. The original $0.0005/embedding
placeholder overstated this by roughly three orders of magnitude; it was never a
material line item and remains one now, just more precisely so.

**Style Studio, from `docs/10` §7.6–7.7 (verified via live `get_cost` preflight, not assumed):**

```
Any generation, either quality tier: 1 credit × $0.05/credit = $0.05/generation (planning rate)
                                      (0.12 credits exact × $0.05 = $0.006/generation, likely floor)
Soul ID training:                    25 credits × $0.05 = $1.25 (one-time; amortized ≈ $0.21/month
                                                            over an assumed 6-month retention window)
```

`docs/10` §7.2 re-derives the Premium quota to **60 generations/month** now that spend
no longer bounds it (queue latency and product-positioning judgment do, not cost —
see `docs/10` §7.2 for the full reasoning). At full quota utilization — the
worst-realistic-case framing this register uses throughout — that's
**60 × $0.05 = $3.00/month**, or **≈$3.21/month** including amortized training.
At a more realistic "actively engaged, not quota-maxing" usage of ~20
generations/month (the figure used in the monthly model below, consistent with the
volumes assumed for every other action in this section): **20 × $0.05 = $1.00/month,
≈$1.21/month including amortized training.** Both figures are far below the
earlier, incorrectly-assumed $3.40–3.61/month — the per-generation cost correction
alone is roughly a 3–4× reduction at realistic usage, on top of Kyra reasoning cost
already having come in cheaper than the original placeholder.

### Revised monthly model — "engaged" Premium subscriber, steady state

Reusing the original action volumes (30 Daily Briefs, 90 Kyra turns, 15 closet
scans, 20 product evaluations), Style Studio at the ~20 generations/month realistic-
usage figure above (not full-quota utilization — see the note below for that
variant), and vision-analysis cost left at the original $0.015/scan placeholder (no
verified replacement pricing exists for `VisionAnalysisProvider` at the time of this
update — still `DECISION PENDING`, `08` §2.5):

```
Daily briefs:      30 × $0.02 (Terra, single-call, judgment-tier per §1.3 routing) = $0.60
Kyra turns:         90 × $0.012 (revised baseline, Luna-dominant, chaining-aware)   = $1.08
Scan vision:        15 × $0.015 (unchanged — no verified pricing yet)              = $0.225
Scan embeddings:    15 × ~$0.0000004                                               ≈ $0.00
Product evals:      20 × ($0.012 reasoning + 0.3 × $0.015 extraction)              = $0.33
Studio (20 generations/month + amortized training, verified per-generation cost)   = $1.21
                                                                          Total    ≈ $3.45/month

Net revenue at 15% Apple cut:  $12.99 × 0.85 = $11.04   Margin: $11.04 − $3.45 = $7.59/month
Net revenue at 30% Apple cut:  $12.99 × 0.70 = $9.09    Margin: $9.09  − $3.45 = $5.64/month
```

This is **lower than the original placeholder model's $4.42/month**, not just lower
than the incorrect intermediate revision's $5.85/month — both cost drivers turned
out cheaper than assumed once real pricing was available, not just one. The
composition **reverts to the original model's shape**: Kyra conversation
($1.08+$0.60=$1.68) is again the largest cost line, well ahead of Style Studio
($1.21) — the intermediate revision's "Style Studio is now the dominant line"
conclusion was itself an artifact of an unverified assumption and does not hold
against the verified figure. Even the worst-case framing (full 60/month quota
utilization, $3.00–3.21/month for Style Studio) would not overtake Kyra conversation
cost at the volumes assumed here.

### Where it still breaks — heavy usage, redone again

Heavy-chat scenario (450 Kyra turns/month, ~15/day, at the $0.03/turn heavy-routing
estimate above), Style Studio and other lines at the steady-state figures above:

```
Kyra turns: 450 × $0.03 = $13.50
(daily briefs + scans + embeddings + evals + studio, unchanged) = $0.60+0.225+0.00+0.33+1.21 = $2.365
Total ≈ $15.87/month  →  exceeds gross revenue at both Apple cut tiers.
```

Solving for the breakeven turn count at the $0.03/turn heavy rate, holding every
other line at the steady-state figures above:

```
Budget available for Kyra turns at 15% cut:  $11.04 − $2.365 = $8.675  →  289 turns/month (~9.6/day)
Budget available for Kyra turns at 30% cut:  $9.09  − $2.365 = $6.725  →  224 turns/month (~7.5/day)
```

**This breakeven (224–289 turns/month) is higher than the incorrect intermediate
revision's 144–209, and close to — though still modestly below — the original
model's ~300–400 turns/month conclusion.** The remaining gap from the original
figure is attributable to more precise reasoning-cost modeling (accounting for
tool-call chaining and tier routing, which the original flat $0.05 placeholder
didn't model explicitly) rather than to Style Studio, which is now confirmed a
minor line item at realistic usage. **The dominant risk driver reverts to where the
original entry placed it: Kyra conversational turn volume, specifically among heavy-
usage power users — not, as the intermediate revision incorrectly concluded, Style
Studio's per-generation cost, which is now resolved and small.**

### Restated conclusion

The original conclusion holds, now on firmer ground than either prior version of
this section: **reasoning cost, driven by conversational volume, is the primary
lever on subscriber profitability, and Kyra conversation cost is confirmed cheap**
(roughly $0.01–0.03/turn depending on tool-call chaining and tier routing,
comfortably below the original $0.02–0.05 placeholder for the realistic majority of
turns). **Style Studio generation cost is now verified, not assumed — via a live
`get_cost` preflight against the real Higgsfield API — at $0.05/generation
(planning rate) regardless of quality tier, and is confirmed small and
well-characterized at realistic usage (≈$1.21/month) and even at full-quota
utilization (≈$3.21/month).** It is neither the largest nor the least-certain line
in this model; that framing, introduced in an intermediate revision of this
section built on a flagged-but-unverified assumption, is withdrawn. The practical
implication is now the same one the original entry drew: the number worth watching
is Kyra turn volume among the heaviest-usage subscribers, not Style Studio pricing,
which this update closes out as a settled input rather than an open question.

- **Likelihood:** M (unchanged from the original entry; the intermediate revision's
  M was correct in grade but for a reason — Style Studio cost uncertainty — that no
  longer applies) — the baseline scenario is comfortably profitable at both Apple
  cut tiers; the risk is concentrated in the tail of heavy-chat-usage subscribers,
  as in the original entry, not spread across the typical subscriber base.
- **Impact:** H (unchanged) — if realized broadly rather than in the tail (the
  *typical* engaged user running well above 90 turns/month, or the team landing at
  the 30% Apple tier), this remains a "business model underwater on its highest-
  tier customers" outcome, not a bug to patch — the same conclusion the original
  entry drew, now re-confirmed rather than displaced by a Style Studio-driven
  reading.
- **Leading indicator:** Per-user monthly provider cost, computed from actual
  billing/usage data and segmented by subscription tier and by cost category
  (reasoning vs. vision vs. embedding vs. Style Studio) — retained from the prior
  revision, since segmenting by category is still useful even though the categories
  no longer move in opposite directions. Specifically watch: Kyra turns/day
  distribution (the original indicator, now the primary one again) and the ratio of
  (top-decile-usage subscriber cost) to (median-subscriber cost). Style Studio
  generation volume against the new 60/month quota is worth tracking operationally
  (queue latency, storage growth) but is no longer a cost-risk indicator per se.
- **Mitigation.** Everything in the original mitigation still applies (instrument
  actual per-provider-call cost from day one, §14; rate-limit by tier, §16; cache
  repeated combinations, §13). Pin the system prompt + tool schemas as a cached
  prefix (§1.2 of `06`, rewarded directly by the 90%-off cached-input pricing) as a
  concrete, immediately-available cost lever. Extend the soft daily/monthly Kyra
  turn cap for Premium (graceful degradation — a lower-cost reasoning tier under
  heavy load — rather than a hard wall) as the primary lever against the tail risk
  identified above, since that risk is now confirmed to be where it originally was.
  The "prefer draft before hi-res" mitigation from `08`/§13 no longer applies to
  Style Studio specifically for this vendor — `docs/10` §7.4 documents why (1.5k
  and 2k cost identically for `soul_2`) and repurposes the underlying idea as a
  storage-retention distinction (save-to-lookbook) instead of a resolution-cost
  gate; this register's cost mitigation for Style Studio is now the §7.2 quota and
  burst limiter in `docs/10`, not a resolution tier.
- **Owner-phase:** Phase 5 (Kyra) and Phase 6 (Studio) for cost instrumentation and
  rate limiting as those systems are built; Phase 7 (Monetization and hardening) for
  the pricing/quota policy decision once real usage data exists.

---

## 6. App Store review risk

**Description.** Several aspects of this product sit in categories Apple's review
process scrutinizes closely: generated imagery depicting a real, identifiable
person (Style Studio, §13); health-adjacent body data (measurements, fit profile,
§6.6, §6.7 — not medical, but close enough to invite extra scrutiny, especially if
any copy reads as body-transformation-adjacent); affiliate commerce and sponsored
content (§17) which must be clearly disclosed per Guideline 3.1.5-adjacent
expectations around transparency; and mandatory in-app account deletion (§7, §29 —
Apple requires this explicitly for any app that supports account creation, per
Guideline 5.1.1(v)).

- **Likelihood:** M — none of these are unprecedented app categories, but the
  combination (real-person generative imagery + body data + affiliate links + a
  subscription paywall) increases the surface for a rejection on any single review
  pass, and generative-imagery-of-real-people apps have drawn extra App Review
  attention industry-wide.
- **Impact:** M–H — a rejection near a planned launch date is a real schedule risk,
  and a *removal* after launch (rather than a pre-launch rejection) would be far
  worse — direct revenue and reputational damage.
- **Leading indicator:** This is inherently hard to "detect early" from internal
  metrics, since App Review is a gate, not a metric — the practical leading
  indicator is a dedicated pre-submission compliance pass (below) surfacing gaps,
  and staying current with App Review Guideline changes specific to generative AI
  imagery, which Apple has iterated on.
- **Mitigation.** Build the §29-required controls (in-app deletion, data export,
  individual image deletion, clear generated-image disclaimers, opt-out for model
  training) as MVP-blocking, not launch-hardening-phase afterthoughts, since
  Guideline 5.1.1(v) makes account deletion a near-certain rejection reason if
  missing. Write privacy-policy language (§29) that accurately and specifically
  describes image processing, named model providers, and retention *before*
  submission, since vague or inaccurate privacy-nutrition-label answers are a common
  rejection/delay cause. Ensure every affiliate link and sponsored placement is
  labeled per §17 with no ambiguity, and keep sponsored ranking separated from
  organic ranking in the actual UI, not just in a policy document. For Style
  Studio, keep the require-ownership/permission gate (§6.17) and the visible
  estimate label (§13) enforced server-side (ADR 0004) so review cannot find a path
  that skips them. Budget real calendar time for at least one rejection-and-resubmit
  cycle in the release plan rather than assuming first-pass approval.
- **Owner-phase:** Phase 7 (Monetization and hardening), but the underlying
  controls (deletion, disclosure, labeling) must actually be built starting in the
  phases that own each feature (Phase 6 for Studio labeling, Phase 1/2 for account
  deletion plumbing) — treating this as purely a Phase 7 concern risks discovering
  the gaps too late to fix cheaply.

---

## 7. Privacy/legal risk — selfies, body measurements, and provider data retention

**Description.** Reference selfies and body measurements (§6.6, §6.7) are sensitive
personal data by most reasonable standards and by some jurisdictions' specific
legal categories (biometric-adjacent data in places like Illinois' BIPA, or
special-category data under GDPR if any inference touches protected
characteristics). §29 requires the privacy policy to describe image processing,
model providers, and retention; requires a model-training opt-out defaulting to no
training; and requires the app avoid collecting unnecessary sensitive demographic
data. The risk is twofold: (a) getting the *policy* wrong (inaccurate or vague
disclosure) and (b) a **third-party AI provider retaining or using data in a way
that contradicts Astra's own stated policy**, which Astra does not fully control
once an image or profile field leaves the Edge Function boundary.

- **Likelihood:** M — provider contracts and data-processing terms vary and change;
  what's true of a provider's retention policy at integration time is not
  guaranteed to stay true, and multi-provider abstraction (ADR 0004) means this must
  be tracked per-provider, not once.
- **Impact:** H — a provider retaining and later exposing or training on a user's
  selfie, in contradiction of Astra's stated no-training-by-default policy (§29),
  is a genuine legal and trust failure, not just a policy technicality — this is the
  kind of incident that produces press coverage disproportionate to the number of
  users actually affected.
- **Leading indicator:** No internal product metric surfaces this directly — the
  leading indicator is process: whether each provider integration has a signed,
  reviewed data-processing agreement covering retention/training use *before* it
  goes live, and whether that agreement is periodically re-verified (providers do
  change terms). Absence of this process, not a metric crossing a threshold, is
  itself the risk signal to watch for.
- **Mitigation.** Require a data-processing agreement (or documented equivalent)
  addressing retention and training use as a condition of integrating any new
  provider behind the five protocols in ADR 0004 — this should be a checklist item
  in the provider-onboarding process, not an assumption. Default every provider
  call to the strictest available no-retention/no-training flag (ADR 0010) and
  verify, not assume, that the flag is honored where technically checkable. Minimize
  what's sent to providers in the first place — send cropped/normalized garment
  images rather than full personal photos to vision providers where the task
  doesn't require the full image (data minimization reduces exposure even before
  retention policy matters). Keep the appearance-profile fields (§6.7: skin
  undertone, hair color, tattoos, etc.) genuinely optional with a clear "why we ask"
  per field, consistent with §29's "avoid collecting unnecessary sensitive
  demographic data," and avoid inferring any of these fields silently from images
  without disclosure. Revisit provider agreements on a fixed cadence (e.g.
  quarterly), not just at initial integration.
- **Owner-phase:** Phase 6 (Studio and commerce) for the selfie-handling pipeline
  specifically; Phase 1 provider selection and Phase 7 hardening for the
  agreement/audit process, which should exist before any provider integration goes
  live, not retrofitted later.

---

## 8. Affiliate integrity risk — commercial incentive silently biasing Kyra's verdict

**Description.** §17 states the principle plainly: "Affiliate availability must not
change Kyra's verdict." This is easy to write down and hard to enforce in practice,
because the same signals that make a product a good affiliate opportunity
(available inventory, active catalog data, a retailer relationship) also make it
the *easiest* product for the system to surface and evaluate — meaning a
recommendation engine can end up systematically favoring affiliate-available
products not because of an explicit rule but because of what data happens to be
richest and most readily available, which is functionally the same outcome as
letting commercial incentive drive the verdict, just arrived at less deliberately.
This risk is dangerous specifically because it can happen *without anyone writing
biased code* — it emerges from data availability asymmetry.

- **Likelihood:** M — this is a subtle, structural risk rather than a discrete bug;
  it's the kind of thing that creeps in through product-catalog data quality
  differences, not through an intentional decision.
- **Impact:** H — if discovered (by a user, a journalist, or a competitor), this
  directly contradicts Kyra's positioning as an opinionated, trustworthy stylist
  (§2) and would be reputationally severe precisely because trustworthiness is the
  entire value proposition — a stylist whose "buy" verdicts turn out to correlate
  with commission is not a stylist, it's a sales funnel wearing a stylist's voice.
- **Leading indicator:** A statistical audit, not a vibe check: compare Kyra verdict
  distribution (buy/consider/wait/skip, §6.19) for affiliate-linked versus
  non-affiliate/user-pasted products, controlling for product category, price, and
  wardrobe-fit score. A statistically significant skew toward "buy" for
  affiliate-available products at equivalent computed compatibility/redundancy
  scores is the concrete signal something is off — either in scoring logic or in
  what data reaches the verdict step.
- **Mitigation.** Enforce this architecturally, not just by policy: the compatibility
  scoring, redundancy scoring, and verdict logic (§6.19, §10) must compute from the
  same feature set (attributes, price, fit data) regardless of whether a product
  came from the curated affiliate catalog or a user-pasted URL (§17's three
  ingestion paths) — the verdict function should not have access to
  affiliate-relationship data as an input at all, only to product attributes.
  Sponsored/organic separation (§11: "Separate sponsored placement from organic
  ranking") should be a UI-layer concern (labeling, placement) applied *after* the
  verdict is computed, never feeding back into the verdict itself. Run the
  statistical audit above on a recurring schedule (not just once at launch) as
  product catalog composition shifts over time, and treat a detected skew as a
  release-blocking bug, not a tuning nuance. Keep this auditable by construction:
  log which scoring inputs were actually used per evaluation (§14's request-ID
  logging) so a post-hoc audit can verify affiliate status truly wasn't a scoring
  input, not just trust that it wasn't.
- **Owner-phase:** Phase 6 (Studio and commerce) for the verdict/scoring separation
  as product evaluation is built; ongoing audit responsibility from Phase 6 onward,
  owned by whoever owns product-catalog quality (likely intersecting with the §28
  admin tooling for catalog management).

---

## 9. Technical risks

### 9a. SwiftData maturity

Covered in depth in ADR 0005. Real risk that SwiftData's younger migration story,
predicate limitations, and Swift 6 strict-concurrency interaction produce framework
bugs, not just app bugs, that block or slow offline-cache development.
**Likelihood:** M. **Impact:** M. **Leading indicator:** Repeated SwiftData crashes
or migration failures surfacing in TestFlight/crash reporting that don't correspond
to an identifiable app-code bug. **Mitigation:** budget contingency time in Phase 1
for SwiftData spike/prototyping before committing the full offline architecture to
it; keep the fallback (GRDB/SQLite, per ADR 0005's alternatives) genuinely
available, not theoretical, if SwiftData proves unworkable. **Owner-phase:** Phase 1
(Foundation).

### 9b. Edge Function cold starts

Covered in ADR 0002/0004. Deno-based Edge Functions have cold-start latency that
directly threatens §20's performance targets (Kyra first token under 2.5s).
**Likelihood:** M. **Impact:** M. **Leading indicator:** p95/p99 latency on
`POST /kyra/respond` and `POST /outfits/generate` tracked from Phase 5 onward,
specifically the tail, not just the mean — cold starts show up as tail latency
spikes, not average degradation. **Mitigation:** keep-warm strategies, minimizing
per-invocation initialization, and measuring real cold-start frequency under
realistic (not synthetic, always-warm) traffic patterns before assuming the target
is met. **Owner-phase:** Phase 5 (Kyra) and Phase 4 (Outfit intelligence).

### 9c. Embedding dimension lock-in

`style_profiles`, `closet_items`, `outfits`, and `style_memories` all carry a
pgvector `embedding` column (§9). The embedding provider chosen (ADR 0004) fixes a
vector dimensionality; switching embedding providers later means either
re-embedding the entire historical corpus (expensive, requires a migration
strategy) or running two dimensionalities in parallel during a cutover.
**Likelihood:** M (embedding providers are less volatile than reasoning/image
providers, but not immune to deprecation/pricing changes). **Impact:** M — costly
to fix, not existential. **Leading indicator:** none proactive; this is a risk to
architecturally pre-empt rather than detect. **Mitigation:** store the embedding
provider/model version alongside each embedding (a metadata column, not just the
raw vector) from day one, so a future migration can identify exactly which rows
need re-embedding rather than guessing; avoid hardcoding vector dimensionality
assumptions in application code outside the schema definition itself.
**Owner-phase:** Phase 2 (Identity, where the first embeddings are generated) —
get the metadata convention right before the corpus grows.

### 9d. Vector index performance at scale

pgvector index performance (HNSW/IVFFlat) degrades or requires retuning as row
counts grow, and query patterns that mix vector similarity with relational filters
(ADR 0003's core pattern — filter by category/formality *and* rank by embedding
similarity) can defeat naive indexing if not deliberately tuned. **Likelihood:** L
at MVP scale, rising over time. **Impact:** M. **Leading indicator:** query latency
on compatibility/similarity searches tracked as closet/catalog size grows, watched
specifically for a step-change rather than gradual degradation (a sign an index
type or parameter needs to change, not just more hardware). **Mitigation:** load-
test vector queries against realistic future-scale synthetic data (thousands of
items per user × many users, plus a large product-candidate catalog) before it's a
production problem, not after. **Owner-phase:** Phase 4 (Outfit intelligence) for
initial indexing strategy; revisit ahead of any major user-growth milestone.

### 9e. Provider API instability

Reasoning, vision, and image-generation providers can change pricing, rate limits,
model behavior, or content policy with limited notice — this is normal for the
current AI-provider market, not a hypothetical. **Likelihood:** H over a
multi-year horizon. **Impact:** M, mitigated specifically *because* ADR 0004's
provider-neutral layer exists — the impact would be H without it.
**Leading indicator:** provider status pages, deprecation notices, and — more
practically — a sudden shift in the cost model in risk 5 above, or a spike in
provider error rates/latency tracked per-provider in Edge Function logs.
**Mitigation:** this is the reason ADR 0004 exists; keep at least a credible
secondary implementation path evaluated (not necessarily live) for each of the five
provider protocols so a forced migration isn't a from-scratch integration effort.
**Owner-phase:** ongoing from Phase 5/6 onward, owned by whoever owns the provider
abstraction layer.

---

## 10. Scope risk — MVP creep

**Description.** §00's master spec is large — 31 sections spanning full onboarding,
a computer vision pipeline, a generative image pipeline, a conversational AI system,
affiliate commerce, and a subscription business, each with real depth. §23 already
draws an MVP line (must-ship / can-follow / explicitly-defer) and §24 sequences a
7-phase build order, which is exactly the right instinct — but the default outcome
for a spec this comprehensive, read by any team (human or AI-agent), is to treat
every section as equally urgent and build breadth-first, arriving at launch with
many features half-finished rather than a smaller set genuinely done to the §22
acceptance bar.

- **Likelihood:** H — this is the single most statistically common failure mode for
  ambitious specs of this size, independent of team quality.
- **Impact:** M–H — doesn't kill the product outright the way risk 1 (mediocre
  recommendations) or risk 5 (unprofitable unit economics) can, but directly causes
  a worse version of risk 1: a wide, shallow build produces exactly the "plausible
  but not good" outcome across many features at once, and delays the point at which
  real user feedback can even start correcting course.
- **Leading indicator:** Compare, at any point in the build, the number of §23
  "must ship" features that meet the full §22 acceptance bar (no lorem ipsum, no
  dead buttons, no unhandled network failure, etc.) versus the number of "can follow
  shortly after" or "explicitly defer" features that have *any* work started on them.
  Any meaningful work on a deferred feature while a must-ship feature is still
  incomplete is the concrete, checkable signal of scope creep in progress — not a
  vague sense of being "behind."
- **Mitigation.** Treat §23's three-tier scope list and §24's phase order as binding
  sequencing, not a suggestion — a Phase 6/7 feature (Studio, affiliate commerce,
  monetization) should not receive engineering time while a Phase 1–4 dependency is
  still incomplete to the §22 bar, even if the later feature seems more interesting
  or is explicitly requested out of order. Use the §30 Definition of Done (the
  14-step "a new user can...") as the actual launch gate, and treat anything not on
  that list as explicitly out of scope for v1 regardless of how much of the master
  spec describes it. For AI coding agents specifically (this repo's primary
  contributor profile per §0), this means `docs/01-build-roadmap.md` and
  `docs/02-task-breakdown.md` phase/ticket sequencing (see `CLAUDE.md`) should be
  followed in order rather than an agent self-selecting whichever section of the
  1800-line spec looks most tractable to implement next.
- **Owner-phase:** every phase — this is a process discipline risk, not a
  single-phase technical risk, and the mitigation is enforced at planning/review
  time throughout Phases 1–7.

---

## Summary table

| # | Risk | Likelihood | Impact | Owner-phase |
|---|---|---|---|---|
| 1 | Mediocre recommendations (silent product death) | H | H | Phase 4, ongoing |
| 2 | Cold-start friction (~15 items to be useful) | H | H | Phase 2–3 |
| 3 | CV accuracy (classification/OCR/background removal) | H | M–H | Phase 3, ongoing |
| 4 | Generative image quality/reputational risk (incl. verified body-proportion gap) | H | H | Phase 6–7 |
| 5 | Per-user cost vs. $12.99/month pricing | M | H | Phase 5–7 |
| 6 | App Store review | M | M–H | Phase 1–2, 6–7 |
| 7 | Privacy/legal — selfies, body data, provider retention | M | H | Phase 1, 6–7 |
| 8 | Affiliate integrity — commercial bias in verdicts | M | H | Phase 6, ongoing |
| 9a | SwiftData maturity | M | M | Phase 1 |
| 9b | Edge Function cold starts | M | M | Phase 4–5 |
| 9c | Embedding dimension lock-in | M | M | Phase 2 |
| 9d | Vector index performance at scale | L (rising) | M | Phase 4 |
| 9e | Provider API instability | H (multi-year) | M (mitigated by ADR 0004) | Ongoing |
| 10 | Scope creep against a large spec | H | M–H | All phases |

**The single risk most likely to actually kill this project is risk 1: outfit
recommendations that are merely plausible rather than genuinely good.** Every other
risk in this register is either detectable through an error, a crash, a cost
dashboard, or a review rejection — all things that generate a forcing function to
fix them. Risk 1 generates no such signal. A user for whom Kyra's picks are simply
"fine" does not file a bug report; they just quietly stop opening the app, and by
the time that shows up in aggregate retention numbers, a meaningful amount of
runway and word-of-mouth has already been spent on a product that never actually
proved its core promise. This is why the north-star instrumentation (§18) and a
real, human, taste-based evaluation process must exist before broad launch, not
after.
