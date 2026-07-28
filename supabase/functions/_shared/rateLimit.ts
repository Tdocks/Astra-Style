// ============================================================================
// _shared/rateLimit.ts
// ============================================================================
// HONEST LIMITATION, stated plainly rather than hidden: this is an
// in-memory, per-isolate fixed-window limiter. It is NOT a durable,
// cross-instance rate limiter. Supabase Edge Functions run on Deno Deploy's
// isolate infrastructure — a single user's requests can land on different,
// independently-cold-started isolates (different regions, or the same
// region after a scale-to-zero cycle), each with its own empty `Map`. That
// means a determined caller could exceed the nominal limit by fanning
// requests out across isolates, and every isolate recycle silently resets
// everyone's counters to zero.
//
// This is what "implement what you can, rather than pretending" means in
// this slice: the vertical slice has no durable store provisioned (no Redis/
// Upstash, no dedicated Postgres rate-limit table in the migrations this
// function is scoped to touch — see docs/01-build-roadmap.md's exclusion
// list). A single-isolate in-memory limiter still does real, useful work
// (it catches a runaway client loop or a single hot isolate being hammered)
// and it costs nothing to deploy, but it must not be presented as a security
// boundary. Before this matters for abuse-resistance in production, replace
// it with a durable counter (a Postgres table + `SELECT ... FOR UPDATE`-free
// atomic upsert via an RPC, or an external store like Upstash Redis) behind
// this exact same `RateLimiter` interface — every call site in this codebase
// only depends on the interface below, not this implementation.
// ============================================================================

export interface RateLimitResult {
  allowed: boolean;
  /** Requests remaining in the current window if allowed, else 0. */
  remaining: number;
  /** Seconds until the window resets. Only meaningful when `!allowed`. */
  retryAfterSeconds: number;
}

export interface RateLimiter {
  check(key: string, nowMs: number): RateLimitResult;
}

export interface RateLimiterOptions {
  /** Maximum requests allowed per window, per key. */
  limit: number;
  /** Fixed window size, in milliseconds. */
  windowMs: number;
}

interface WindowState {
  count: number;
  windowStartMs: number;
}

/**
 * A fixed-window counter per key, held in a plain `Map`. Each call to
 * `createRateLimiter` owns an independent `Map` (no module-level shared
 * state), so tests can construct isolated limiters without cross-test
 * pollution, and a single deployed function instance holds exactly one of
 * these for its lifetime.
 */
export function createRateLimiter(options: RateLimiterOptions): RateLimiter {
  const { limit, windowMs } = options;
  if (limit <= 0) {
    throw new Error("RateLimiter limit must be a positive integer.");
  }
  if (windowMs <= 0) {
    throw new Error("RateLimiter windowMs must be a positive integer.");
  }

  const windows = new Map<string, WindowState>();

  return {
    check(key: string, nowMs: number): RateLimitResult {
      const existing = windows.get(key);

      if (!existing || nowMs - existing.windowStartMs >= windowMs) {
        windows.set(key, { count: 1, windowStartMs: nowMs });
        return { allowed: true, remaining: limit - 1, retryAfterSeconds: 0 };
      }

      if (existing.count < limit) {
        existing.count += 1;
        return { allowed: true, remaining: limit - existing.count, retryAfterSeconds: 0 };
      }

      const resetAtMs = existing.windowStartMs + windowMs;
      const retryAfterSeconds = Math.max(1, Math.ceil((resetAtMs - nowMs) / 1000));
      return { allowed: false, remaining: 0, retryAfterSeconds };
    },
  };
}
