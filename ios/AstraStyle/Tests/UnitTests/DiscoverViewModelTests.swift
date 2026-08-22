//
//  DiscoverViewModelTests.swift
//  AstraStyleTests
//
//  Wave F: Discover is his outfits as lookbooks. Empty is a sentence, not
//  a fake grid. Archived rows stay out. No retailer cards.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Discover lookbooks")
@MainActor
struct DiscoverViewModelTests {

    @Test("No saved outfits is empty, not a storefront")
    func emptyClosetLooksEmpty() async {
        let model = DiscoverViewModel(outfitRepository: DiscoverOutfitStub(outfits: []))
        await model.onAppear()
        guard case .empty = model.state else {
            Issue.record("expected .empty, got \(model.state)")
            return
        }
    }

    @Test("Saved outfits become lookbooks; archived ones do not")
    func listsLiveOutfitsOnly() async throws {
        let live = Outfit(id: UUID(), userID: SampleData.userID, name: "Thursday navy")
        let archived = Outfit(
            id: UUID(),
            userID: SampleData.userID,
            name: "Old look",
            archivedAt: Date()
        )
        let model = DiscoverViewModel(outfitRepository: DiscoverOutfitStub(outfits: [live, archived]))
        await model.onAppear()

        guard case .loaded(let outfits) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(outfits.map(\.id) == [live.id])
        #expect(outfits.allSatisfy { !$0.isArchived })
    }
}

/// Only `fetchOutfits` is in scope for Discover's list.
private final class DiscoverOutfitStub: OutfitRepository, @unchecked Sendable {
    private let outfits: [Outfit]

    init(outfits: [Outfit]) {
        self.outfits = outfits
    }

    func fetchOutfits() async throws -> [Outfit] { outfits }
    func fetchOutfit(id: UUID) async throws -> Outfit { throw AstraError.unimplemented("unused") }
    func fetchOutfits(ids: [UUID]) async throws -> [Outfit] { outfits.filter { ids.contains($0.id) } }
    func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem] { [] }
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
    func recordFeedback(
        targetType: StyleFeedbackTargetType,
        targetID: UUID,
        signal: StyleFeedbackSignal,
        reasonTags: [String],
        freeText: String?
    ) async throws -> StyleFeedback {
        throw AstraError.unimplemented("unused")
    }
}
