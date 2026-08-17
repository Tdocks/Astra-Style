// ============================================================================
// _shared/providers/mockImageGeneration.ts
// ============================================================================
// Deterministic `ImageGenerationProvider` for local development, Deno tests,
// and any deploy that has not flipped on the live OpenAI adapter. Writes a
// real (tiny, charcoal) PNG to the real result path so the client's signed
// URL fetch, the retention sweep, and the deletion path all exercise the
// same storage objects a live deploy produces — a mock that only *claims* a
// path would leave every downstream consumer untested against an object
// that exists.
//
// WHAT THE MOCK DOES NOT PRETEND: the placeholder is visibly not a
// photograph of anyone. This codebase's rule is that absent is honest and
// a confounded reading is not — a mock that returned a plausible-looking
// human render would be a fake generation indistinguishable from a real
// one, which is precisely the wrong property for the one feature whose
// whole §11 guardrail is "label what is generated." A flat grey square
// cannot be mistaken for a working feature.
//
// A provider swap must not change handler.ts, the wire DTO, or anything in
// ios/ — constructing this vs. the OpenAI adapter is `studio/index.ts`'s
// only job (ADR 0004).
// ============================================================================

import { ProviderError, type ProviderRequestContext } from "./types.ts";
import {
  type ImageGenerationProvider,
  type ImageGenerationRequest,
  type ImageGenerationResult,
  studioResultPath,
} from "./imageGeneration.ts";

/**
 * An 8×8 uniform charcoal PNG (74 bytes), pre-encoded so the mock needs no
 * image library and no network. Charcoal rather than transparent/white so a
 * viewport rendering it is unambiguous: something arrived, and it is
 * obviously not a person.
 */
const PLACEHOLDER_PNG_BASE64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR42mOQkpLBihiGlgQA0LEUAW7027IAAAAASUVORK5CYII=";

export function placeholderPngBytes(): Uint8Array {
  const binary = atob(PLACEHOLDER_PNG_BASE64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * The storage seam, injected by `studio/index.ts` (Supabase Storage in a
 * deploy, an in-memory map in tests). The mock is I/O-free by itself so
 * handler tests never touch a bucket.
 */
export interface MockImageGenerationDeps {
  readonly storeResult: (
    storagePath: string,
    bytes: Uint8Array,
    contentType: string,
  ) => Promise<void>;
  readonly resultExists: (storagePath: string) => Promise<boolean>;
}

/**
 * Stateless across calls on purpose — see
 * `ImageGenerationProvider.pollStatus`'s isolate warning. "Has the result
 * object landed at the deterministic path" IS the job state; no `Map` of
 * in-flight jobs exists to go stale.
 */
export class MockImageGenerationProvider implements ImageGenerationProvider {
  private readonly deps: MockImageGenerationDeps;

  constructor(deps: MockImageGenerationDeps) {
    this.deps = deps;
  }

  async submitGeneration(
    request: ImageGenerationRequest,
    ctx: ProviderRequestContext,
  ): Promise<{ providerJobId: string }> {
    if (request.prompt.trim().length === 0) {
      // A blank prompt upstream is a handler bug, not a user condition —
      // surface it the way a live vendor would (as a rejected payload)
      // so the mock path exercises the same failure branch.
      throw new ProviderError("INVALID_INPUT", false, "Mock provider received an empty prompt.");
    }
    const path = studioResultPath(ctx.userId, request.generationId);
    await this.deps.storeResult(path, placeholderPngBytes(), "image/png");
    // The generation id doubles as the provider job id: deterministic, and
    // it lets pollStatus recover the result path with no shared state.
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
    // submitGeneration writes the object before returning, so a poll for a
    // job the handler marked "generating" that finds nothing means the
    // object was lost (or the submit never really happened). Saying
    // "generating" here would poll forever against a job that cannot
    // finish; a retryable failure tells the user the truth and preserves
    // their prompt for a retry (§21).
    return {
      status: "failed",
      resultStoragePath: null,
      providerJobId,
      errorMessage: "mock_result_missing",
      isRetryableFailure: true,
    };
  }
}
