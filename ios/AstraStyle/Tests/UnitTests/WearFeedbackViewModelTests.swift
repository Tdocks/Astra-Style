//
//  WearFeedbackViewModelTests.swift
//  AstraStyleTests
//
//  Derived from P4-OUTFIT-14's acceptance criteria, not from the
//  implementation:
//    - "Marking an outfit worn writes exactly one outfit_wears row ...
//      for that outfit."
//    - "A subsequent 'skip' or 'dislike' action on a different outfit
//      writes a style_feedback row with the correct signal value."
//  Tests the count, not just the happy path, per this ticket's own
//  instructions.
//

import Foundation
import Testing
@testable import AstraStyle

/// `@MainActor` because `WearFeedbackViewModel` is, like every `@Observable`
/// view model in this app (ADR 0006). Without it the initialiser cannot be
/// called and `lastOutcome` cannot be read — Swift 6 reports the second as
/// "non-Sendable type cannot exit main actor-isolated context", pointing at
/// generated macro code rather than at the test.
@MainActor
@Suite("WearFeedbackViewModel")
struct WearFeedbackViewModelTests {

    // MARK: - Wore it

    @Test("Marking worn writes exactly one outfit_wears row")
    func markWornWritesExactlyOneRow() async throws {
        let repository = MockOutfitRepository()
        let outfitID = UUID()
        let viewModel = WearFeedbackViewModel(outfitID: outfitID, outfitRepository: repository)

        await viewModel.markWorn()

        let wears = await repository.recordedWears()
        #expect(wears.count == 1)
        #expect(wears.first?.outfitID == outfitID)
        #expect(viewModel.lastOutcome == .wore)
    }

    @Test("A double tap on 'Wore it' while the first request is in flight still writes exactly one row")
    func doubleTapMarkWornWritesOnlyOneRow() async throws {
        let repository = MockOutfitRepository()
        let outfitID = UUID()
        let viewModel = WearFeedbackViewModel(outfitID: outfitID, outfitRepository: repository)

        async let first: Void = viewModel.markWorn()
        async let second: Void = viewModel.markWorn()
        _ = await (first, second)

        let wears = await repository.recordedWears()
        #expect(wears.count == 1, "The second tap must be refused while the first is still in flight")
    }

    // MARK: - Skip / dislike

    @Test("Skip writes a style_feedback row with the skipped signal, and Wore it on the same outfit still writes its own row")
    func skipWritesFeedbackSignal() async throws {
        let repository = MockOutfitRepository()
        let outfitID = UUID()
        let viewModel = WearFeedbackViewModel(outfitID: outfitID, outfitRepository: repository)

        await viewModel.skip()

        let feedback = await repository.recordedFeedback()
        #expect(feedback.count == 1)
        #expect(feedback.first?.signal == .skipped)
        #expect(feedback.first?.targetType == .outfit)
        #expect(feedback.first?.targetID == outfitID)
        #expect(viewModel.lastOutcome == .feedback(.skipped))
        // Skip never writes to outfit_wears — a rejection is not a wear.
        #expect(await repository.recordedWears().isEmpty)
    }

    @Test("Dislike on a different outfit than a prior wear writes a style_feedback row with the dislike signal")
    func dislikeOnADifferentOutfitWritesFeedbackSignal() async throws {
        let repository = MockOutfitRepository()
        let wornOutfitID = UUID()
        let dislikedOutfitID = UUID()

        let wornViewModel = WearFeedbackViewModel(outfitID: wornOutfitID, outfitRepository: repository)
        await wornViewModel.markWorn()

        let dislikedViewModel = WearFeedbackViewModel(outfitID: dislikedOutfitID, outfitRepository: repository)
        await dislikedViewModel.dislike()

        let feedback = await repository.recordedFeedback()
        #expect(feedback.count == 1)
        #expect(feedback.first?.signal == .dislike)
        #expect(feedback.first?.targetID == dislikedOutfitID)

        let wears = await repository.recordedWears()
        #expect(wears.count == 1)
        #expect(wears.first?.outfitID == wornOutfitID)
    }
}
