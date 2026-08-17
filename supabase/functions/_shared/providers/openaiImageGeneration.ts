// ============================================================================
// _shared/providers/openaiImageGeneration.ts
// ============================================================================
// Live `ImageGenerationProvider` adapter — OpenAI `gpt-image-1.5` via
// `POST /v1/images/edits`, per the decision record in `docs/08` §3.5
// (chosen on measured identity retention, 78.5% ±1.6 at n=3; deliberately
// NOT `gpt-image-2`, which measured worse on the axis Studio lives on).
// Constructed ONLY from `studio/index.ts` when
// `IMAGE_GENERATION_PROVIDER=openai` and `IMAGE_PROVIDER_API_KEY` are set.
// Never imported by handlers or tests that should stay offline, and — as
// of this writing — NEVER INVOKED: the key is not set on the project
// (supabase/README.md) and the default provider is the mock. This file
// exists so flipping the env var is the whole deployment story.
//
// HOW A SYNCHRONOUS VENDOR FITS AN ASYNC PROTOCOL. OpenAI's image API has
// no job object, no webhook, no poll endpoint — the HTTP response IS the
// image. So `submitGeneration` here does the entire render: call OpenAI,
// decode the base64 result, persist it to the deterministic
// `studioResultPath`, return. `pollStatus` then answers from storage
// alone ("has the object landed"), which keeps it honest across isolates
// with zero shared state. The studio handler already calls
// `submitGeneration` from the status-poll path (not the generate request)
// precisely so this blocking call never holds `POST /studio/generate`
// open — see `studio/handler.ts`.
//
// THE KEY IS `IMAGE_PROVIDER_API_KEY` — spec §25's per-capability naming,
// same scheme (and same six-weeks-of-silent-mock lesson) as
// `VISION_PROVIDER_API_KEY` in `closet/index.ts`. This layer does not know
// it is talking to OpenAI; the vendor name appears in this file and
// `studio/index.ts`'s selection switch, nowhere else.
// ============================================================================

import { ProviderError, type ProviderRequestContext } from "./types.ts";
import {
  type ImageGenerationProvider,
  type ImageGenerationRequest,
  type ImageGenerationResult,
  studioResultPath,
} from "./imageGeneration.ts";

export interface OpenAIImageGenerationDeps {
  readonly apiKey: string;
  /**
   * Pinned model string. `docs/08` §3.5: "Pin the model string explicitly,
   * and re-measure on docs/15 §3a's protocol before moving to another one,
   * in either direction." Newest measured WORSE here — do not bump this
   * because a newer model exists.
   */
  readonly model: string;
  /** Resolves a private storage path to image bytes the vendor can read. */
  readonly loadImageBytes: (storagePath: string) => Promise<Uint8Array>;
  readonly storeResult: (
    storagePath: string,
    bytes: Uint8Array,
    contentType: string,
  ) => Promise<void>;
  readonly resultExists: (storagePath: string) => Promise<boolean>;
  readonly fetchImpl?: typeof fetch;
}

const OPENAI_IMAGES_EDITS_URL = "https://api.openai.com/v1/images/edits";

/**
 * Portrait 1024×1536 — the §6.17 viewport is portrait editorial, and it is
 * the size `docs/16` §3.5's pricing (and therefore §13's cost controls)
 * are modelled on.
 */
const PORTRAIT_SIZE = "1024x1536";

/**
 * §13's draft-before-hi-res lever, priced at `docs/16` §3.5 list rates for
 * gpt-image-1.5 portrait: medium $0.050 (the $0.05/generation planning
 * rate), high $0.200. "low" ($0.013) was considered for draft and
 * rejected: `docs/11` risk 4 is Studio output that looks wrong or uncanny,
 * and a visibly cheap draft of the user's own face is that risk on
 * purpose. Medium draft / high export keeps the 4× saving while both
 * tiers stay presentable.
 */
function qualityFor(resolution: "draft" | "hi_res"): "medium" | "high" {
  return resolution === "draft" ? "medium" : "high";
}

interface OpenAIErrorBody {
  error?: { message?: string; code?: string; type?: string };
}

