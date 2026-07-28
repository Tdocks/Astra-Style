# 0004. Provider-neutral AI layer behind Edge Functions

## Status

Accepted

## Context

Astra Style depends on multiple categories of AI provider capability: reasoning
(Kyra's stylist logic), vision analysis (garment classification, OCR, condition
estimation), image generation (Style Studio), embeddings (style/closet/outfit
similarity), and product-page extraction (parsing a pasted retailer URL into
structured product data). §8 requires this be built as a provider-neutral server
interface — five named protocols (`StylistReasoningProvider`,
`VisionAnalysisProvider`, `ImageGenerationProvider`, `EmbeddingProvider`,
`ProductExtractionProvider`) — with an explicit instruction: "Do not hardcode the
app directly to one model vendor." §8 also states "the iOS client talks only to
Astra Edge Functions." §25 keeps every provider API key server-side; the app
receives only `SUPABASE_URL` and `SUPABASE_ANON_KEY`.

The alternative would be to call a model vendor's SDK (e.g. an LLM vendor's iOS SDK,
or a direct REST call from the client with an embedded key) directly from the app,
which is faster to prototype and has one fewer network hop.

## Decision

1. Define five server-side provider protocols matching §8 exactly, each with a
   single responsibility and a stable input/output contract independent of which
   vendor implements it.
2. Every provider has at least one concrete implementation per supported vendor, and
   a mock implementation behind the same protocol for use when a vendor key is
   unavailable (§31).
3. The iOS client never holds a provider API key and never constructs a request to a
   model vendor's endpoint. It calls Astra Edge Functions only (§14's endpoint list),
   and Edge Functions call providers using server-held credentials (§25).
4. Provider selection (which vendor backs `StylistReasoningProvider` today) is a
   server-side configuration concern, changeable without an app release.

## Consequences

### Positive

- A vendor outage, price increase, or policy change (e.g. an image-generation
  provider tightening its content policy in a way that breaks Style Studio) is a
  server-side swap, not an App Store resubmission. This matters concretely for
  Astra Style because generative image providers are the least mature, most
  frequently-changing category in the stack.
- Provider API keys never ship in the app binary, closing an entire class of key
  exfiltration risk (a decompiled app leaking a vision or image-gen key that could
  then be used at Astra's expense by anyone).
- The Edge Function boundary is a natural place to enforce guardrails that must never
  be bypassable client-side: the "never imply exact fit," "label as estimate,"
  "affiliate availability must not change Kyra's verdict" rules in §11 and §17 are
  enforced in code the client cannot route around, not in client-side prompt
  construction that a jailbroken or modified client could skip.
- A/B testing or gradually rolling out a new reasoning or image-generation vendor is
  a server-side flag, testable on a slice of traffic without a client release train.
- Mock implementations behind the same protocol (§31) let iOS development proceed
  against realistic contracts before a given provider account/key exists, without
  the client code knowing the difference.

### Negative (real costs, named)

- **The indirection has a real latency cost.** Every AI-backed action is
  client → Edge Function → provider → Edge Function → client, i.e. two network hops
  plus Edge Function cold-start risk (ADR 0002) instead of one direct client-to-
  vendor call. This is in direct tension with §20's Kyra-first-token-under-2.5s and
  Studio-under-30s targets, and has to be actively engineered around (streaming
  responses through the Edge Function, keeping functions warm) rather than assumed
  away by the abstraction.
- **Five protocols is real design and maintenance overhead**, not free architecture.
  Each protocol needs a stable contract that's abstract enough to cover multiple
  vendors' actual capabilities (which differ — one vision vendor may return
  brand-confidence scores structured differently than another) without leaking
  vendor-specific quirks through the abstraction, and specific enough to be useful.
  Getting that boundary wrong produces either a leaky abstraction (vendor quirks
  bleed through) or a lowest-common-denominator one (the protocol can't express a
  capability a specific vendor actually has, e.g. a particular vendor's superior
  structured JSON mode).
- Debugging a production issue now spans two systems (Edge Function logs and vendor
  dashboards) instead of one; §14 explicitly forbids logging full prompt contents or
  private images, which is correct for privacy but makes some failures harder to
  reproduce from logs alone.
- Every new provider integration is genuinely two implementations minimum (the real
  vendor adapter plus keeping the mock in sync as the protocol evolves), which is
  slower than "just call the SDK" for a single-vendor prototype.
- The abstraction can create false confidence that switching vendors is free. In
  practice, prompt engineering, few-shot examples, and output-parsing logic tend to
  be tuned to a specific vendor's actual behavior; the protocol boundary hides
  *interface* differences, not *quality/behavior* differences, so a vendor swap
  still requires real evaluation work even though the code compiles unchanged.

## Alternatives Considered

- **Direct client-to-vendor SDK calls.** Rejected: violates §25's secret-handling
  requirement outright (any embedded key is extractable from the app binary), and
  makes every guardrail in §11 client-enforced and therefore bypassable.
- **Single hardcoded vendor, no abstraction.** Rejected: the AI provider landscape
  for reasoning, vision, and image generation is the fastest-moving part of this
  stack; §8's explicit instruction against hardcoding one vendor reflects a
  reasonable expectation that at least one provider category will need to change
  before Astra Style reaches maturity. The cost of the abstraction (above) is judged
  cheaper than a mid-flight rewrite under vendor-outage pressure.
- **A generic third-party LLM gateway/router (e.g. an off-the-shelf multi-provider
  proxy service) instead of a hand-rolled protocol layer.** Rejected for v1: adds
  another vendor dependency and another place data about users' images and style
  preferences would transit, in tension with §29's data-minimization posture. The
  five protocols are deliberately Astra-domain-shaped (e.g.
  `ProductExtractionProvider` is not a generic LLM call, it is a specific contract
  for turning a retailer page into structured product data), which a generic router
  would not model any better than a thin hand-rolled layer.
