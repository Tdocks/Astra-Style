# Connected degraded-network acceptance — 2026-10-12

Result: PASS. The local connected journey ran against disposable Supabase with a deterministic Kyra provider, 150 ms added latency on each app request, and a loopback-only fault proxy. No paid provider was called. The fixture account, rows and isolated stack were removed and verified.

Flow: persisted-session relaunch → cached owner closet through a failed read → failed Kyra send and explicit retry → persisted outfit/message → wear after a committed response was dropped → second wear after all four API attempts fail → durable queue replay across relaunch, with its committed response also dropped → another relaunch/reconciliation → Monthly Review → failed initial deletion and automatic recovery → revoked session.

The test requires every fault to be consumed: seven HTTP 503 responses and two dropped successful write responses across six rules. Both dropped-response paths must actually retry. Exactly two intentional wears remain two rows after retries and relaunches. An independent owner-JWT database read confirmed garment wear counts [2, 2, 2]. Kyra produces one outfit and one assistant message. The review keeps current-month wears out of the prior month; deletion returns to sign-in and invalidates the old session.

## Fixes

- Wear writes keep a stable ID across HTTP attempts and offline fallback. Existing native clients receive a stable owner/request-derived identity on the server.
- Duplicate live inserts recover the existing caller-owned row through RLS, verify its fields, and avoid a second insert/trigger. Offline replay uses conflict-ignore insertion followed by a verified owner-scoped read.
- Postgres's empty weather object decodes as absent weather, preventing valid wear rows from becoming repeated requests or permanently queued replays. The endpoint also emits null for absent weather so existing native clients can decode its success response.
- The test waits for recovery to complete before checking row counts; a premature read could otherwise miss duplicates.

## Evidence

Final result: 56 simulator tests passed, zero failed/skipped (55 unit tests plus the connected UI journey). 37 Deno handler tests, backend type checking/lint, Python configuration checks, CI test partition check and diff checks passed.

- Result bundle: `/tmp/astra-degraded-network-final-20261012/degraded-network/LocalKyraAcceptance.xcresult`
- Cleaned-fixture report: `/tmp/astra-degraded-network-final-20261012/degraded-network/acceptance.json`
- Independent database check: `/tmp/astra-degraded-final-db-check.json`
- Backend test log: `/tmp/astra-wear-tests.log`
- Repeat command: `python3 scripts/run_local_kyra_acceptance.py --degraded-network`

The backward-compatible server changes were deployed to outfits v23, confirmed ACTIVE with JWT verification enabled; an unauthenticated record-wear request returns 401. Deployment requires `--import-map supabase/functions/deno.json` with the pinned CLI's API bundler. Native fixes await the next app release; no TestFlight build was uploaded.

## Scope

This is the connected signed-in flow with seeded closet items and a deterministic provider. It does not execute the entire master-spec §30 sequence: first-time onboarding, scanner/provider accuracy, retailer verdict, Studio generation, purchases/restore and VoiceOver remain separate acceptance requirements. P7-TEST-08 stays Partial. It also does not establish behavior on a real carrier network.
