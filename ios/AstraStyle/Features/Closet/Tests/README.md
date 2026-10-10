# Closet tests

This directory records test ownership for the Closet feature. Executable test sources remain in the shared `ios/AstraStyle/Tests/UnitTests` and `UITests` targets so XcodeGen continues using the existing targets and shared support.

Current related test sources:

- [`ClosetBasedPreviewUITestDriver.swift`](../../../Tests/UITests/ClosetBasedPreviewUITestDriver.swift)
- [`ClosetCaptureUploadPipelineTests.swift`](../../../Tests/UnitTests/ClosetCaptureUploadPipelineTests.swift)
- [`ClosetCareInstructionsPersistenceTests.swift`](../../../Tests/UnitTests/ClosetCareInstructionsPersistenceTests.swift)
- [`ClosetColorSpectrumOrderTests.swift`](../../../Tests/UnitTests/ClosetColorSpectrumOrderTests.swift)
- [`ClosetEmptyReasonTests.swift`](../../../Tests/UnitTests/ClosetEmptyReasonTests.swift)
- [`ClosetFiltersTests.swift`](../../../Tests/UnitTests/ClosetFiltersTests.swift)
- [`ClosetGridImageResolutionTests.swift`](../../../Tests/UnitTests/ClosetGridImageResolutionTests.swift)
- [`ClosetImageByteCacheTests.swift`](../../../Tests/UnitTests/ClosetImageByteCacheTests.swift)
- [`ClosetImageThumbnailerTests.swift`](../../../Tests/UnitTests/ClosetImageThumbnailerTests.swift)
- [`ClosetImageVariantPathTests.swift`](../../../Tests/UnitTests/ClosetImageVariantPathTests.swift)
- [`ClosetItemAnalysisResultTests.swift`](../../../Tests/UnitTests/ClosetItemAnalysisResultTests.swift)
- [`ClosetItemCareInstructionsUITests.swift`](../../../Tests/UITests/ClosetItemCareInstructionsUITests.swift)
- [`ClosetItemDetailViewModelTests.swift`](../../../Tests/UnitTests/ClosetItemDetailViewModelTests.swift)
- [`ClosetItemFormViewModelTests.swift`](../../../Tests/UnitTests/ClosetItemFormViewModelTests.swift)
- [`ClosetItemInsightsTests.swift`](../../../Tests/UnitTests/ClosetItemInsightsTests.swift)
- [`ClosetItemUpdatePayloadTests.swift`](../../../Tests/UnitTests/ClosetItemUpdatePayloadTests.swift)
- [`ClosetItemWearableTests.swift`](../../../Tests/UnitTests/ClosetItemWearableTests.swift)
- [`ClosetLaundryTests.swift`](../../../Tests/UnitTests/ClosetLaundryTests.swift)
- [`ClosetLooksViewModelTests.swift`](../../../Tests/UnitTests/ClosetLooksViewModelTests.swift)
- [`ClosetMetricsTests.swift`](../../../Tests/UnitTests/ClosetMetricsTests.swift)
- [`ClosetVersatilityMetricTests.swift`](../../../Tests/UnitTests/ClosetVersatilityMetricTests.swift)
- [`ClosetViewModeTests.swift`](../../../Tests/UnitTests/ClosetViewModeTests.swift)
- [`ClosetViewModelTests.swift`](../../../Tests/UnitTests/ClosetViewModelTests.swift)
- [`FreeTierClosetCapTests.swift`](../../../Tests/UnitTests/FreeTierClosetCapTests.swift)
- [`LiveClosetImageURLResolverOwnershipTests.swift`](../../../Tests/UnitTests/LiveClosetImageURLResolverOwnershipTests.swift)
- [`LiveClosetRepositoryCacheTests.swift`](../../../Tests/UnitTests/LiveClosetRepositoryCacheTests.swift)
- [`MonthlyReviewAuthoredReviewTests.swift`](../../../Tests/UnitTests/MonthlyReviewAuthoredReviewTests.swift)
- [`MonthlyReviewCacheViewModelTests.swift`](../../../Tests/UnitTests/MonthlyReviewCacheViewModelTests.swift)
- [`MonthlyReviewFactsTests.swift`](../../../Tests/UnitTests/MonthlyReviewFactsTests.swift)
- [`MonthlyReviewSummaryPersistenceTests.swift`](../../../Tests/UnitTests/MonthlyReviewSummaryPersistenceTests.swift)
- [`MonthlyReviewViewModelTests.swift`](../../../Tests/UnitTests/MonthlyReviewViewModelTests.swift)

Add new tests to the existing target and update this index. `project.yml` excludes the feature documentation from the application bundle.
