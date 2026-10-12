# Postgres startup recovery and connected session journey

## Cause and fixes

Docker Desktop's backend was still listening on default Supabase ports 54321 and 54322
while the test ran in Colima. Local CLI database connections reached those stale listeners
rather than the disposable test stack. `lsof` confirmed the Desktop listeners.

The harness now allocates distinct available loopback ports for API, Postgres, shadow
database and provider stub. It preserves existing config sections and only changes local
port settings. Two config tests pass, including absent/existing section cases. The pinned
CLI is unchanged (2.120.0). Existing prepared `astra-local-qa` Colima profile uses 4 CPUs/
8 GiB memory and cached images; it is restarted instead of creating another default
2 GiB runtime. New memory preflight requires ≥6 GiB reported Docker memory. Disk preflight
requires 6 GiB when every needed pinned image is cached, otherwise 15 GiB.

The first runnable journey exposed missing fixture persistence. DEBUG loopback AppContainer
now uses a separate Keychain service per local API port, preserving the production namespace.
Fixture login persists there. On standard relaunch, the volatile QA SDK auth store is
rehydrated from those saved credentials, not the fixture file. The seeded profile is explicitly
onboarded. The UI test removes fixture-file access for relaunch and scrolls the closet grid
to assert each owned item. Production SDK persistence behavior is unchanged.

## Passed acceptance

On iPhone 17 Pro Simulator, iOS 26.5:

1. Fixture login reaches Home using local Supabase.
2. Terminate/relaunch restores saved-session Home without fixture reinjection.
3. Restored session loads the owner's three closet items.
4. Kyra creates an outfit; UI shows fixture garments.
5. Owner JWT reads persisted outfit and owned garment links; assistant history exists.
6. Mark Worn persists a wear row for that outfit/owner.
7. Prior-month Monthly Review excludes the newly recorded current-month wear.
8. Privacy & Data account deletion returns to sign-in; old JWT is rejected.
9. Harness independently confirms fixture user erasure, empty owned closet rows, and stack stop.

Connected run: **5 tests passed, zero failures/skips** (journey + privacy/factory checks).
Final separate auth regressions: **25 passed, zero failures/skips**. Two Python port/config
tests pass. Strict SwiftLint and diff checks pass. Future harness runs also select the auth
suites automatically. Evidence JSON files adjacent to this report; full connected xcresult:
`/var/folders/33/m31qjfnj3q90gwt7bntgjslc0000gn/T/astra-local-kyra-evidence-20731/LocalKyraAcceptance.xcresult`.

Earlier failed attempts remain recorded in `2026-10-12-auth-session-recovery.md`; this
later successful run supersedes its open startup blocker. No production Supabase or paid
provider calls were made. No TestFlight upload or commit in this pass.

## Limits

This starts from a seeded onboarded account and deterministic provider. It does not verify
Apple/email OTP UI login, onboarding, actual camera capture, live provider quality,
VoiceOver, degraded networking, expired-token live refresh or physical-device permissions.
The Supabase SDK emits its existing initial-session behavior advisory; the app's session
checks do not rely on that event as proof of validity. The complete master-plan journey
remains Partial for those separate criteria.

## Reuse

Start the prepared runtime with `colima start astra-local-qa`, then run
`python3 scripts/run_local_kyra_acceptance.py --journey`. New free ports are selected
per run. Keep cached runtime images to avoid repeated large pulls. The completed disposable
stack and its fixture credentials are removed by the harness.
