# Studio tests

This directory records test ownership for the Studio feature. Executable test sources remain in the shared `ios/AstraStyle/Tests/UnitTests` and `UITests` targets so XcodeGen continues using the existing targets and shared support.

Current related test sources:

- [`MockStudioHighResolutionExportTests.swift`](../../../Tests/UnitTests/MockStudioHighResolutionExportTests.swift)
- [`StudioComparisonViewModelTests.swift`](../../../Tests/UnitTests/StudioComparisonViewModelTests.swift)
- [`StudioEstimateExportTests.swift`](../../../Tests/UnitTests/StudioEstimateExportTests.swift)
- [`StudioGenerationViewModelTests.swift`](../../../Tests/UnitTests/StudioGenerationViewModelTests.swift)
- [`StudioHighResolutionExportTests.swift`](../../../Tests/UnitTests/StudioHighResolutionExportTests.swift)
- [`StudioHomeViewModelTests.swift`](../../../Tests/UnitTests/StudioHomeViewModelTests.swift)
- [`StudioImageDescriptionTests.swift`](../../../Tests/UnitTests/StudioImageDescriptionTests.swift)
- [`StudioLookbookTests.swift`](../../../Tests/UnitTests/StudioLookbookTests.swift)
- [`StudioPresetGalleryUITests.swift`](../../../Tests/UITests/StudioPresetGalleryUITests.swift)

Add new tests to the existing target and update this index. `project.yml` excludes the feature documentation from the application bundle.
