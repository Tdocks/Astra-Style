# Master §30 acceptance matrix

**Audit date:** 2026-10-09  
**Scope:** the fourteen user-visible steps in `docs/00-master-spec.md` §30 and the cross-cutting appearance, accessibility, network, and provider-credential conditions. This reconciles simulator evidence and the new connected hosted backend run documented in `2026-10-09-connected-live-lifecycle.md`.

## Evidence labels

- **Simulator (mock):** the named UI flow ran against deterministic mock data. It does not prove hosted persistence or a live provider response.
- **Hosted, focused:** an opt-in backend harness exercised a specific route with disposable synthetic data. It does not prove the native client journey.
- **Hosted, connected:** onboarding, an owned Kyra outfit, wear, review, export and deletion ran sequentially on one disposable account. This still does not prove the native journey.
- **Open:** the full acceptance criterion has no recorded end-to-end proof.

## Fourteen-step flow

| §30 | User action | Existing coverage and evidence | Remaining acceptance |
|---:|---|---|---|
| 1 | Install the app | **Partial.** `START_HERE.md` records version 1.0.0 build 32 as VALID/IN_BETA_TESTING with internal membership and notes verified. This is internal distribution evidence, not proof of installation on a physical device. | Install the current approved build from TestFlight on a physical device and launch it as a new user. |
| 2 | Sign in | **Partial.** `ScreenQAUITests.testEmailAuthSheet` checks the auth sheet. It does not complete a real signed-in session and restore against hosted Auth. | Sign in with a dedicated QA credential and verify relaunch restores the same account. |
| 3 | Complete onboarding | **Simulator (mock).** `AstraStyleUITests.testCompleteOnboarding`; `OnboardingFlowUITests.testWalkTheWholeFlow` and `testWalkTheFullDeferredFlow` cover the user-facing onboarding and Style DNA route with test fixtures. The connected hosted run also verified the onboarding completion timestamp and stored profile state. | Complete onboarding on the signed-in QA account and verify the hosted profile state. |
| 4 | Receive coherent Style DNA | **Partial.** The Style DNA UI tests verify the rendered sections and regeneration behavior. They do not establish a human quality review of the recommendations. | Review a real result for coherence and verify hosted persistence. |
| 5 | Scan at least five garments | **Open.** `OnboardingFirstItemsUITests.testAddingAFirstItem` covers one first-item path; scanner capture and analysis have unit and focused hosted coverage. No acceptance run saves five distinct captures through the device flow. | Capture/import, analyze, and save five distinct garments on a camera-capable device; verify they are available to subsequent steps. |
| 6 | Correct analysis metadata | **Open.** Scanner metadata editing is implemented and unit-tested, but there is no recorded acceptance flow correcting a scanner result and carrying it into outfit generation. | Correct a field on an analyzed item, save it, and verify the corrected value persists and is used downstream. |
| 7 | Receive three outfits made from owned items | **Simulator (mock).** `AstraStyleUITests.testGenerateOutfit` opens the closet outfit builder, asserts exactly three recommendations and owned garment names, selects one, verifies the canvas, and saves it. The separate hosted builder acceptance verifies owner-scoped completion, locked pieces, and persistence. | Verify the complete three-outfit path with the signed-in device account's actual closet. |
| 8 | Ask Kyra what to wear for an occasion | **Simulator (mock) and hosted, focused.** `AstraStyleUITests.testAskKyra` covers the UI. `kyra/hosted_builder_completion_acceptance.ts` verifies a bounded live builder-completion request; Monthly Review and memory have separate hosted harnesses. The new connected hosted lifecycle also generated one owned outfit from a locked garment on the same disposable account; the full native §30 flow remains open. | Ask one occasion question using the same QA account and verify the answer reflects its owned closet/context. Provider request requires an approved bounded cost. |
| 9 | Mark an outfit worn | **Simulator (mock).** `AstraStyleUITests.testMarkOutfitWorn` marks an outfit and verifies Monthly Review shows one wear. The connected hosted run verified exact wear-count increments and prior-month date boundaries; focused Monthly Review acceptance separately covers richer facts. | Verify the same signed-in account's wear persists and appears in its review. |
| 10 | Paste a retailer link and receive a verdict | **Simulator (mock).** `ProductLinkFlowUITests.testPastedProductReachesVerdictAndCanBeSaved` covers invalid/valid URL entry, verdict display, and saving. `products/live_evaluation_acceptance.ts` separately evaluates a seeded duplicate candidate; it does not fetch a retailer or run extraction. | Exercise a controlled real retailer link and the production extraction/evaluation path, with visible handling for unavailable links. |
| 11 | Generate a visual styling estimate | **Simulator (mock) and hosted, focused.** Home estimate and Studio flows have UI tests; hosted Studio acceptance verifies a real provider result and private stored image. These are separate paths/accounts and do not establish a live estimate in the §30 account. | Generate one estimate from the QA account's selected outfit, review the result, and verify recovery behavior. This incurs image-provider cost and needs explicit approval. |
| 12 | Subscribe and restore | **Partial.** `AstraStyleUITests.testOpenPaywallAndRestorePurchases` exercises the local restore route. The sandbox purchase, renewal/cancel lifecycle, and signed Apple notification receipt are not proven by that mock/local test. | Use an App Store Connect sandbox tester to purchase, restore, renew/cancel, and verify server entitlement reconciliation. Keep signed Apple notification acceptance as its own check. |
| 13 | View or delete stored style memories | **Simulator (mock) and hosted, focused.** `AstraStyleUITests.testStyleMemoriesCanBeReviewedAndDeleted` checks UI removal. `kyra/live_memory_acceptance.ts` verifies hosted owner-scoped memory retrieval/deletion with a disposable account. | Review and delete a memory on the same signed-in §30 account, then verify it stays deleted. |
| 14 | Delete account and associated data | **Partial.** `AstraStyleUITests.testDeleteAccount` verifies the mock UI flow. Hosted disposable-account harnesses verify normal deletion and cleanup for specific populated fixture sets, including export, memory, Studio, and product flows. No one acceptance account has completed the full §30 journey and then been independently checked across all associated stores. | Delete the §30 QA account last; verify the deletion receipt completes, Auth identity is absent, owner rows and Storage objects are gone, and signing in again cannot restore prior data. |

