//
//  OutfitBuilderViewModelTests.swift
//  AstraStyleTests
//
//  Derived from P4-OUTFIT-12's acceptance criteria, not from the
//  implementation:
//    - "Locking an item and triggering regenerate changes only unlocked
//      slots."
//    - "The compatibility meter updates live as items are swapped,
//      calling CompatibilityScorer for the current combination."
//    - "'Ask Kyra to finish' ... may show a 'coming soon' state rather
//      than a silently broken button" before P5-KYRA-06 lands.
//

import Foundation
import Testing
@testable import AstraStyle

/// `@MainActor` for the same reason every other view-model suite here is:
/// `OutfitBuilderViewModel` is `@MainActor @Observable` per ADR 0006, so
/// without it neither the initialiser nor any observable property is reachable
/// from the test. Swift 6 reports it against generated macro code rather than
/// against the `#expect` that caused it, which makes it look far stranger than
/// it is.
@MainActor
@Suite("OutfitBuilderViewModel")
struct OutfitBuilderViewModelTests {

    // MARK: - Fixtures

    private func item(_ category: ClothingCategory, name: String = "Fixture") -> ClosetItem {
        ClosetItem(id: UUID(), userID: UUID(), name: name, category: category)
    }

    // MARK: - Doubles

    /// A minimal, fully-controllable `OutfitRepository` double. Every
    /// method not under test in a given case throws
    /// `AstraError.unimplemented` rather than silently no-op-ing, so a
    /// test that accidentally exercises an unstubbed path fails loudly
    /// instead of passing on a wrong assumption.
    private actor StubOutfitRepository: OutfitRepository {
        var rankResult: [OutfitRecommendation] = []
        private(set) var lastLockedClosetItemIDs: [UUID] = []
        private(set) var savedRecommendations: [OutfitRecommendation] = []

        func fetchOutfits() async throws -> [Outfit] { [] }
        func fetchOutfit(id: UUID) async throws -> Outfit { Outfit(id: id, userID: UUID(), name: "Fixture") }
        func fetchOutfits(ids: [UUID]) async throws -> [Outfit] { [] }
        func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem] { [] }
        func generateOutfits(_ request: OutfitGenerationRequest) async throws -> [OutfitRecommendation] {
            throw AstraError.unimplemented("not stubbed")
        }

        func rankOutfits(candidateOutfitIDs: [UUID], lockedClosetItemIDs: [UUID]) async throws -> [OutfitRecommendation] {
            lastLockedClosetItemIDs = lockedClosetItemIDs
            return rankResult
        }

        func saveOutfit(from recommendation: OutfitRecommendation, name: String?, closetItems: [ClosetItem]) async throws -> Outfit {
            savedRecommendations.append(recommendation)
            return Outfit(id: recommendation.id, userID: UUID(), name: name ?? recommendation.name)
        }

        func updateOutfit(_ outfit: Outfit) async throws -> Outfit { outfit }
        func deleteOutfit(id: UUID) async throws {}

        @discardableResult
        func recordWear(outfitID: UUID, wornAt: Date, occasion: String?, rating: Int?, feedback: String?) async throws -> OutfitWear {
            throw AstraError.unimplemented("not stubbed")
        }

        @discardableResult
        func recordFeedback(
            targetType: StyleFeedbackTargetType,
            targetID: UUID,
            signal: StyleFeedbackSignal,
            reasonTags: [String],
            freeText: String?
        ) async throws -> StyleFeedback {
            throw AstraError.unimplemented("not stubbed")
        }

        func fetchDailyBrief(for date: Date) async throws -> DailyBrief? { nil }
        func generateDailyBrief(for date: Date, regenerate: Bool, weather: WeatherSnapshot?) async throws -> DailyBrief {
            throw AstraError.unimplemented("not stubbed")
        }
        func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan {
            throw AstraError.unimplemented("not stubbed")
        }

