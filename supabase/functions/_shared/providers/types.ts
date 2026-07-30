// ============================================================================
// _shared/providers/types.ts
// ============================================================================
// The shared envelope and error taxonomy every provider protocol in
// `docs/08-provider-abstraction.md` §0 declares. Lives in `_shared/` rather
// than beside the first function that needs it because §8 of the master spec
// names FIVE provider protocols (StylistReasoningProvider,
// VisionAnalysisProvider, ImageGenerationProvider, EmbeddingProvider,
// ProductExtractionProvider) and ADR 0004 requires all five to share one
// retry/logging/circuit-breaker story. Putting the envelope next to
// `style-dna/` — the first consumer — would mean `closet/analyze-item`
// copies it in Phase 3 and the two drift.
//
// These types are Astra-shaped, NOT vendor-shaped, and that is the entire
// point of ADR 0004: "The interfaces in this document are Astra-shaped, not
// OpenAI-shaped — the tool schema, message roles, and response contract are
// translated to/from the vendor's API format inside the adapter, not leaked
// into the protocol." A vendor swap changes an adapter file; it must never
// change a handler, a DTO, or anything the iOS client can observe.
// ============================================================================

/**
 * Carried by every provider call so logging, tracing, retry and cost
 * attribution are uniform across all five provider types
 * (`docs/08-provider-abstraction.md` §0).
 *
 * `requestId` is propagated from the originating Edge Function request
 * rather than generated here, so one line in the Supabase log drain ties a
 * client request to the provider call it caused — spec §14's "log request
 * ID and latency" is only useful if the id survives the hop.
 */
export interface ProviderRequestContext {
  readonly requestId: string;
  readonly userId: string;
  /** Hard timeout for this call. See each provider's latency budget in `docs/08` §N.4. */
  readonly timeoutMs: number;
  /**
   * Required for any call with a real-money or quota cost, so a client-side
   * or network-level retry cannot double-charge. Absent for free/mock
   * implementations, which is why it is optional rather than defaulted to
   * something meaningless.
   */
  readonly idempotencyKey?: string;
}

/**
 * `docs/08-provider-abstraction.md` §0's error taxonomy, verbatim. The split
 * that matters is retryable vs not: TIMEOUT / PROVIDER_UNAVAILABLE /
 * RATE_LIMITED are worth one automatic retry; AUTH_FAILED / INVALID_INPUT /
 * CONTENT_MODERATION_REJECTED will not succeed on retry and burning the
 * retry budget on them only adds latency to a response a user is waiting on.
 */
export type ProviderErrorCode =
  | "TIMEOUT"
  | "RATE_LIMITED"
  | "AUTH_FAILED"
  | "INVALID_INPUT"
  | "CONTENT_MODERATION_REJECTED"
  | "PROVIDER_UNAVAILABLE"
  | "PROVIDER_QUOTA_EXCEEDED"
  | "UNKNOWN";

export class ProviderError extends Error {
  readonly code: ProviderErrorCode;
  readonly retryable: boolean;
  readonly providerRawStatus?: number;

  constructor(
    code: ProviderErrorCode,
    retryable: boolean,
    message: string,
    providerRawStatus?: number,
  ) {
    super(message);
    this.name = "ProviderError";
    this.code = code;
    this.retryable = retryable;
    this.providerRawStatus = providerRawStatus;
  }
}

/**
 * The operational tiers `docs/08-provider-abstraction.md` §1.5 resolved and
 * `docs/09-model-routing.md` routes between: Luna is the default, Terra the
 * escalation tier, Sol a narrow ceiling reserved for double-escalation.
 *
 * Modeled as a provider-neutral enum rather than a vendor model id string on
 * purpose. `docs/09` §1 assigns a TIER to each call type — Style DNA
 * generation is Terra (row 6: "foundational, high-perceived-quality-stakes,
 * structurally low-volume") — and that assignment is a policy statement
 * about how much reasoning the call deserves, not a statement about which
 * vendor is wired in this month. An adapter maps a tier to whatever model
 * identifier its vendor uses; nothing above the adapter names a model.
 */
export type ModelTier = "luna" | "terra" | "sol";
