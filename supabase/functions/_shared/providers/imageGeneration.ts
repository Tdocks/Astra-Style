// ============================================================================
// _shared/providers/imageGeneration.ts
// ============================================================================
// `ImageGenerationProvider` — the third of spec §8's five provider
// protocols, specified in `docs/08-provider-abstraction.md` §3. Interface
// ONLY: no vendor SDK, no API key handling, no HTTP. The mock lives beside
// it (`mockImageGeneration.ts`); the live OpenAI adapter lives in
// `openaiImageGeneration.ts` and is constructed exclusively in
// `studio/index.ts` when enabled by env — never from a handler, never
// from iOS (ADR 0004: the client never holds a provider key).
//
// TWO DELIBERATE DEPARTURES FROM `docs/08` §3's SKETCH, both with reasons:
//
// 1. `prompt` and `generationId` are ON the request. `docs/08` §8.2 has the
//    provider assemble the prompt itself; here the HANDLER assembles it
//    (studio/promptBuilder.ts) and passes the finished string down. The
//    reason is §21's retry contract: the prompt persisted in
//    `studio_generations.prompt_payload` must be *the* string the provider
//    submitted — not a second assembly that could drift from the stored
//    one between the original attempt and a retry. One assembly, stored
//    first, submitted verbatim. `generationId` exists so every adapter
//    derives the same deterministic result path
//    (`users/{userId}/studio/{generationId}/result.png`, spec §15) with no
//    per-isolate state — which is also what makes `pollStatus`
//    answerable from a different isolate than the one that submitted.
//
// 2. NO `handleWebhook`. `docs/08` §3 sketches one so poll- and push-based
//    vendors normalize to a single shape. The one live vendor (OpenAI,
//    `docs/08` §3.5) has no webhook delivery for image generation, so an
//    interface method no adapter can implement honestly would be a stub
//    that throws — dead code wearing a protocol's clothes. Add the method
//    when a vendor exists that can actually be wired to it.
// ============================================================================

import type { ProviderRequestContext } from "./types.ts";

/**
 * One garment in the structured list. Field-for-field the shape
 * `studio/promptBuilder.ts` consumes: built from `closet_items` attributes
 * (the same ones that drive compatibility scoring, `docs/05`), never a
 * free-text re-description of the outfit (`docs/08` §8.2).
 */
export interface StudioGarment {
  /** Slot within the outfit — `clothing_category` values. */
  readonly role: string;
  /** e.g. "knit crewneck sweater" — `closet_items.name`/`subcategory`. */
  readonly normalizedTitle: string;
  /** Natural-language colour, e.g. "navy" — `closet_items.primary_color`. */
  readonly colorDescription: string;
  readonly material: readonly string[];
  /** "solid" | "stripe" | ... Empty string when unknown. */
  readonly pattern: string;
  /**
   * The cut. Carried separately from the title because `docs/15` §3b
   * measured that cut buried as an adjective is dropped by the model
   * (honoured 2/18) while cut as a sentence subject is always honoured —
   * the prompt builder needs it as its own field to foreground it.
   */
  readonly fit: string;
}

/** `docs/08` §3 — request side, with the header's two departures. */
export interface ImageGenerationRequest {
  /** The `studio_generations.id` this job renders. Determines the result path. */
  readonly generationId: string;
  /** Private Supabase Storage path — never a public URL (spec §15). */
  readonly referenceImageStoragePath: string;
  /**
   * Provider-specific identity token from a prior preprocessing step, if
   * the provider requires one. The OpenAI adapter accepts the raw
   * reference image directly, so this is unused today; kept for `docs/08`
   * §3 protocol generality.
   */
  readonly identityRepresentation?: string;
  readonly structuredGarmentList: readonly StudioGarment[];
  /**
   * The fully assembled spec §13 prompt (studio/promptBuilder.ts), stored
   * in `prompt_payload` BEFORE submission and submitted verbatim — see the
   * header for why assembly happens above this interface.
   */
  readonly prompt: string;
  readonly pose: string;
  readonly background: string;
  readonly lighting: string;
  readonly formality: string;
  /**
   * §13's draft-before-hi-res cost lever, live again under OpenAI pricing
   * (docs/08 §3.5: gpt-image-1.5 portrait — medium $0.050, high $0.200,
   * a real 4× saving per draft, unlike the dropped vendor whose tiers
   * billed identically).
   */
  readonly resolution: "draft" | "hi_res";
  readonly preserveFace: boolean;
  readonly preserveBodyProportions: boolean;
  readonly preserveHairFacialHair: boolean;
}

/** `docs/08` §3 — result side, verbatim. */
export interface ImageGenerationResult {
  readonly status: "queued" | "generating" | "complete" | "failed";
  /** Private Storage path of the re-hosted result; never a provider URL. */
  readonly resultStoragePath: string | null;
  readonly providerJobId: string;
  readonly errorMessage: string | null;
  /**
   * §21/`docs/08` §3.2: true unless the failure is a content-moderation
   * rejection — a moderation rejection is never auto-retried, everything
   * else may be retried without consuming quota.
   */
  readonly isRetryableFailure: boolean;
}

/**
 * The deterministic result path every adapter writes to and every poll
 * checks — spec §15's `users/{user_id}/studio/...` convention. One shared
 * function rather than per-adapter string building so a vendor swap cannot
 * quietly move where results land (retention jobs and account deletion
 * both sweep by this prefix, ADR 0010).
 */
export function studioResultPath(userId: string, generationId: string): string {
  return `users/${userId.toLowerCase()}/studio/${generationId.toLowerCase()}/result.png`;
}

export interface ImageGenerationProvider {
  /**
   * Submits a job. MAY block for the duration of the render (OpenAI's
   * image API is synchronous), which is why the studio handler calls this
   * from the status-poll path — the closet batch "advance on poll"
   * pattern — never from `POST /studio/generate`'s request handling.
   */
  submitGeneration(
    request: ImageGenerationRequest,
    ctx: ProviderRequestContext,
  ): Promise<{ providerJobId: string }>;

  /**
   * Reports job state. Must be answerable with no in-memory state from
   * the submitting isolate — Supabase Edge Function invocations do not
   * share memory, so an adapter that remembers jobs in a `Map` would
   * report "unknown job" for every poll that lands on a fresh isolate.
   */
  pollStatus(
    providerJobId: string,
    ctx: ProviderRequestContext,
  ): Promise<ImageGenerationResult>;
}
