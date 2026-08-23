//
//  DiscoverViewModelTests.swift
//  AstraStyleTests
//
//  ADR 0017: own lookbooks, public worn looks, Unlocks ranked by HIS gap.
//  Empty copy points at Wear This / paste-a-link, not a storefront.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Discover lookbooks")
@MainActor
struct DiscoverViewModelTests {

    @Test("No saved outfits and no unlocks is empty, not a storefront")
    func emptyClosetLooksEmpty() async {
        let model = DiscoverViewModel(
            outfitRepository: DiscoverOutfitStub(outfits: []),
            shoppingRepository: EmptyShoppingStub()
        )
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
        let model = DiscoverViewModel(
            outfitRepository: DiscoverOutfitStub(outfits: [live, archived]),
            shoppingRepository: EmptyShoppingStub()
        )
        await model.onAppear()

        guard case .loaded(let catalog) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(catalog.mine.map(\.id) == [live.id])
        #expect(catalog.mine.allSatisfy { !$0.isArchived })
        #expect(catalog.wornByOthers.isEmpty)
    }

    @Test("Public worn looks sit on a second rail, not mixed into mine")
    func publicLooksAreSeparate() async throws {
        let mine = Outfit(id: UUID(), userID: SampleData.userID, name: "Mine")
        let other = Outfit(
            id: UUID(),
            userID: UUID(),
            name: "His navy",
            visibility: .shared
        )
        let model = DiscoverViewModel(
            outfitRepository: DiscoverOutfitStub(outfits: [mine], publicLooks: [other]),
            shoppingRepository: EmptyShoppingStub()
        )
        await model.onAppear()
        guard case .loaded(let catalog) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(catalog.mine.map(\.id) == [mine.id])
        #expect(catalog.wornByOthers.map(\.id) == [other.id])
    }

    @Test("A candidate with more unlocks ranks above one with fewer")
    func higherGapRanksFirst() async throws {
        let few = unlock(name: "Few looks", outfitsUnlocked: 2)
        let many = unlock(name: "Many looks", outfitsUnlocked: 8)
        let model = DiscoverViewModel(
            outfitRepository: DiscoverOutfitStub(outfits: [
                Outfit(id: UUID(), userID: SampleData.userID, name: "Keep loaded")
            ]),
            shoppingRepository: UnlocksShoppingStub([few, many])
        )
        await model.onAppear()
        guard case .loaded(let catalog) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(catalog.unlocks.map(\.id) == [many.id, few.id])
        #expect(catalog.unlocks.map(\.outfitsUnlocked) == [8, 2])
    }

    @Test("Discover Unlocks does not read the curated catalog")
    func unlocksDoesNotCallCuratedCatalog() async {
        let shopping = UnlocksShoppingStub([])
        let model = DiscoverViewModel(
            outfitRepository: DiscoverOutfitStub(outfits: []),
            shoppingRepository: shopping
        )
        await model.onAppear()
        #expect(await shopping.curatedCalls == 0)
    }

    @Test("Sponsored cannot outrank a higher unlock count")
    func sponsoredCannotOutrankGap() async throws {
        let sponsoredFew = unlock(
            name: "Sponsored loafer",
            outfitsUnlocked: 3,
            affiliate: true
        )
        let organicMany = unlock(name: "Organic boot", outfitsUnlocked: 9)
        let model = DiscoverViewModel(
            outfitRepository: DiscoverOutfitStub(outfits: [
                Outfit(id: UUID(), userID: SampleData.userID, name: "Keep loaded")
            ]),
            shoppingRepository: UnlocksShoppingStub([sponsoredFew, organicMany])
        )
        await model.onAppear()
        guard case .loaded(let catalog) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(catalog.unlocks.map(\.id) == [organicMany.id, sponsoredFew.id])
        #expect(catalog.unlocks[0].candidate.isAffiliateLink == false)
        #expect(catalog.unlocks[1].candidate.isAffiliateLink == true)
    }

