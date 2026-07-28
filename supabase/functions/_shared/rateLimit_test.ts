import { assertEquals } from "@std/assert";
import { createRateLimiter } from "./rateLimit.ts";

Deno.test("allows requests up to the limit within the window", () => {
  const limiter = createRateLimiter({ limit: 3, windowMs: 1000 });
  const now = 1_000_000;
  assertEquals(limiter.check("user-a", now).allowed, true);
  assertEquals(limiter.check("user-a", now + 10).allowed, true);
  assertEquals(limiter.check("user-a", now + 20).allowed, true);
});

Deno.test("rejects the request that exceeds the limit within the window", () => {
  const limiter = createRateLimiter({ limit: 2, windowMs: 1000 });
  const now = 2_000_000;
  assertEquals(limiter.check("user-b", now).allowed, true);
  assertEquals(limiter.check("user-b", now + 1).allowed, true);
  const third = limiter.check("user-b", now + 2);
  assertEquals(third.allowed, false);
  assertEquals(third.remaining, 0);
  assertEquals(third.retryAfterSeconds > 0, true);
});

Deno.test("resets after the window elapses", () => {
  const limiter = createRateLimiter({ limit: 1, windowMs: 1000 });
  const now = 3_000_000;
  assertEquals(limiter.check("user-c", now).allowed, true);
  assertEquals(limiter.check("user-c", now + 500).allowed, false);
  assertEquals(limiter.check("user-c", now + 1000).allowed, true);
});

Deno.test("tracks separate keys independently", () => {
  const limiter = createRateLimiter({ limit: 1, windowMs: 1000 });
  const now = 4_000_000;
  assertEquals(limiter.check("user-d", now).allowed, true);
  assertEquals(limiter.check("user-e", now).allowed, true);
  assertEquals(limiter.check("user-d", now).allowed, false);
});

Deno.test("two independent limiter instances do not share state", () => {
  const limiterA = createRateLimiter({ limit: 1, windowMs: 1000 });
  const limiterB = createRateLimiter({ limit: 1, windowMs: 1000 });
  const now = 5_000_000;
  assertEquals(limiterA.check("same-key", now).allowed, true);
  assertEquals(limiterB.check("same-key", now).allowed, true);
});
