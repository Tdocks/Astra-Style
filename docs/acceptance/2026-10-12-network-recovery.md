# API recovery acceptance — 2026-10-12

The shared API client now respects Retry-After on transient HTTP 429/5xx responses, accepting delta-seconds and HTTP-date values. Invalid hints retain the existing exponential backoff. Hints longer than 30 seconds surface the error instead of automatically waiting or retrying early. Subscription quota failures remain nonretryable.

Cancellation is checked before transport and before retry sleep; transport CancellationError is mapped to the existing cancelled category. A cancelled task cannot issue another retry even if an injected sleeper returns normally. Request and paid-call idempotency identities remain stable across retries.

Verification: targeted AstraAPIClientIdempotencyTests on iPhone 17 Pro Simulator, iOS 26.5, Xcode 27.0. `xcodebuild test` succeeded: 14 tests in one suite, including parameterized cooldown/invalid-hint cases, cancellation during backoff, recovery, retry exhaustion, renewed credentials and stable idempotency keys. Log: `/tmp/astra-network-recovery-20261012.log`. `git diff --check` passed.

This proves the shared client's simulated-response behavior. It does not close the connected journey's degraded-network acceptance or prove real carrier-network recovery. No new TestFlight build was uploaded.
