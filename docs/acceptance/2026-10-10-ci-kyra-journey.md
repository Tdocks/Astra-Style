# CI, Kyra and connected journey — 2026-10-10

## CI diagnosis and repair

Run 38011472659 passed 1,193 unit tests and all 17 core UI flows, but six populated Studio visual comparisons failed. Studio formatted its date directly with system defaults, ignoring the injected SwiftUI time zone. Reference images generated on the owner’s Mac therefore differed from the UTC CI runner.

The gallery now explicitly uses its environment locale, calendar and time zone. Only the six affected references changed. Local recording and independent comparison passed all 64 images; comparator negative controls passed. Pixel tolerance was not changed. Fresh GitHub run 38091270368 passed all 1,193 unit tests, all 17 core UI flows and its onboarding partition. Four remaining AX Studio comparisons differ only in the books toolbar glyph bounds; the original date/default-size differences are resolved. Targeted visual run 38093338640 confirmed that setting a font on the standard system-image button does not resolve the UIKit glyph size. Custom fixed-size image artwork within a separate 44-point hit target resolved the issue. Targeted visual CI [38094000757](https://github.com/Tdocks/Astra-Style/actions/runs/38094000757) passed on 75f98bad; local independent comparison passed as well. Comparison tolerance was never weakened.

## Kyra

Local backend/provider-stub CI run 38091038426 reached worker readiness but returned a server error. Account/row cleanup and stack shutdown passed. This is not a Kyra UI acceptance pass. The local worker is now verified ready. A local Kyra UI test and all three privacy checks passed, with fixture erasure and stack shutdown verified. The harness result parser was updated for the current human-readable test suite names. Hosted acceptance passed two real provider calls with `gpt-5.6-luna`, no fallback/provider failure: closet outfit (6.735 seconds), then casual refinement in the same thread (5.885 seconds). Both outfits persisted. Normal account deletion completed; independent SQL confirmed zero remaining owned rows. This verifies the hosted provider and persistence, not a hosted iOS UI pass.

## Connected journey

Connected GitHub CI [38092882030](https://github.com/Tdocks/Astra-Style/actions/runs/38092882030) passed on `4c6fb82e`: Kyra-created outfit, owned garment links and messages, saved-look navigation, recorded wear, prior-month Monthly Review, and real account deletion. The saved result bundle and acceptance report verify the test executed, privacy checks passed, fixture Auth was deleted, closet rows were empty, and the isolated stack stopped.

The journey exposed a missing Monthly Review entry in empty Home; the existing card is now rendered there. Other corrections were fixture discovery, scrolling and the confirmation-sheet selector. It uses a seeded signed-in fixture and deterministic provider; onboarding, camera capture, physical permissions, live image quality and the complete three-variant master-spec journey remain separate acceptance gates.

P5-TEST-02 is closed. Tracker: 143 done, 33 partial, 3 not started (36 open). Closet unit and outfit/wear UI CI checks and onboarding are closed; connected end-to-end coverage is Partial.

Build 33 remains installed through internal TestFlight for owner testing. These changes have not been uploaded in another build.

## Feature CI reliability

The original feature partition hit its 45-minute time limit. Five image-flow assertions also raced quota loading or matched the pre-action enabled state. They now wait for actual allowance data, visible generation progress, completed image, and the enabled action. All five focused tests passed locally. Feature coverage is split into two deterministic method groups (24 and 23); the checker proves complete non-overlapping coverage and separately reserves controlled performance/local acceptance. CI run [38094514985](https://github.com/Tdocks/Astra-Style/actions/runs/38094514985) completed: features passed (24 executed, one intentional skip, zero failures); features-extra failed three generation flows. The literal initial allowance text identified a preparation/session race rather than a quota response failure. Inspiration now keeps nil-owner and cancelled preparation retryable, restarts preparation when the signed-in owner arrives, and invalidates existing context only when the owner actually differs. It retains owner checks before private data/provider access. All three failed UI cases and all 12 Inspiration view-model tests passed locally on iOS 26.5. The correction is committed as `4e7aff7b`; feature CI [38096410603](https://github.com/Tdocks/Astra-Style/actions/runs/38096410603) is pending. Build 33 does not contain this correction.
