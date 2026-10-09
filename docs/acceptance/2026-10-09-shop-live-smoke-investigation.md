# Shop live smoke investigation — 2026-10-09

## Live UI result

`PublicCutSmokeUITests.testGuestStrangerPath` failed in `/tmp/astra-combined-v5-studio-native-verification-4.log` after 304.249 seconds. The recorded assertion was “Shop should load catalog or empty, not hang.” The test did not capture an HTTP status or PostgREST error code. The UI's `.failed` state has no dedicated accessibility identifier, so the old assertion could not distinguish a rendered error state from a stale/missing catalog anchor. Discover navigation was attempted, but the log does not record a completed Discover assertion or endpoint status. This is not a passing live smoke test.

## Read-only Shop request check

A separate disposable anonymous session made the same read-only requests as Shop, using its caller JWT:

- Recent evaluations: HTTP 200, 0 rows (`user_product_evaluations`, caller-scoped; same 180-day window, ordering and range as `fetchRecentDecisions(limit: 20)`).
- Curated catalog: HTTP 200, 9 rows (`product_candidates?select=*&order=last_checked_at.desc`).
- No profile prerequisite is used by these Shop reads: the recent-history repository obtains the authenticated user ID, while the catalog is shared/read-only.

The live catalog has 9 rows, including one with `retailer IS NULL`. The database allows a nullable retailer (`product_candidates.retailer` has no `NOT NULL` constraint), while `ProductCandidate.retailer` was non-optional. Synthesized Codable decoding therefore rejects the full catalog response when it encounters that row. This is a concrete client/schema mismatch consistent with the failed Shop load, although the old test did not capture the app's underlying decode error.

An isolated native draft makes `retailer` optional, adds a label accessor, updates Shop/Product Decision/Discover to omit the label when unavailable, and tests decoding a catalog row with `retailer: null`. It is in `/tmp/astra-shop-smoke-draft`; it has only passed Swift parsing and strict SwiftLint so far. No simulator test or native producer ran for this draft.

## Disposable fixture cleanup

The original smoke account `43628909-4234-4600-94b4-f8c6df72a0a4` was verified as anonymous and matched the test-created Smoke Tee, Smoke Trousers, and Smoke Sneakers rows. Before cleanup it had zero Storage objects, Studio generations/submissions/allowances, closet analysis jobs/idempotency rows, cutout requests, and closet-item image records. No user JWT was available to invoke normal in-app deletion, so the explicitly authorized exact-ID AuthAdmin cleanup fallback was used. Its response was HTTP 200. Independent SQL readback confirmed zero auth user, identity/session, profile, garment, image, Studio, and Storage rows. This was administrative fixture cleanup, not an acceptance test of `DELETE /account`.

For the separate read-only Shop check, disposable anonymous user `7704575b-e774-42fd-903d-9408a7d09049` was deleted through its own `DELETE /account` request (HTTP 202). Independent SQL readback confirmed zero auth user, identity/session, profile, and Storage rows. That check made no garment/catalog writes and no provider requests.

## Remaining gate

The live guest smoke should be opt-in with `ASTRA_RUN_LIVE_SMOKE=1`; its teardown must delete the anonymous account through the product privacy flow and assert deletion was accepted. That harness change is drafted at `/tmp/astra-public-smoke-draft/ios/AstraStyle/Tests/UITests/PublicCutSmokeUITests.swift` and is not yet integrated. The live smoke remains open until the model fix is integrated and verified, Shop renders its catalog, and the Discover path records a complete result. Mock UI coverage does not replace this live-backend gate.
