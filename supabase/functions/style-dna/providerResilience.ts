import type {
  StylistCompletionRequest,
  StylistCompletionResult,
  StylistReasoningProvider,
} from "../_shared/providers/stylistReasoning.ts";
import { ProviderError, type ProviderRequestContext } from "../_shared/providers/types.ts";

export interface ProviderResilienceOptions {
  readonly now?: () => number;
  readonly random?: () => number;
  readonly sleep?: (milliseconds: number) => Promise<void>;
  readonly failureWindowMs?: number;
  readonly openAfterFailures?: number;
  readonly openDurationMs?: number;
}

const delay = (milliseconds: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, milliseconds));

/**
 * Applies docs/08 §0.1's single transient retry and per-isolate circuit breaker
 * to a provider call. Failures remain provider failures; this wrapper never
 * substitutes deterministic content for an unsuccessful live response.
 */
export class ResilientStylistProvider implements StylistReasoningProvider {
  private readonly now: () => number;
  private readonly random: () => number;
  private readonly sleep: (milliseconds: number) => Promise<void>;
  private readonly failureWindowMs: number;
  private readonly openAfterFailures: number;
  private readonly openDurationMs: number;
  private failures: number[] = [];
  private openedAt: number | null = null;
  private probeInFlight = false;

  constructor(
    private readonly inner: StylistReasoningProvider,
    options: ProviderResilienceOptions = {},
  ) {
    this.now = options.now ?? Date.now;
    this.random = options.random ?? Math.random;
    this.sleep = options.sleep ?? delay;
    this.failureWindowMs = options.failureWindowMs ?? 60_000;
    this.openAfterFailures = options.openAfterFailures ?? 5;
    this.openDurationMs = options.openDurationMs ?? 30_000;
  }

  async complete(
    request: StylistCompletionRequest,
    ctx: ProviderRequestContext,
  ): Promise<StylistCompletionResult> {
    const probe = this.admitCall();
    try {
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          const result = await this.inner.complete(request, ctx);
          this.recordSuccess();
          return result;
        } catch (error) {
          const providerError = normalizeProviderError(error);
          this.recordFailure();
          if (attempt === 0 && providerError.retryable) {
            // Full jitter over the §0.1 first exponential-backoff slot.
            await this.sleep(Math.max(0, Math.min(1, this.random())) * 250);
            continue;
          }
          throw providerError;
        }
      }
      throw new ProviderError("UNKNOWN", false, "Stylist provider did not complete.");
    } finally {
      if (probe) this.probeInFlight = false;
    }
  }

  completeStream(
    request: StylistCompletionRequest,
    ctx: ProviderRequestContext,
  ): AsyncIterable<{ delta: string; toolCallDelta?: unknown }> {
    return this.inner.completeStream(request, ctx);
  }

  private admitCall(): boolean {
    const now = this.now();
    this.failures = this.failures.filter((at) => now - at <= this.failureWindowMs);
    if (this.openedAt === null) return false;
    if (now - this.openedAt < this.openDurationMs) {
      throw circuitOpenError();
    }
    if (this.probeInFlight) throw circuitOpenError();
    this.probeInFlight = true;
    return true;
  }

  private recordFailure(): void {
    const now = this.now();
    this.failures = this.failures.filter((at) => now - at <= this.failureWindowMs);
    this.failures.push(now);
    if (this.failures.length >= this.openAfterFailures) this.openedAt = now;
  }

  private recordSuccess(): void {
    this.failures = [];
    this.openedAt = null;
  }
}

function normalizeProviderError(error: unknown): ProviderError {
  if (error instanceof ProviderError) return error;
  return new ProviderError(
    "PROVIDER_UNAVAILABLE",
    true,
    "Stylist provider transport failed.",
  );
}

function circuitOpenError(): ProviderError {
  return new ProviderError(
    "PROVIDER_UNAVAILABLE",
    true,
    "Stylist provider circuit is open.",
  );
}
