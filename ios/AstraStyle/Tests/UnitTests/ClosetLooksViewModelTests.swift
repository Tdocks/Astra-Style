//
//  ClosetLooksViewModelTests.swift
//  AstraStyleTests
//
//  Written against what the tone controls PROMISE rather than how they are
//  implemented: "too dressy" must move to something less dressy, must say
//  so when it cannot, and must record the opinion either way.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("ClosetLooksViewModel")
@MainActor
struct ClosetLooksViewModelTests {

    @Test("A closet with no saved outfits is empty, not failed")
    func noOutfitsIsEmpty() async {
        let model = makeModel(outfits: [])
        await model.onAppear()

        guard case .empty = model.state else {
            Issue.record("expected .empty, got \(model.state)")
            return
        }
    }

    @Test("Each look carries the garments its outfit_items point at")
    func looksAreHydrated() async throws {
        let closet = Array(SampleData.closetItems.prefix(3))
        let model = makeModel(outfits: [outfit(formality: 40)], closet: closet)
        await model.onAppear()

        let looks = try #require(loaded(model))
        #expect(looks.count == 1)
        #expect(looks[0].garments.count == 3)
        #expect(looks[0].garments.map(\.item.id) == closet.map(\.id))
    }

    @Test("An outfit whose garments no longer resolve is dropped, not shown empty")
    func outfitPointingAtNothingIsDropped() async {
        // The row exists; every `closet_item_id` on it points at a garment
        // that has since been deleted. A card reading "Thursday Casual" with
        // no clothes on it claims an outfit that cannot be worn.
        let model = makeModel(outfits: [outfit(formality: 40)], closet: [])
        await model.onAppear()

        guard case .empty = model.state else {
            Issue.record("expected .empty, got \(model.state)")
            return
        }
    }

    @Test("Too dressy moves to the NEAREST less formal look, not the most casual one")
    func tooDressyStepsDownOnce() async throws {
        // A man who says "too dressy" about a suit wants the blazer, not
        // gym shorts. Stepping to the extreme is the failure this asserts
        // against.
        let looks = [outfit(formality: 80), outfit(formality: 60), outfit(formality: 20)]
        let model = makeModel(outfits: looks, closet: Array(SampleData.closetItems.prefix(3)))
        await model.onAppear()
        model.focusedLookID = looks[0].id

        await model.nudge(.tooDressy)

        #expect(model.focusedLookID == looks[1].id)
        #expect(model.nudgeNote == nil)
    }

    @Test("Too casual moves the other way")
    func tooCasualStepsUp() async throws {
        let looks = [outfit(formality: 20), outfit(formality: 55)]
        let model = makeModel(outfits: looks, closet: Array(SampleData.closetItems.prefix(3)))
        await model.onAppear()
        model.focusedLookID = looks[0].id

        await model.nudge(.tooCasual)

        #expect(model.focusedLookID == looks[1].id)
    }

    @Test("A nudge with nowhere to go says so rather than doing nothing")
    func edgeOfTheRangeIsSpokenAloud() async throws {
        let looks = [outfit(formality: 20), outfit(formality: 55)]
        let model = makeModel(outfits: looks, closet: Array(SampleData.closetItems.prefix(3)))
        await model.onAppear()
        model.focusedLookID = looks[0].id

        await model.nudge(.tooDressy)

        // Still on the same look — and the screen has a sentence for it.
        #expect(model.focusedLookID == looks[0].id)
        #expect(model.nudgeNote != nil)
    }

    @Test("The opinion is recorded even when the carousel could not move")
    func feedbackIsWrittenAtTheEdgeToo() async throws {
        // The end of the range is the case most worth learning from: every
        // look he owns is dressier than he wants. Recording only the jumps
        // would throw exactly that signal away.
        let looks = [outfit(formality: 20)]
        let closet = Array(SampleData.closetItems.prefix(3))
        let repository = LooksOutfitRepository(outfits: looks, garmentIDs: closet.map(\.id))
        let model = makeModel(repository: repository, closet: closet)
        await model.onAppear()

        await model.nudge(.tooDressy)

        #expect(repository.feedback.count == 1)
        #expect(repository.feedback.first?.signal == .tooFormal)
        #expect(repository.feedback.first?.targetID == looks[0].id)
    }

