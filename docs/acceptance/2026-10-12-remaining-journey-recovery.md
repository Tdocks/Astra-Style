# Remaining journey recovery — 2026-10-12

## Verified

Final combined iOS 27 / Xcode 27 run: **87 passed, zero failed/skipped**. This includes 77 Swift Testing cases, four live-adapter/local-StoreKit cases, and six UI cases. A final test-file-only split compiled and passed another 13 scanner tests. Twenty-seven backend verifier/webhook/subscription tests passed. Strict SwiftLint, test-partition checks and whitespace checks pass.

- Onboarding: walks the real first-run screens, injects a Style DNA failure, retries, displays the result and reaches Home. Existing unit cases cover offline first-item saves and interrupted reference uploads.
- Scanner: imports an actual representative garment image through Photos, queues a transient analysis failure, explicitly retries without replacing the upload, edits the garment, fails the first save, retries and returns to Closet. Unit cases cover stable identity, durable journals and batch recovery.
- Studio: failed generation recovers; consent/allowances/polling are covered by unit cases; the higher-resolution confirmation, completion and reopen UI flow also passes.
- Purchases: local Apple StoreKit engine + live native adapter verifies paid transaction delivery failure/retry, finish-after-acknowledgement, restore, renewal, cancellation retaining paid-period access, refund removal, and delayed Ask to Buy approval reaching the matching owner. No locally signed receipt is sent to hosted Supabase. User-initiated AppStore.sync remains enabled in production; the local test injects a no-op account-authentication sync.
- VoiceOver: the actual iOS 27 XCUIVoiceOverService enabled VoiceOver and recorded 12 spoken focus advances per screen on Home, Closet and Studio. Label/trait audits also pass on these screens, Studio output and purchase recovery. This is spoken simulator evidence, not a claim that the entire master-spec sequence was navigated with VoiceOver or on a physical phone.

## Corrections

1. Queued scanner analysis now exposes an explicit retry when a short backend outage leaves Wi-Fi connected. Its claim prevents overlapping manual/reconnect analysis. The queued block preserves its child accessibility controls.
2. Paid purchase activation failures retain the verified transaction and expose an activation retry. Plan buttons cannot start another purchase while delivery is pending. Restore reconciles all payloads chronologically, and inactive backend results cannot claim activation success.
3. Direct purchases finish only after backend acknowledgement. A session-scoped observer delivers verified delayed approvals/renewals and unfinished transactions on launch, account change and reconnect. Supported product, appAccountToken and returned subscription owner must match before automatic finishing. Legacy receipts without a token use explicit Restore.
4. Native restore ignores revoked, upgraded and expired receipts. Normal recovery UI tests enter ordinary CI feature shards. Speech tests stay separately selectable because they need Xcode/iOS 27; older compilers build the guarded skip path. Local StoreKit lifecycle cases explicitly skip when the runtime cannot activate the configured catalog.

## Evidence and repetition

- Combined result: `/tmp/astra-remaining-journey-final-20261012.xcresult`
- Combined log: `/tmp/astra-remaining-journey-final-20261012.log`
- Spoken transcripts: `/tmp/astra-voiceover-final-evidence/`
- Final split scanner regression: `/tmp/astra-scanner-extension-final-20261012.xcresult`
- Backend log: `/tmp/astra-purchase-backend-final-20261012.log`

Generate the reviewed project/package resolution, resolve an installed iOS 27 simulator, boot it, then seed `fixtures/vision-pilot/probe-shirt-prepared.jpg` with `xcrun simctl addmedia`. Run `xcodebuild test -project ios/AstraStyle.xcodeproj -scheme AstraStyle -destination id=<simulator> -parallel-testing-enabled NO` selecting `OnboardingFlowUITests/testWalkRecoversFromStyleDNAFailure`, `RemainingJourneyAcceptanceUITests`, `VoiceOverAcceptanceUITests`, `PersonalStyleFeatureUITests/testStudioHighResolutionExportConfirmationAndRecoveryDark`, and the `StoreKitLifecycleAcceptanceTests`, `PaywallRecoveryTests`, `ScannerReviewViewModelTests`, `StudioGenerationViewModelTests` and `StudioPollingPolicyTests` unit suites. The normal CI fixture seeding already covers photo import.

## Still required

Forced-expiration simulation is **not verified**. In the failed local probes, SKTestTransaction.expirationDate changed to the current time, while the native signed receipt retained a future expiry and Product.SubscriptionInfo.status still returned subscribed. Accelerated-clock and cancellation-ID variants did not establish reliable expiration. See `/tmp/astra-storekit-status-20261012.xcresult` and its log. Do not interpret the independent passing lifecycle cases as an expiration pass; server-inactive entitlement rejection is covered separately.

The UI recovery cases use deliberately failing mock repositories; they supplement the preceding real local-Supabase connected journey and do not constitute one continuous hosted-provider §30 run. Real camera capture, Apple sandbox device purchases/expiration, and complete physical-device VoiceOver gestures remain required. No backend deployment or TestFlight upload was performed in this batch. P7-TEST-08 remains Partial.
