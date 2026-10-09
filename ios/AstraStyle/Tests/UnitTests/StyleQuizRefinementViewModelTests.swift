import Foundation
import Testing
@testable import AstraStyle

private actor QuizOwnerFixture {
    private var id: UUID?
    init(_ id: UUID?) { self.id = id }
    func read() -> UUID? { id }
    func switchTo(_ id: UUID?) { self.id = id }
}

@Suite("Profile taste refinement")
@MainActor
struct StyleQuizRefinementViewModelTests {
    @Test("A completed prior quiz can be restarted without changing saved answers")
    func restartPreservesSavedAnswers() async throws {
        let repository = MockProfileRepository()
        let engine = StyleQuizEngine(catalog: .bundled(), session: .fullRefinement)
        var style = try #require(await repository.fetchStyleProfile())
        style.preferenceQuizAnswers = engine.comparisons.map {
            StylePreferenceQuizAnswer(pairID: $0.id, chosenOptionID: StyleQuizPair.noPreferenceOptionID)
        }
        _ = try await repository.updateStyleProfile(style)
        let viewModel = StyleQuizRefinementViewModel(
            profileRepository: repository,
            currentOwnerID: { SampleData.userID }
        )
        await viewModel.load()
        #expect(viewModel.canSave)
        viewModel.restartQuiz()
        #expect(!viewModel.canSave)
        #expect(viewModel.draft.quizAnswers.isEmpty)
        #expect(await repository.styleProfileWrites() == 1)
        let saved = try #require(await repository.fetchStyleProfile())
        #expect(saved.preferenceQuizAnswers == style.preferenceQuizAnswers)
    }

    @Test("Requires every comparison and persists answer record with vector once")
    func fullAnswersPersistBeforeDNARefresh() async throws {
        let owner = QuizOwnerFixture(SampleData.userID)
        let repository = MockProfileRepository()
        await repository.failNextDNAGenerations(1)
        let viewModel = StyleQuizRefinementViewModel(
            profileRepository: repository,
            currentOwnerID: { await owner.read() }
        )
        await viewModel.load()

        #expect(viewModel.engine.comparisonCount >= 12)
        #expect(!viewModel.canSave)
        for pair in viewModel.engine.comparisons {
            viewModel.choose(pairID: pair.id, optionID: StyleQuizPair.noPreferenceOptionID)
        }
        #expect(viewModel.canSave)

        await viewModel.save()
        #expect(await repository.styleProfileWrites() == 1)
        #expect(await repository.dnaGenerations() == 1)
        let stored = try #require(await repository.fetchStyleProfile())
        #expect(stored.preferenceQuizAnswers?.count == viewModel.engine.comparisonCount)
        #expect(stored.preferenceVector.dimensions.count == StyleDimension.allCases.count)

        await viewModel.retryStyleDNA()
        #expect(await repository.styleProfileWrites() == 1)
        #expect(await repository.dnaGenerations() == 2)
    }

    @Test("Owner change before save prevents the write")
    func ownerChangeBlocksSave() async throws {
        let owner = QuizOwnerFixture(SampleData.userID)
        let repository = MockProfileRepository()
        let viewModel = StyleQuizRefinementViewModel(
            profileRepository: repository,
            currentOwnerID: { await owner.read() }
        )
        await viewModel.load()
        for pair in viewModel.engine.comparisons {
            viewModel.choose(pairID: pair.id, optionID: StyleQuizPair.noPreferenceOptionID)
        }
        await owner.switchTo(UUID())
        await viewModel.save()
        #expect(await repository.styleProfileWrites() == 0)
    }
}
