# Home tests

This directory records test ownership for the Home feature. Executable test sources remain in the shared `ios/AstraStyle/Tests/UnitTests` and `UITests` targets so XcodeGen continues using the existing targets and shared support.

Current related test sources:

- [`DailyBriefDecodingTests.swift`](../../../Tests/UnitTests/DailyBriefDecodingTests.swift)
- [`HomeBriefEmptyReasonTests.swift`](../../../Tests/UnitTests/HomeBriefEmptyReasonTests.swift)
- [`HomeBriefProvidingTests.swift`](../../../Tests/UnitTests/HomeBriefProvidingTests.swift)
- [`HomeShareCopyTests.swift`](../../../Tests/UnitTests/HomeShareCopyTests.swift)
- [`HomeViewModelReliabilityTests.swift`](../../../Tests/UnitTests/HomeViewModelReliabilityTests.swift)
- [`HomeViewModelWeatherTests.swift`](../../../Tests/UnitTests/HomeViewModelWeatherTests.swift)
- [`HomeWeatherFreshnessLabelTests.swift`](../../../Tests/UnitTests/HomeWeatherFreshnessLabelTests.swift)
- [`HomeWeekStripTests.swift`](../../../Tests/UnitTests/HomeWeekStripTests.swift)
- [`InspirationViewModelTests.swift`](../../../Tests/UnitTests/InspirationViewModelTests.swift)
- [`ScheduleSnapshotBuilderTests.swift`](../../../Tests/UnitTests/ScheduleSnapshotBuilderTests.swift)
- [`WeatherSnapshotCacheTests.swift`](../../../Tests/UnitTests/WeatherSnapshotCacheTests.swift)

Add new tests to the existing target and update this index. `project.yml` excludes the feature documentation from the application bundle.
