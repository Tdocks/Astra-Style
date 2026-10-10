# Kyra tests

This directory records test ownership for the Kyra feature. Executable test sources remain in the shared `ios/AstraStyle/Tests/UnitTests` and `UITests` targets so XcodeGen continues using the existing targets and shared support.

Current related test sources:

- [`KyraConversationViewModelTests.swift`](../../../Tests/UnitTests/KyraConversationViewModelTests.swift)
- [`KyraDailyLimitPaywallTests.swift`](../../../Tests/UnitTests/KyraDailyLimitPaywallTests.swift)
- [`KyraHistoryCacheTests.swift`](../../../Tests/UnitTests/KyraHistoryCacheTests.swift)
- [`KyraHistoryDiskPersistenceTests.swift`](../../../Tests/UnitTests/KyraHistoryDiskPersistenceTests.swift)
- [`KyraStructuredResponseDecodingTests.swift`](../../../Tests/UnitTests/KyraStructuredResponseDecodingTests.swift)
- [`KyraStudioInspirationAttachmentTests.swift`](../../../Tests/UnitTests/KyraStudioInspirationAttachmentTests.swift)

Add new tests to the existing target and update this index. `project.yml` excludes the feature documentation from the application bundle.