    @Test("Unlock count 0 is omitted from the rail")
    func zeroUnlockOmitted() async throws {
        let zero = unlock(name: "Already covered", outfitsUnlocked: 0)
        let gap = unlock(name: "New looks", outfitsUnlocked: 4)
        let model = DiscoverViewModel(
            outfitRepository: DiscoverOutfitStub(outfits: [
                Outfit(id: UUID(), userID: SampleData.userID, name: "Keep loaded")
            ]),
            shoppingRepository: UnlocksShoppingStub([zero, gap])
        )
        await model.onAppear()
        guard case .loaded(let catalog) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(catalog.unlocks.map(\.id) == [gap.id])
        #expect(catalog.unlocks.allSatisfy { $0.outfitsUnlocked > 0 })
    }

    @Test("An unlocks-only empty catalog stays empty, not a mall dump")
    func emptyUnlocksStayEmpty() async {
        let model = DiscoverViewModel(
            outfitRepository: DiscoverOutfitStub(outfits: []),
            shoppingRepository: UnlocksShoppingStub([
                unlock(name: "No gap", outfitsUnlocked: 0)
            ])
        )
        await model.onAppear()
        guard case .empty = model.state else {
            Issue.record("expected .empty, got \(model.state)")
            return
        }
    }
}

private func unlock(name: String, outfitsUnlocked: Int, affiliate: Bool = false) -> ProductUnlock {
    let id = UUID()
    let url = URL(string: "https://example.com/products/\(id.uuidString)") ?? URL(fileURLWithPath: "/")
    return ProductUnlock(
        candidate: ProductCandidate(
            id: id,
            canonicalURL: url,
            retailer: "Example",
            name: name,
            category: .shoes,
            affiliateURL: affiliate ? url : nil,
            lastCheckedAt: .now
        ),
        outfitsUnlocked: outfitsUnlocked
    )
}

/// Only `fetchOutfits` / public looks are in scope for Discover's list.
private final class DiscoverOutfitStub: OutfitRepository, @unchecked Sendable {
    private let outfits: [Outfit]
    private let publicLooks: [Outfit]

    init(outfits: [Outfit], publicLooks: [Outfit] = []) {
        self.outfits = outfits
        self.publicLooks = publicLooks
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
    func fetchPublicWornLooks() async throws -> [Outfit] { publicLooks }
    func reportLookbook(outfitID: UUID) async throws {}
}

private actor EmptyShoppingStub: ShoppingRepository {
    func extractProduct(from url: URL) async throws -> ProductCandidate {
        throw AstraError.unimplemented("unused")
    }
    func evaluateProduct(candidateID: UUID) async throws -> ProductEvaluation {
        throw AstraError.unimplemented("unused")
    }
    func fetchProductCandidate(id: UUID) async throws -> ProductCandidate {
        throw AstraError.unimplemented("unused")
    }
    private(set) var curatedCalls = 0
    func fetchCuratedProducts(category: ClothingCategory?) async throws -> [ProductCandidate] {
        curatedCalls += 1
        return []
    }
    func fetchUnlocks() async throws -> [ProductUnlock] { [] }
    func fetchWishlist() async throws -> [ProductCandidate] { [] }
    func addToWishlist(candidateID: UUID) async throws {}
    func removeFromWishlist(candidateID: UUID) async throws {}
    func markPurchased(candidateID: UUID) async throws {}
}

private actor UnlocksShoppingStub: ShoppingRepository {
    private let unlocks: [ProductUnlock]

    init(_ unlocks: [ProductUnlock]) {
        self.unlocks = unlocks
    }

    func extractProduct(from url: URL) async throws -> ProductCandidate {
        throw AstraError.unimplemented("unused")
    }
    func evaluateProduct(candidateID: UUID) async throws -> ProductEvaluation {
        throw AstraError.unimplemented("unused")
    }
    func fetchProductCandidate(id: UUID) async throws -> ProductCandidate {
        throw AstraError.unimplemented("unused")
    }
    private(set) var curatedCalls = 0
    func fetchCuratedProducts(category: ClothingCategory?) async throws -> [ProductCandidate] {
        curatedCalls += 1
        return []
    }
    func fetchUnlocks() async throws -> [ProductUnlock] { unlocks }
    func fetchWishlist() async throws -> [ProductCandidate] { [] }
    func addToWishlist(candidateID: UUID) async throws {}
    func removeFromWishlist(candidateID: UUID) async throws {}
    func markPurchased(candidateID: UUID) async throws {}
}
