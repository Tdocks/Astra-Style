//
//  AppearanceEditorViewModelTests.swift
//  AstraStyleTests
//

import Testing
@testable import AstraStyle

@MainActor
struct AppearanceEditorViewModelTests {
    @Test("Existing appearance loads into the post-onboarding editor")
    func loadsExistingAppearance() async {
        var body = SampleData.bodyProfile
        body.appearance.skinTone = "Deep"
        body.appearance.skinUndertone = "Warm"
        let repository = MockProfileRepository(bodyProfile: body)
        let model = AppearanceEditorViewModel(profileRepository: repository)

        await model.load()

        #expect(model.appearance.skinTone == "Deep")
        #expect(model.appearance.skinUndertone == "Warm")
        guard case .ready = model.phase else {
            Issue.record("Expected ready appearance editor")
            return
        }
    }

    @Test("A user who skipped appearance can save it later and refresh Style DNA")
    func savesDeferredAppearance() async throws {
        let repository = MockProfileRepository(bodyProfile: nil)
        let model = AppearanceEditorViewModel(profileRepository: repository)
        await model.load()
        model.appearance.skinTone = "Deepest"
        model.appearance.skinUndertone = "Cool"

        await model.save()

        let stored = try await repository.fetchBodyProfile()
        #expect(stored?.appearance.skinTone == "Deepest")
        #expect(stored?.appearance.skinUndertone == "Cool")
        #expect(model.confirmation?.contains("Style DNA") == true)
        guard case .ready = model.phase else {
            Issue.record("Expected ready editor after saving")
            return
        }
    }
}
