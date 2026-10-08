# Runtime session renewal

## Implementation (8 October 2026)

`SessionStore` renews credentials before returning an expired or nearly expired
access token to the API client. Concurrent callers share one renewal. Production
uses the Supabase SDK's current session for the same identity, including refresh
tokens already rotated by SDK auto-refresh; the persisted refresh token is the
fallback when the SDK has no session. Refreshed credentials are persisted in
Keychain and the guest flag is retained.

A session revision prevents late refresh results from restoring an account after
sign-out, reset or replacement. A mismatched owner or invalid refresh credential
is rejected. Connectivity/server failures retain recoverable credentials instead
of erasing them. Launch restoration also rejects identity changes and retains
Keychain credentials when offline.

## Verification

- Initial eight session restoration/request tests passed in the simulator.
- Expanded ten-test suite passed, including concurrent renewal and late completion
  after in-memory sign-out.
- Final eleven-test suite passed, including offline launch recovery. Log:
  `/tmp/astra-session-tests3.log`; Swift strict concurrency compilation succeeded.
- Request-level Authorization coverage plus session and networking suites passed:
  19 tests across three suites (`/tmp/astra-session-final.log`).
- Kyra mock simulator conversation passed (`/tmp/astra-session-regression.log`);
  this does not prove hosted authentication rotation.
- Real-device background/foreground acceptance and hosted rotated-session
  integration remain pending. These tests do not establish full app readiness.

No server deployment is required for this client fix. TestFlight build 19 does
not contain it; the next native release must include it.

## Build 20 upload

Version 1.0.0 (20) archived at
`/Users/tylerdockswell/Library/Developer/Xcode/Archives/2026-10-08/AstraStyle 2026-10-08 19.46.52.xcarchive`.
The archive's bundle/version were verified. Fastlane confirmed upload success at
19:49:44 on 8 October 2026 (`/tmp/astra-testflight20.log`). Apple processing and
Internal group membership are not yet verified. Build 19 remains the confirmed
Internal release until those checks pass.