## Cross-cutting conditions

| Condition | Existing evidence | Remaining acceptance |
|---|---|---|
| Light and dark appearance | Targeted screen and Studio flows cover both appearances. | Run the connected §30 flow in both appearances and review the resulting screens. |
| VoiceOver | Accessibility labels, identifiers, and large Dynamic Type tests exist. Large text does not prove VoiceOver operation. | Repeat the connected flow with VoiceOver enabled and record navigation, labels, and action outcomes. |
| Degraded network | Offline queue, reconnect, and startup-recovery suites cover component behavior. | Repeat the connected flow with a documented network profile and record user-visible recovery at each interruption. |
| Provider credentials | Provider calls are routed through server functions in source. | Verify the distributed app bundle and runtime requests contain no provider key; confirm server-side provider configuration separately. |

## Existing serial UI tests

These tests provide component-flow coverage, not a single connected acceptance run:

1. Onboarding: `AstraStyleUITests.testCompleteOnboarding`, `OnboardingFlowUITests.testWalkTheWholeFlow`, `OnboardingFlowUITests.testWalkTheFullDeferredFlow`.
2. Closet and recommendations: `AstraStyleUITests.testAddGarment`, `AstraStyleUITests.testGenerateOutfit`, `AstraStyleUITests.testMarkOutfitWorn`.
3. Kyra: `AstraStyleUITests.testAskKyra`, `PersonalStyleFeatureUITests.testOutfitSpecificKyraChat`, `PersonalStyleFeatureUITests.testMonthlyReviewAndKyraReflection`.
4. Product link: `ProductLinkFlowUITests.testPastedProductReachesVerdictAndCanBeSaved`, `ProductLinkFlowUITests.testShopHistoryOpensSavedSnapshotAndRequiresRefreshOptIn`.
5. Estimates and Studio: `PersonalStyleFeatureUITests.testHomeStyleInspiration`, `PersonalStyleFeatureUITests.testHomeClosetBasedOutfit`, `AstraStyleUITests.testKyraQueuedPreviewOpensAndReturnsToChat`, `PersonalStyleFeatureUITests.testStudioHighResolutionExportConfirmationAndRecoveryDark`, `PersonalStyleFeatureUITests.testStudioHighResolutionExportConfirmationAndRecoveryLightAccessibility`.
6. Paywall, memory, and deletion: `AstraStyleUITests.testOpenPaywallAndRestorePurchases`, `AstraStyleUITests.testStyleMemoriesCanBeReviewedAndDeleted`, `AstraStyleUITests.testDeleteAccount`.

The iOS CI workflow includes the functional UI suites in serial simulator partitions. A passing CI artifact is required where a ticket specifies CI acceptance; CI does not substitute for camera, Apple sandbox, VoiceOver, or physical-device checks.

## Physical-device and owner-input checklist

- Provide a dedicated disposable QA account and a physical camera-capable iPhone. Do not use a personal or customer account; delete the QA account only after evidence has been recorded.
- Prepare five garments and permission to capture/import their photos. At least one must produce a field that the tester can correct and verify.
- Provide one controlled retailer URL and decide whether to authorize a live extraction/evaluation request. The existing seeded-candidate test does not exercise retailer fetching.
- A bounded live Kyra request was authorized and completed in the connected backend run. Native acceptance and a visual review of the same account’s Studio output remain open.
- Provide an App Store Connect sandbox tester and confirm subscription products, localization, and test availability before purchase/restore tests.
- For accessibility and reliability acceptance, enable VoiceOver for the second run and use a documented network-throttling profile for the third; preserve per-step results and failures.
- Before external submission, owner/counsel must supply the verified legal entity/seller name, support contact and URL, approved privacy policy and retention/provider disclosures, final App Privacy answers, age rating, categories, copyright, availability, and any required privacy-choice URL. Do not infer or publish missing legal/contact information from draft copy.
- Capture and review actual screenshots from the release candidate; do not use mock-provider imagery as evidence of live output quality.