    @Test("An outfit with no score of its own is ranked by the garments in it")
    func formalityFallsBackToTheGarments() async throws {
        // Every `outfits` row the daily brief has written carries a null
        // `formality_score`. Reading only that column left both tone buttons
        // permanently inert on real data — every tap fell through to the
        // edge note. The garments have the number, so the look does.
        let dressy = Array(SampleData.closetItems.prefix(3))          // mean ≈ 38
        let looks = [outfit(formality: 70), outfit(formality: nil)]
        let model = makeModel(outfits: looks, closet: dressy)
        await model.onAppear()
        model.focusedLookID = looks[0].id

        await model.nudge(.tooDressy)

        #expect(model.focusedLookID == looks[1].id)
        #expect(model.nudgeNote == nil)
    }

    @Test("A look whose garments are all unscored is still not a destination")
    func aTrulyUnscoredLookIsSkipped() async throws {
        // Nil is not zero. If nothing in the look has a formality score
        // there is no comparison to make, and treating the absence as 0
        // would pull every "too dressy" tap onto the one look the app knows
        // least about.
        let unscored = (0..<3).map { index in
            ClosetItem(id: UUID(), userID: UUID(), name: "Piece \(index)", category: .top)
        }
        let looks = [outfit(formality: 70), outfit(formality: nil)]
        let model = makeModel(outfits: looks, closet: unscored)
        await model.onAppear()
        model.focusedLookID = looks[0].id

        await model.nudge(.tooDressy)

        #expect(model.focusedLookID == looks[0].id)
        #expect(model.nudgeNote != nil)
    }

    @Test("The frame is derived from the body profile, and absent when there is none")
    func frameComesFromTheBodyProfile() async {
        let model = makeModel(outfits: [outfit(formality: 40)],
                              closet: Array(SampleData.closetItems.prefix(3)),
                              bodyProfile: nil)
        await model.onAppear()

        // No measurements is the normal state (spec §6.6 allows "I don't
        // know" on every field) and must leave the silhouette on its
        // balanced defaults rather than on a guess.
        #expect(model.frame.isEmpty)
    }
}

// MARK: - Helpers

@MainActor
private func makeModel(
    outfits: [Outfit],
    closet: [ClosetItem] = SampleData.closetItems,
    bodyProfile: BodyProfile? = nil
) -> ClosetLooksViewModel {
    // The outfit's items point at whatever closet this test passed. Pinning
    // them to `SampleData` instead meant a test that supplied its own
    // garments silently got an outfit joined to nothing, and the assertion
    // it thought it was making was never reached.
    makeModel(
        repository: LooksOutfitRepository(outfits: outfits, garmentIDs: closet.prefix(3).map(\.id)),
        closet: closet,
        bodyProfile: bodyProfile
    )
}

@MainActor
private func makeModel(
    repository: LooksOutfitRepository,
    closet: [ClosetItem],
    bodyProfile: BodyProfile? = nil
) -> ClosetLooksViewModel {
    ClosetLooksViewModel(
        outfitRepository: repository,
        closetRepository: MockClosetRepository(items: closet),
        profileRepository: LooksProfileRepository(bodyProfile: bodyProfile),
        imageURLResolver: MockClosetImageURLResolver()
    )
}

private func outfit(formality: Int?) -> Outfit {
    Outfit(
        id: UUID(),
        userID: UUID(),
        name: "Look \(formality.map(String.init) ?? "unscored")",
        formalityScore: formality
    )
}

@MainActor
private func loaded(_ model: ClosetLooksViewModel) -> [ClosetLooksViewModel.Look]? {
    guard case .loaded(let looks) = model.state else { return nil }
    return looks
}

/// Serves the outfits under test and records every opinion written about
/// them. `@unchecked Sendable` with main-actor-only access, the same shape
/// the other view-model suites in this target use.
private final class LooksOutfitRepository: OutfitRepository, @unchecked Sendable {
    private let outfits: [Outfit]
    private let garmentIDs: [UUID]
    private(set) var feedback: [StyleFeedback] = []

