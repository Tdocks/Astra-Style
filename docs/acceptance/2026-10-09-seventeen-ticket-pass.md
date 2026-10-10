# Seventeen-ticket completion pass — 2026-10-09

This pass implements and verifies the selected foundation, design, privacy,
Studio repository, and acceptance-test gaps. It does not establish physical
camera, VoiceOver, purchase, production image quality, or legal acceptance.
TestFlight build 32 predates these changes.

## Evidence available before final CI

- Signed simulator Swift Testing run: 1,190 tests across 187 suites passed.
  The unsigned test-host attempt failed Keychain access; signing restored the
  existing authentication tests without changing their production behavior.
- Onboarding, closet-generated outfit and mark-worn UI tests passed. Onboarding
  now reads back a persisted completion timestamp and repository write count.
- 64 image baselines cover eight major screens in light/dark appearance,
  default/AX3/AX5 populated states and default empty states. Recording and an
  independent comparison both passed; the comparator rejects a one-pixel change.
  Outfit Detail without a record renders its unavailable/not-found state.
  Loading-state snapshots are not included. See the separate visual audit for
  scope and findings.
- Staging compiled, with no first-party compiler warnings. The built executable
  contains none of the eight checked privileged credential identifiers and
  bundles third-party notices. Apple's App Intents metadata processor emits an
  advisory because this app does not link AppIntents; the log is not literally
  free of every tool warning.
- Backend: 1,090 tests passed; type checking, formatting and lint passed.
- Fifteen color tokens match named Asset Catalog assets; all 32 checked contrast
  pairs pass. UI convention checks cover 447 Swift files.

## Ticket evidence map

| Tickets | Implementation / acceptance evidence |
|---|---|
| P1-INFRA-01 | Eleven feature modules expose the required seven folders; legacy Slice diagnostics moved into App. Owner explicitly retired the obsolete empty-scaffold condition. |
| P1-INFRA-02 | Debug/Staging/Release configuration, ignored local secrets, built-binary credential check. |
| P1-DS-01 | Exact light/dark named color assets and token tests. |
| P1-DS-03 | Raw spacing lint and existing named size/radius/spacing tokens. |
| P1-DS-04 | Four component previews, destructive button variant, minimum touch targets. |
| P1-DS-05 | Measured launch instrumentation exists; supported physical-device 1.4-second acceptance remains open. |
| P1-DS-06 | Reduce Motion-aware hero/breathing/paging transitions and haptics audit. |
| P3-TEST-01 | Cost-per-wear, redundancy, offline replay regression coverage; actual updated CI required. |
| P4-TEST-04 | Generate/save and wear/review UI acceptance; actual updated CI required. |
| P5-TEST-02 | Disposable local Supabase Auth/PostgREST/Edge Function plus deterministic Responses provider; actual app UI and owned-item card assertions. Local deployment replaces staging with owner approval; updated dedicated CI required. |
| P6-STUDIO-12 | Shared bounded backoff policy and authenticated canonical deletion-route regression. |
| P7-PRIVACY-07 | All sixteen event types audited; string inputs allowlisted; raw_prompt/rawPrompt aliases redacted by the production logger. Synthetic production-equivalent log sample contains neither private prompt nor image URL. |
| P7-DS-01 | Critical screens at AX5 in both appearances; snapshot visual audit and simulator accessibility checks. Physical VoiceOver is a separate ticket. |
| P7-DS-03 | Accessible champagne for meaning-bearing text/strokes; verdict/confidence/laundry text indicators. |
| P7-INFRA-04 | Locked dependency inventory, bundled license notices and first-party compiler warning gate. Updated CI required. |
| P7-TEST-04 | Persisted onboarding completion readback; actual updated CI required. |
| P7-TEST-07 | Bundled 64 baselines, comparison and failure attachments; actual updated CI required. |

## Analytics privacy tradeoff

Retailers use four known catalog identifiers; other retailer strings serialize
as `other`. Unknown subscription identifiers also become `other`; unknown
feedback tags are discarded. This limits analytics detail intentionally so
user-supplied URLs, free text and email addresses cannot enter these properties.

## Connected local test correction

The first connected UI run reached Home and the composer but could not send.
Each local SDK client had a different in-memory auth store, leaving repositories
without the fixture session. The Debug-only local factory now shares its
process-only store; a regression checks cross-client storage. Production SDK
storage and hosted authentication are unchanged.

## Remaining acceptance gates

No ticket requiring CI is closed solely because a workflow or test exists.
The local Kyra run must execute (a skip fails the harness), render the seeded
items, remove the disposable account and rows, and stop its isolated stack.
The dedicated runner accepts only manually dispatched trusted main-branch code.
Credentials are temporary, owner-readable only, and excluded from evidence.
