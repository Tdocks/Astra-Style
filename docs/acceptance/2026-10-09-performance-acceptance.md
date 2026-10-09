# Performance acceptance — 2026-10-09

## Result

The opt-in performance UI suite passed on an iPhone 17 Pro simulator running iOS 26.5 (three tests, zero failures). This is diagnostic simulator evidence, not representative-device acceptance. The result bundle is `/tmp/astra-inspiration-build/Logs/Test/Test-AstraStyle-2026.10.09_01-34-22--0400.xcresult`; the run log is `/tmp/astra-performance-ui-verification-final.log`.

| §20 target | Simulator evidence | Assessment |
|---|---|---|
| Cold launch <2.5 s | `testColdLaunchToResponsiveHome`: 10 runs; `ApplicationFirstFramePresentationResponsive` mean 0.996 s (range 0.966–1.046 s). The app signpost `AppLaunchToInteractive` mean was 0.534 s (0.529–0.556 s). | Below target in this mock simulator run; device measurement remains open. |
| Cached Home render <500 ms | `testCachedHomeRender`: 10 `HomeCachedRender` signpost measurements; mean 0.083 s (0.076–0.106 s). | Below target in this mock simulator run; device measurement remains open. |
| Closet grid 60 fps | `testLargeClosetGridScrollHitchesAndMemory` traversed all 125 fixture tiles from newest to oldest and back in each of five iterations. Test case duration was 1,319.965 s. The result bundle contains memory metrics but no hitch metric samples. | Traversal passed; frame rate/hitch target is unmeasured. |
| Item analysis <8 s | Not measured in this run. | Open. |
| Kyra first token/card <2.5 s | Not measured in this run. | Open. |
| Draft Studio generation <30 s | Not measured in this run. | Open. |

The closet test's five `Memory Peak Physical` samples were 33,900.752, 33,573.072, 33,442, 34,097.36, and 33,704.144 kB (mean 33,743.466 kB; maximum 34,097.36 kB, about 34.1 MB). These are observed samples, not a validated memory bound. The bundle does not contain hitch counts or frame-rate measurements, so a passing test result must not be read as evidence that scrolling met 60 fps.

The fixture is synthetic and local-only: 125 closet records reuse eight bundled JPEGs through temporary local paths. It exercises grid traversal and image loading without a live account, network image fetches, or image-provider calls. The launch/Home tests use the mock backend and seeded cached Home data. Test definitions are in `ios/AstraStyle/Tests/UITests/PerformanceAcceptanceUITests.swift`; fixture and local resolver are in `ios/AstraStyle/Core/Mocks/PerformanceClosetFixture.swift` and `ios/AstraStyle/Core/Mocks/PerformanceClosetImageURLResolver.swift`.

## Remaining acceptance

Run the §20 measurements on a representative supported physical device. Capture and report a real closet scrolling hitch/frame-rate metric, then measure item analysis, Kyra first response, and draft Studio generation on their representative flows. Compare each measured value to the stated target; document a root cause and fix or an explicit accepted-risk note for any miss. Until then, P7-INFRA-02 remains Partial.
