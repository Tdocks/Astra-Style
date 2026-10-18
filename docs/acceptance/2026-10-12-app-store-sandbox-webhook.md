# App Store sandbox webhook acceptance — 2026-10-12

Apple accepted a fresh Sandbox TEST notification request using the active In-App
Purchase key provided by the owner, and Get Test Notification Status reported
`SUCCESS`. The callback reached the deployed Astra Style webhook, passed signed
data verification including online certificate revocation checks, and was
acknowledged without changing entitlements.

## Causes and corrections

- The acceptance script hardcoded Production. Astra Style has no production
  release, so Production returned 401 even with a valid key. TestFlight is Sandbox.
  The script now defaults to Sandbox, with an explicit environment option.
- Apple's Node verifier uses X509 APIs missing from hosted Deno 2.1.4, plus EC
  curve and raw-signature behavior incompatible with that runtime. The deployed
  webhook therefore rejected genuine notifications with 400. ADR 0047 records the
  compatibility adapter, retaining certificate-chain, Apple OID, expiry,
  revocation, P-256 signature, bundle ID and environment checks.
- The hosted certificate-library public-key conversion also rejected the key.
  Certificate signatures now use native crypto verification over the parsed
  signed certificate bytes; JWS signatures use WebCrypto.

The key file is stored privately outside the repository. Its contents, generated
API JWTs and notification-status tokens are not committed or logged.

## Evidence

- `app-store` ACTIVE v14, `verify_jwt=false` for Apple-signed webhook callbacks.
- `subscriptions` ACTIVE v11, `verify_jwt=true` for authenticated purchase sync.
- Fresh official Apple library request: Sandbox accepted, delivery result `SUCCESS`.
- Direct genuine TEST replay: HTTP 200, `received=true`, `result=ignored`.
- Altered-signature hosted callback: HTTP 400.
- Unauthenticated hosted purchase sync: HTTP 401.
- 30 targeted verifier, webhook and subscription tests passed on current Deno.
- Five signed-fixture security tests passed on Deno 2.1.4; CI now repeats them.
- Type checks, lint and diff whitespace checks passed.

This closes signed sandbox TEST delivery acceptance, not the entire purchase
lifecycle. Device sandbox purchase, renewal, cancellation, expiration, refund and
restore still require acceptance. Production delivery must be checked after a
production app release. No native app code or TestFlight build changed.

## Repository follow-up — 2026-10-18

The current local run passed 34 verifier/webhook/subscription tests and the full
backend suite passed 1,114 tests. Additional rejection cases cover truncated or
extra-segment JWS tokens, unsigned algorithms, malformed certificate arrays, and
a genuine Sandbox event presented to a Production verifier. Type checking,
formatting and lint passed. The test task grants read access only to the public
fixture directory in addition to its existing source-file allowlist. Hosted
Deno 2.1.4 CI remains a separate check; this follow-up did not send a fresh Apple
notification or exercise device purchases.
