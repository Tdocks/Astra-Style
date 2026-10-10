# Discover tests

This directory records test ownership for the Discover feature. Executable test sources remain in the shared `ios/AstraStyle/Tests/UnitTests` and `UITests` targets so XcodeGen continues using the existing targets and shared support.

Current related test sources:

- [`DiscoverEditorialRepositoryTests.swift`](../../../Tests/UnitTests/DiscoverEditorialRepositoryTests.swift)
- [`DiscoverEditorialUITests.swift`](../../../Tests/UITests/DiscoverEditorialUITests.swift)
- [`DiscoverGuideDetailViewModelTests.swift`](../../../Tests/UnitTests/DiscoverGuideDetailViewModelTests.swift)
- [`DiscoverViewModelTests.swift`](../../../Tests/UnitTests/DiscoverViewModelTests.swift)

Add new tests to the existing target and update this index. `project.yml` excludes the feature documentation from the application bundle.
