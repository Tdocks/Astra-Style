# Onboarding tests

This directory records test ownership for the Onboarding feature. Executable test sources remain in the shared `ios/AstraStyle/Tests/UnitTests` and `UITests` targets so XcodeGen continues using the existing targets and shared support.

Current related test sources:

- [`AppearanceEditorViewModelTests.swift`](../../../Tests/UnitTests/AppearanceEditorViewModelTests.swift)
- [`AppearanceOptionsTests.swift`](../../../Tests/UnitTests/AppearanceOptionsTests.swift)
- [`OnboardingCaptureStepsUITests.swift`](../../../Tests/UITests/OnboardingCaptureStepsUITests.swift)
- [`OnboardingCaptureUITestCase.swift`](../../../Tests/UITests/OnboardingCaptureUITestCase.swift)
- [`OnboardingDraftTests.swift`](../../../Tests/UnitTests/OnboardingDraftTests.swift)
- [`OnboardingFirstItemsTests.swift`](../../../Tests/UnitTests/OnboardingFirstItemsTests.swift)
- [`OnboardingFirstItemsUITests.swift`](../../../Tests/UITests/OnboardingFirstItemsUITests.swift)
- [`OnboardingFlowUITestSupport.swift`](../../../Tests/UITests/OnboardingFlowUITestSupport.swift)
- [`OnboardingFlowUITests.swift`](../../../Tests/UITests/OnboardingFlowUITests.swift)
- [`OnboardingReferenceTests.swift`](../../../Tests/UnitTests/OnboardingReferenceTests.swift)
- [`ReferencePhotosViewModelTests.swift`](../../../Tests/UnitTests/ReferencePhotosViewModelTests.swift)
- [`StyleDNADecodingTests.swift`](../../../Tests/UnitTests/StyleDNADecodingTests.swift)
- [`StyleDNAResultTests.swift`](../../../Tests/UnitTests/StyleDNAResultTests.swift)
- [`StyleQuizEngineTests.swift`](../../../Tests/UnitTests/StyleQuizEngineTests.swift)
- [`StyleQuizRefinementUITests.swift`](../../../Tests/UITests/StyleQuizRefinementUITests.swift)
- [`StyleQuizRefinementViewModelTests.swift`](../../../Tests/UnitTests/StyleQuizRefinementViewModelTests.swift)

Add new tests to the existing target and update this index. `project.yml` excludes the feature documentation from the application bundle.
