# CI, Kyra and connected journey — 2026-10-10

## CI diagnosis and repair

Run 38011472659 passed 1,193 unit tests and all 17 core UI flows, but six populated Studio visual comparisons failed. Studio formatted its date directly with system defaults, ignoring the injected SwiftUI time zone. Reference images generated on the owner’s Mac therefore differed from the UTC CI runner.

The gallery now explicitly uses its environment locale, calendar and time zone. Only the six affected references changed. Local recording and independent comparison passed all 64 images; comparator negative controls passed. Pixel tolerance was not changed. Fresh GitHub acceptance: https://github.com/Tdocks/Astra-Style/actions/runs/38091270368 (pending).

## Kyra

Local backend/provider-stub CI run 38091038426 reached worker readiness but returned a server error. Account/row cleanup and stack shutdown passed. This is not a Kyra UI acceptance pass. The local worker is now verified ready. A local Kyra UI test and all three privacy checks passed, with fixture erasure and stack shutdown verified. The harness result parser was updated for the current human-readable test suite names. Hosted acceptance passed two real provider calls with `gpt-5.6-luna`, no fallback/provider failure: closet outfit (6.735 seconds), then casual refinement in the same thread (5.885 seconds). Both outfits persisted. Normal account deletion completed; independent SQL confirmed zero remaining owned rows. This verifies the hosted provider and persistence, not a hosted iOS UI pass.

## Connected journey

Connected GitHub CI [38092882030](https://github.com/Tdocks/Astra-Style/actions/runs/38092882030) passed on `4c6fb82e`: Kyra-created outfit, owned garment links and messages, saved-look navigation, recorded wear, prior-month Monthly Review, and real account deletion. The saved result bundle and acceptance report verify the test executed, privacy checks passed, fixture Auth was deleted, closet rows were empty, and the isolated stack stopped.

The journey exposed a missing Monthly Review entry in empty Home; the existing card is now rendered there. Other corrections were fixture discovery, scrolling and the confirmation-sheet selector. It uses a seeded signed-in fixture and deterministic provider; onboarding, camera capture, physical permissions, live image quality and the complete three-variant master-spec journey remain separate acceptance gates.

P5-TEST-02 is closed. Tracker: 139 done, 36 partial, 4 not started (40 open).

Build 33 remains installed through internal TestFlight for owner testing. These changes have not been uploaded in another build.