function mapOpenAIError(httpStatus: number, body: OpenAIErrorBody | null): ProviderError {
  const code = body?.error?.code ?? "";
  // Moderation rejections arrive as HTTP 400 with a dedicated code, not a
  // distinct status — mapping by code keeps them out of the retry path
  // (§21: a moderation rejection is never auto-retried).
  if (code === "moderation_blocked" || code === "content_policy_violation") {
    return new ProviderError(
      "CONTENT_MODERATION_REJECTED",
      false,
      "Provider content moderation rejected the reference image or prompt.",
      httpStatus,
    );
  }
  if (httpStatus === 401 || httpStatus === 403) {
    return new ProviderError("AUTH_FAILED", false, "Provider rejected credentials.", httpStatus);
  }
  if (httpStatus === 400 || httpStatus === 404 || httpStatus === 422) {
    return new ProviderError(
      "INVALID_INPUT",
      false,
      "Provider rejected the request payload.",
      httpStatus,
    );
  }
  if (httpStatus === 429) {
    // OpenAI uses 429 for both rate limits and exhausted billing quota;
    // `insufficient_quota` is Astra's own account problem, not load.
    if (code === "insufficient_quota") {
      return new ProviderError(
        "PROVIDER_QUOTA_EXCEEDED",
        false,
        "Provider account quota exhausted.",
        httpStatus,
      );
    }
    return new ProviderError("RATE_LIMITED", true, "Provider rate limit hit.", httpStatus);
  }
  if (httpStatus >= 500) {
    return new ProviderError(
      "PROVIDER_UNAVAILABLE",
      true,
      "Provider returned a server error.",
      httpStatus,
    );
  }
  return new ProviderError(
    "UNKNOWN",
    false,
    `Unmapped provider error (HTTP ${httpStatus}).`,
    httpStatus,
  );
}

function decodeBase64(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export class OpenAIImageGenerationProvider implements ImageGenerationProvider {
  private readonly deps: OpenAIImageGenerationDeps;

  constructor(deps: OpenAIImageGenerationDeps) {
    this.deps = deps;
  }

  /** Exported-shape seam for tests: builds the multipart form, no I/O. */
  buildForm(request: ImageGenerationRequest, referenceBytes: Uint8Array): FormData {
    const form = new FormData();
    form.set("model", this.deps.model);
    form.set("prompt", request.prompt);
    form.set("size", PORTRAIT_SIZE);
    form.set("quality", qualityFor(request.resolution));
    form.set("n", "1");
    // A fresh ArrayBuffer copy rather than the Uint8Array's own buffer:
    // the array may be a view into a larger buffer, and Blob would happily
    // upload the whole thing.
    form.set(
      "image",
      new Blob([new Uint8Array(referenceBytes).buffer], { type: "image/jpeg" }),
      "reference.jpg",
    );
    return form;
  }

  async submitGeneration(
    request: ImageGenerationRequest,
    ctx: ProviderRequestContext,
  ): Promise<{ providerJobId: string }> {
    const fetchImpl = this.deps.fetchImpl ?? fetch;
    const referenceBytes = await this.deps.loadImageBytes(request.referenceImageStoragePath);
    const form = this.buildForm(request, referenceBytes);

    let response: Response;
    try {
      response = await fetchImpl(OPENAI_IMAGES_EDITS_URL, {
        method: "POST",
        headers: { Authorization: `Bearer ${this.deps.apiKey}` },
        body: form,
        signal: AbortSignal.timeout(ctx.timeoutMs),
      });
    } catch (err) {
      if (err instanceof DOMException && err.name === "TimeoutError") {
        throw new ProviderError("TIMEOUT", true, "Provider request timed out.", undefined);
      }
      throw new ProviderError("PROVIDER_UNAVAILABLE", true, "Provider was unreachable.", undefined);
    }

    if (!response.ok) {
      let body: OpenAIErrorBody | null = null;
      try {
        body = await response.json() as OpenAIErrorBody;
      } catch {
        body = null;
      }
      throw mapOpenAIError(response.status, body);
    }

    const payload = await response.json() as { data?: Array<{ b64_json?: string }> };
    const b64 = payload.data?.[0]?.b64_json;
    if (!b64) {
      throw new ProviderError(
        "UNKNOWN",
        false,
        "Provider returned a response with no image data.",
        response.status,
      );
    }

    // Re-host before reporting success — spec §15/ADR 0010: results land
    // in Astra's own private bucket, never a provider URL, so retention
    // and deletion are single-prefix operations under Astra's control.
    const path = studioResultPath(ctx.userId, request.generationId);
    await this.deps.storeResult(path, decodeBase64(b64), "image/png");
    return { providerJobId: request.generationId };
  }

  async pollStatus(
    providerJobId: string,
    ctx: ProviderRequestContext,
  ): Promise<ImageGenerationResult> {
    const path = studioResultPath(ctx.userId, providerJobId);
    if (await this.deps.resultExists(path)) {
      return {
        status: "complete",
        resultStoragePath: path,
        providerJobId,
        errorMessage: null,
        isRetryableFailure: false,
      };
    }
    // Same reasoning as the mock: submit persists before returning, so a
    // "generating" row with no object means the render was lost. Failing
    // retryably (quota was never debited — §21) beats polling forever.
    return {
      status: "failed",
      resultStoragePath: null,
      providerJobId,
      errorMessage: "result_not_persisted",
      isRetryableFailure: true,
    };
  }
}
