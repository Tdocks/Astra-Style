# Scanner stream lifecycle recovery — 2026-10-18

## Fix

`LiveCaptureSessionController.stop()` finished its quality stream while holding
the same NSLock acquired by the stream's synchronous termination handler. That
could deadlock the capture queue when closing the scanner. Continuations are now
detached under the lock, then finished/resumed outside it.

Replacing a quality stream now finishes its previous subscriber. Each stream has
an identity, so termination of an older subscription cannot clear the replacement.
The termination handler retains a single strong reference while locking/unlocking.

## Verification

Existing iPhone 18 Pro / iOS 27.0 simulator, canonical `ios/build/DerivedData`:

- **10 passed, 0 failed, 0 skipped**: two new real-controller stream lifecycle
  tests and eight existing scanner capture state tests.
- New tests verify replacement completes the old subscriber, stopping completes
  the replacement, and a subsequent subscription can stop without a locked queue.
- No camera startup or permission request is needed for these stream/queue tests.
- Strict lint and diff whitespace checks passed.
- Evidence: `/tmp/astra-camera-lifecycle-20261018.xcresult`.

This is a code-path deadlock fix with simulator regression coverage. It is not a
new physical-camera acceptance run. The owner's device-test pause was respected;
no phone interaction, deployment or TestFlight upload occurred.
