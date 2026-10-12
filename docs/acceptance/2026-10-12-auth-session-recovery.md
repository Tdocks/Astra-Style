# Authentication recovery and connected journey — 2026-10-12

## Verified

Fixed a launch-restoration race: after the splash deadline cancels restoration, a late
refresher result must not persist or install credentials. SessionStore now checks task
cancellation alongside session revision after the awaited refresh. Recoverable stored
credentials remain available for a later retry.

Added regression coverage for offline launch followed by recovery, a pending launch restore
finishing after a new account signs in, and cancelled launch restoration finishing late.
Existing tests cover expired/rejected tokens, corrupt/absent Keychain state, concurrent
renewal, sign-out races and anonymous-session renewal.

`xcodebuild test` selected SessionRestoreTests and GuestAuthTests on iPhone 17 Pro Simulator
iOS 26.5. **25 passed, zero failures/skips**, including all three new cases. Result:
`/tmp/astra-auth-recovery-final-20261012.xcresult`; safe summary:
`2026-10-12-auth-session-recovery-results.json`. Strict SwiftLint and diff checks pass.

## Connected journey: implemented, not verified

Extended the existing connected UI journey to terminate/relaunch before Kyra, bypass fixture
credential reinjection, restore through standard app bootstrap, and prove the restored
owner can read the seeded closet. The bypass is DEBUG-only and keeps the loopback local
backend environment. Existing subsequent steps check persisted Kyra outfit ownership,
wear rows, prior-month review boundaries and UI account deletion/revocation.

Local backend startup failed before UI execution: initial Postgres connectivity failure;
retry exhausted local disk and failed; fresh runtime after cleanup still reported Postgres
connection termination. **No connected UI pass is claimed.** Added bounded redacted
infrastructure diagnostics and a 15 GiB startup disk-space preflight to avoid future
disk exhaustion. Python compilation passes. Temporary fixture credentials and test stacks
were cleaned by the harness; the disposable runtime/data were removed.

The deterministic local provider/seeded closet do not exercise real Apple sign-in,
onboarding, camera capture, live providers, degraded networking or VoiceOver. These remain
separate acceptance requirements. No TestFlight upload or commit was made in this pass.

## Follow-up resolved

Postgres startup and saved-session connected journey now pass; see
`2026-10-12-connected-session-journey.md` for cause, fixes and retained evidence.
