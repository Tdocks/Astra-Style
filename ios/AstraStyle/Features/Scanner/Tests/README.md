# Scanner tests

This directory records test ownership for the Scanner feature. Executable test sources remain in the shared `ios/AstraStyle/Tests/UnitTests` and `UITests` targets so XcodeGen continues using the existing targets and shared support.

Current related test sources:

- [`BackgroundRemovalTests.swift`](../../../Tests/UnitTests/BackgroundRemovalTests.swift)
- [`CapturePreparationTests.swift`](../../../Tests/UnitTests/CapturePreparationTests.swift)
- [`CaptureQualityTests.swift`](../../../Tests/UnitTests/CaptureQualityTests.swift)
- [`MirrorCaptureViewModelTests.swift`](../../../Tests/UnitTests/MirrorCaptureViewModelTests.swift)
- [`ReceiptCaptureViewModelTests.swift`](../../../Tests/UnitTests/ReceiptCaptureViewModelTests.swift)
- [`ScannerBatchDurabilityTests.swift`](../../../Tests/UnitTests/ScannerBatchDurabilityTests.swift)
- [`ScannerBatchPendingStoreTests.swift`](../../../Tests/UnitTests/ScannerBatchPendingStoreTests.swift)
- [`ScannerBatchViewModelTests.swift`](../../../Tests/UnitTests/ScannerBatchViewModelTests.swift)
- [`ScannerCaptureViewModelTests.swift`](../../../Tests/UnitTests/ScannerCaptureViewModelTests.swift)
- [`ScannerFallbackTests.swift`](../../../Tests/UnitTests/ScannerFallbackTests.swift)
- [`ScannerImageFixtures.swift`](../../../Tests/UnitTests/ScannerImageFixtures.swift)
- [`ScannerPendingQueueFailureTests.swift`](../../../Tests/UnitTests/ScannerPendingQueueFailureTests.swift)
- [`ScannerReviewSaveIdentityTests.swift`](../../../Tests/UnitTests/ScannerReviewSaveIdentityTests.swift)
- [`ScannerReviewViewModelTests.swift`](../../../Tests/UnitTests/ScannerReviewViewModelTests.swift)
- [`ScannerSaveRecoveryTests.swift`](../../../Tests/UnitTests/ScannerSaveRecoveryTests.swift)
- [`ScannerUnlockCountFollowUpTests.swift`](../../../Tests/UnitTests/ScannerUnlockCountFollowUpTests.swift)

Add new tests to the existing target and update this index. `project.yml` excludes the feature documentation from the application bundle.
