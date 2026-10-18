# ADR 0047: App Store signed data on the hosted Edge runtime

Status: Accepted, 2026-10-12.

The deployed Supabase Edge runtime uses Deno 2.1.4. Apple's pinned Node server
library 3.1.0 fails there because X509Certificate.toString, raw, infoAccess and
verify are unimplemented. Its JWT dependency also rejects the runtime's EC curve
alias; node:crypto verification mishandles the raw P1363 signature option.
Current local Deno does not expose these failures.

Use a request-scoped SignedDataVerifier subclass. Preserve Apple's payload
validators, chain signatures, Apple certificate OIDs, expiry checks, application
identifier checks and environment checks. Supply the missing certificate methods
using jsrsasign 11.1.5, already a pinned transitive dependency of Apple's library,
now explicitly imported. Verify ES256 JWS with WebCrypto, enforcing P-256 and a
64-byte raw signature. Retain optional JWT expiry/not-before enforcement.

The OCSP routine mirrors Apple's 3.1.0 implementation with native fetch and
adapted responder certificates. It verifies issuer/delegated responder authority,
OCSP signing purpose and validity, signed response integrity, matching certificate
ID, good revocation status, and update dates with Apple's one-minute skew.
It rejects invalid dates and treats network failures as retryable. Online checks
remain enabled in both sandbox and production. No global crypto prototype is
modified, and no verification fallback accepts unsigned data.

The maintenance cost is tracking Apple's protected APIs and OCSP routine whenever
the pinned library changes. Remove the adapter once the hosted runtime supports
the missing APIs and its EC/JWS behavior passes these fixtures. Tests include a
genuine Apple TEST fixture without customer/transaction data, altered signature
and payload, wrong app ID, and untrusted root. Run these on Deno 2.1.4 as well as
current Deno; verify online OCSP through a fresh hosted Apple TEST notification.

TestFlight is Apple's Sandbox environment. The acceptance script defaults to
sandbox and requires APP_STORE_SERVER_ENVIRONMENT=production to test a released
app. Production API access is unavailable before a production app release.
