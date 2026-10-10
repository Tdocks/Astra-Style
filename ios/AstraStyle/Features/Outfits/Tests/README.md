# Outfits tests

This directory records test ownership for the Outfits feature. Executable test sources remain in the shared `ios/AstraStyle/Tests/UnitTests` and `UITests` targets so XcodeGen continues using the existing targets and shared support.

Current related test sources:

- [`CompatibilityScoringTests.swift`](../../../Tests/UnitTests/CompatibilityScoringTests.swift)
- [`LocalCompatibilityScorerTests.swift`](../../../Tests/UnitTests/LocalCompatibilityScorerTests.swift)
- [`MonthlyReviewAuthoredReviewTests.swift`](../../../Tests/UnitTests/MonthlyReviewAuthoredReviewTests.swift)
- [`MonthlyReviewCacheViewModelTests.swift`](../../../Tests/UnitTests/MonthlyReviewCacheViewModelTests.swift)
- [`MonthlyReviewFactsTests.swift`](../../../Tests/UnitTests/MonthlyReviewFactsTests.swift)
- [`MonthlyReviewSummaryPersistenceTests.swift`](../../../Tests/UnitTests/MonthlyReviewSummaryPersistenceTests.swift)
- [`MonthlyReviewViewModelTests.swift`](../../../Tests/UnitTests/MonthlyReviewViewModelTests.swift)
- [`OutfitBuilderKyraSafetyTests.swift`](../../../Tests/UnitTests/OutfitBuilderKyraSafetyTests.swift)
- [`OutfitBuilderViewModelTests.swift`](../../../Tests/UnitTests/OutfitBuilderViewModelTests.swift)
- [`OutfitDetailCopyTests.swift`](../../../Tests/UnitTests/OutfitDetailCopyTests.swift)
- [`OutfitDetailViewModelTests.swift`](../../../Tests/UnitTests/OutfitDetailViewModelTests.swift)
- [`OutfitItemAssemblyTests.swift`](../../../Tests/UnitTests/OutfitItemAssemblyTests.swift)
- [`OutfitOfflineDrainWiringTests.swift`](../../../Tests/UnitTests/OutfitOfflineDrainWiringTests.swift)
- [`OutfitRecommendationWireTests.swift`](../../../Tests/UnitTests/OutfitRecommendationWireTests.swift)
- [`OutfitWeatherContextTests.swift`](../../../Tests/UnitTests/OutfitWeatherContextTests.swift)

Add new tests to the existing target and update this index. `project.yml` excludes the feature documentation from the application bundle.