        func setRankResult(_ result: [OutfitRecommendation]) {
            rankResult = result
        }
    }

    private func makeViewModel(
        closet: [ClosetItem],
        repository: StubOutfitRepository = StubOutfitRepository()
    ) -> (OutfitBuilderViewModel, StubOutfitRepository) {
        let closetRepository = MockClosetRepository(items: closet)
        let viewModel = OutfitBuilderViewModel(
            outfitRepository: repository,
            closetRepository: closetRepository,
            compatibilityScorer: LocalCompatibilityScorer()
        )
        return (viewModel, repository)
    }

    // MARK: - Lock + regenerate

    @Test("Regenerating with a locked top only changes the unlocked bottom slot")
    func regenerateChangesOnlyUnlockedSlots() async throws {
        let lockedTop = item(.top, name: "Locked Navy Shirt")
        let originalBottom = item(.bottom, name: "Original Chinos")
        let newBottom = item(.bottom, name: "Recommended Trousers")
        let closet = [lockedTop, originalBottom, newBottom]

        let (viewModel, repository) = makeViewModel(closet: closet)
        await viewModel.onAppear()
        viewModel.selectItem(lockedTop, for: .top)
        viewModel.selectItem(originalBottom, for: .bottom)
        viewModel.toggleLock(for: .top)
        #expect(viewModel.slots.first(where: { $0.category == .top })?.isLocked == true)

        let recommendation = OutfitRecommendation(
            id: UUID(),
            name: "Regenerated",
            reason: "",
            compatibilityScore: 80,
            itemIDs: [lockedTop.id, newBottom.id],
            missingProductIDs: []
        )
        await repository.setRankResult([recommendation])

        await viewModel.regenerate()

        let top = viewModel.slots.first(where: { $0.category == .top })
        let bottom = viewModel.slots.first(where: { $0.category == .bottom })
        #expect(top?.item?.id == lockedTop.id, "The locked slot must be untouched")
        #expect(bottom?.item?.id == newBottom.id, "The unlocked slot must take the regenerated item")
        #expect(await repository.lastLockedClosetItemIDs == [lockedTop.id])
    }

    @Test("applyToUnlockedSlots never overwrites a locked slot, even if the recommendation targets it")
    func applyToUnlockedSlotsNeverTouchesLockedSlot() async throws {
        let lockedTop = item(.top, name: "Locked")
        let recommendedTop = item(.top, name: "Would-be replacement")
        let (viewModel, _) = makeViewModel(closet: [lockedTop, recommendedTop])
        await viewModel.onAppear()
        viewModel.selectItem(lockedTop, for: .top)
        viewModel.toggleLock(for: .top)

        let recommendation = OutfitRecommendation(
            id: UUID(), name: "x", reason: "", compatibilityScore: 50,
            itemIDs: [recommendedTop.id], missingProductIDs: []
        )
        viewModel.applyToUnlockedSlots(recommendation)

        #expect(viewModel.slots.first(where: { $0.category == .top })?.item?.id == lockedTop.id)
    }

    @Test("An empty slot cannot be locked")
    func emptySlotCannotBeLocked() async throws {
        let (viewModel, _) = makeViewModel(closet: [])
        await viewModel.onAppear()
        viewModel.toggleLock(for: .top)
        #expect(viewModel.slots.first(where: { $0.category == .top })?.isLocked == false)
    }

    // MARK: - Live compatibility meter

    @Test("Fewer than two filled slots reports no compatibility reading at all")
    func compatibilityIsAbsentBelowTwoItems() async throws {
        let top = item(.top)
        let (viewModel, _) = makeViewModel(closet: [top])
        await viewModel.onAppear()
        #expect(viewModel.currentCompatibility == nil)

        viewModel.selectItem(top, for: .top)
        #expect(viewModel.currentCompatibility == nil, "One item alone has nothing to be compatible WITH")
    }

    @Test("The compatibility reading updates live as a slot is swapped")
    func compatibilityUpdatesWhenASlotIsSwapped() async throws {
        let topScored = ClosetItem(id: UUID(), userID: UUID(), name: "Top", category: .top, formalityScore: 50)
        let bottomA = ClosetItem(id: UUID(), userID: UUID(), name: "A", category: .bottom, formalityScore: 50)
        let bottomB = ClosetItem(id: UUID(), userID: UUID(), name: "B", category: .bottom, formalityScore: 0)
        let (viewModel, _) = makeViewModel(closet: [topScored, bottomA, bottomB])
        await viewModel.onAppear()

        viewModel.selectItem(topScored, for: .top)
        viewModel.selectItem(bottomA, for: .bottom)
        let firstReading = try #require(viewModel.currentCompatibility)

        viewModel.selectItem(bottomB, for: .bottom)
        let secondReading = try #require(viewModel.currentCompatibility)

        #expect(firstReading != secondReading)
    }

    // MARK: - Ask Kyra to finish

    @Test("Ask Kyra to finish is an honest, visible state change, not a silent no-op")
    func askKyraToFinishIsHonestState() async throws {
        let (viewModel, _) = makeViewModel(closet: [])
        #expect(viewModel.askKyraState == .idle)
        viewModel.askKyraToFinish()
        #expect(viewModel.askKyraState == .comingSoon)
    }

    // MARK: - Save

    @Test("Saving with no items filled does nothing")
    func saveDoesNothingWhenEmpty() async throws {
        let (viewModel, repository) = makeViewModel(closet: [])
        await viewModel.onAppear()
        await viewModel.save()
        #expect(await repository.savedRecommendations.isEmpty)
        #expect(viewModel.savedOutfit == nil)
    }

    @Test("Saving with at least one item persists and records the backing outfit id")
    func saveWithOneItemPersists() async throws {
        let top = item(.top)
        let (viewModel, repository) = makeViewModel(closet: [top])
        await viewModel.onAppear()
        viewModel.selectItem(top, for: .top)

        await viewModel.save()

        #expect(await repository.savedRecommendations.count == 1)
        #expect(viewModel.savedOutfit != nil)
        #expect(viewModel.backingOutfitID == viewModel.savedOutfit?.id)
    }
}