    init(outfits: [Outfit], garmentIDs: [UUID]) {
        self.outfits = outfits
        self.garmentIDs = garmentIDs
    }

    func fetchOutfits() async throws -> [Outfit] { outfits }

    /// One `outfit_items` row per garment the test supplied. A test that
    /// passes an empty closet therefore gets an outfit whose row survived
    /// and whose garments did not, which is a real state.
    func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem] {
        garmentIDs.enumerated().map { index, id in
            OutfitItem(
                outfitID: outfitID,
                closetItemID: id,
                role: [.top, .bottom, .shoes][index % 3],
                sortOrder: index
            )
        }
    }

    func recordFeedback(
        targetType: StyleFeedbackTargetType,
        targetID: UUID,
        signal: StyleFeedbackSignal,
        reasonTags: [String],
        freeText: String?
    ) async throws -> StyleFeedback {
        let row = StyleFeedback(
            id: UUID(),
            userID: UUID(),
            targetType: targetType,
            targetID: targetID,
            signal: signal,
            reasonTags: reasonTags,
            freeText: freeText
        )
        feedback.append(row)
        return row
    }

    func fetchOutfit(id: UUID) async throws -> Outfit { throw AstraError.unimplemented("unused") }
    func fetchOutfits(ids: [UUID]) async throws -> [Outfit] { outfits.filter { ids.contains($0.id) } }
    func generateOutfits(_ request: OutfitGenerationRequest) async throws -> [OutfitRecommendation] { [] }
    func rankOutfits(candidateOutfitIDs: [UUID], lockedClosetItemIDs: [UUID]) async throws -> [OutfitRecommendation] { [] }
    func saveOutfit(from recommendation: OutfitRecommendation, name: String?, closetItems: [ClosetItem]) async throws -> Outfit {
        throw AstraError.unimplemented("unused")
    }
    func updateOutfit(_ outfit: Outfit) async throws -> Outfit { outfit }
    func deleteOutfit(id: UUID) async throws {}
    func recordWear(outfitID: UUID, wornAt: Date, occasion: String?, rating: Int?, feedback: String?) async throws -> OutfitWear {
        throw AstraError.unimplemented("unused")
    }
    func fetchDailyBrief(for date: Date) async throws -> DailyBrief? { nil }
    func generateDailyBrief(for date: Date, regenerate: Bool, weather: WeatherSnapshot?) async throws -> DailyBrief {
        throw AstraError.unimplemented("unused")
    }
    func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan {
        throw AstraError.unimplemented("unused")
    }
}

/// Only `fetchBodyProfile` is exercised; everything else is out of scope for
/// a carousel and says so rather than returning a plausible blank.
private final class LooksProfileRepository: ProfileRepository, @unchecked Sendable {
    private let bodyProfile: BodyProfile?

    init(bodyProfile: BodyProfile?) {
        self.bodyProfile = bodyProfile
    }

    func fetchBodyProfile() async throws -> BodyProfile? { bodyProfile }

    func fetchCurrentProfile() async throws -> Profile { SampleData.profile }
    func updateProfile(_ profile: Profile) async throws -> Profile { profile }
    func fetchStyleProfile() async throws -> StyleProfile? { nil }
    func updateStyleProfile(_ styleProfile: StyleProfile) async throws -> StyleProfile { styleProfile }
    func updateBodyProfile(_ bodyProfile: BodyProfile) async throws -> BodyProfile { bodyProfile }
    func fetchLifestyleProfile() async throws -> LifestyleProfile? { nil }
    func updateLifestyleProfile(_ lifestyleProfile: LifestyleProfile) async throws -> LifestyleProfile { lifestyleProfile }
    func completeOnboarding(_ payload: OnboardingCompletionPayload) async throws -> Profile {
        throw AstraError.unimplemented("unused")
    }
    func generateStyleDNA() async throws -> StyleDNA { throw AstraError.unimplemented("unused") }
    func uploadReferenceImage(_ imageData: Data) async throws -> String {
        throw AstraError.unimplemented("unused")
    }
    func exportPersonalData() async throws -> URL { throw AstraError.unimplemented("unused") }
}
