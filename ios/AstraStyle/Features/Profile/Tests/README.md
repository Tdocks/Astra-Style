# Profile tests

This directory records test ownership for the Profile feature. Executable test sources remain in the shared `ios/AstraStyle/Tests/UnitTests` and `UITests` targets so XcodeGen continues using the existing targets and shared support.

Current related test sources:

- [`AccountDeletionViewModelTests.swift`](../../../Tests/UnitTests/AccountDeletionViewModelTests.swift)
- [`AppearanceEditorViewModelTests.swift`](../../../Tests/UnitTests/AppearanceEditorViewModelTests.swift)
- [`PersonalDataExportTests.swift`](../../../Tests/UnitTests/PersonalDataExportTests.swift)
- [`ProfileShoppingStatsViewModelTests.swift`](../../../Tests/UnitTests/ProfileShoppingStatsViewModelTests.swift)
- [`ProfileSnapshotPersistenceTests.swift`](../../../Tests/UnitTests/ProfileSnapshotPersistenceTests.swift)
- [`ReferencePhotosViewModelTests.swift`](../../../Tests/UnitTests/ReferencePhotosViewModelTests.swift)
- [`StyleMemoriesViewModelTests.swift`](../../../Tests/UnitTests/StyleMemoriesViewModelTests.swift)

Add new tests to the existing target and update this index. `project.yml` excludes the feature documentation from the application bundle.
