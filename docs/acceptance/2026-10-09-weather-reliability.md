# Weather reliability — 2026-10-09

## Implemented

The existing owner-scoped disk cache was only consumed by Home. Closet outfit generation, Home inspiration and Kyra now use `currentReading()` as well. Last-known readings keep their original observation timestamp; the cache only returns this owner's same coarse region within two hours, with five minutes allowed future clock skew. Denied permissions and account changes fail closed; cancellation is not converted to fallback. Weather cache removal is wired through the existing authentication lifecycle.

Inspiration labels last-known weather in both its visible context summary and generation instructions. Builder instructions also distinguish last-known weather. Kyra's parser now preserves optional `observed_at`; its weather tool returns the original timestamp and age and rejects expired or implausibly future observations. Older clients without a timestamp remain compatible, with no claim that an observation was freshly fetched.

## Verification

- Signed simulator: 43 tests across weather cache, Home brief context, outfit weather encoding/context, calendar minimization and inspiration suites passed.
- Kyra backend: 160 tests passed, including saved observation age, stale/future rejection and backward-compatible parsing.
- Strict SwiftLint and changed-file diff checks passed.
- Kyra backend deployed through the project import map. No new TestFlight archive/upload.

## Still required

Physical-device WeatherKit, location denial/revocation and offline forecast behavior; actual calendar permissions/events. Cache fallback requires a fresh usable location for same-region matching: a failure to establish location does not reuse a potentially wrong-region forecast. No claim of physical-device acceptance or complete app readiness.
