//
//  FreeTierClosetCapTests.swift
//  AstraStyleTests
//
//  Ticket P3-CLOSET-11 — free-tier 30-item closet cap (spec §16), enforced
//  at the `ClosetRepository` boundary via `FreeTierCappedClosetRepository`.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Free-tier closet cap — spec §16 30-item limit")
struct FreeTierClosetCapTests {

    private func makeItem(userID: UUID = UUID(), name: String) -> ClosetItem {
        ClosetItem(id: UUID(), userID: userID, name: name, category: .top)
    }

    private func seed(_ repository: MockClosetRepository, count: Int, userID: UUID) async throws {
        for index in 1...count {
            _ = try await repository.createItem(makeItem(userID: userID, name: "Seed \(index)"), images: [])
        }
    }

    @Test("FreeTierLimits.maxClosetItems is exactly 30, per spec §16")
    func capConstantMatchesSpec() {
        #expect(FreeTierLimits.maxClosetItems == 30)
    }

    @Test("A batch that would not fit is refused BEFORE the vision spend, not at save")
    func batchIsRefusedBeforeAnalysisWhenItWouldNotFit() async throws {
        // The cap used to be checked only in `createItem`. A free-tier user
        // two items short of it could hand over twenty photographs, wait
        // through twenty vision calls, and be refused at the eighteenth save
        // — having paid, in real provider spend, for eighteen readings he
        // could never keep. Same cap, wrong end of the flow.
        let userID = UUID()
        let base = MockClosetRepository(items: [])
        try await seed(base, count: FreeTierLimits.maxClosetItems - 2, userID: userID)
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { false }
        )

        let requests = (0..<5).map { index in
            ClosetItemAnalysisRequest(imageData: Data([UInt8(index)]), storagePath: "p/\(index).jpg")
        }

        await #expect(throws: FreeTierClosetError.capReached(limit: FreeTierLimits.maxClosetItems)) {
            _ = try await repository.batchAnalyzeItems(requests)
        }
    }

    @Test("A batch that fits is passed straight through")
    func batchThatFitsIsAllowed() async throws {
        let userID = UUID()
        let base = MockClosetRepository(items: [])
        try await seed(base, count: FreeTierLimits.maxClosetItems - 5, userID: userID)
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { false }
        )

        let requests = (0..<5).map { index in
            ClosetItemAnalysisRequest(imageData: Data([UInt8(index)]), storagePath: "p/\(index).jpg")
        }
        let batch = try await repository.batchAnalyzeItems(requests)
        #expect(batch.results.count == 5)
    }

    @Test("A premium account is not capped on batch either")
    func premiumBatchIsUncapped() async throws {
        let userID = UUID()
        let base = MockClosetRepository(items: [])
        try await seed(base, count: FreeTierLimits.maxClosetItems, userID: userID)
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { true }
        )

        let requests = [ClosetItemAnalysisRequest(imageData: Data([0]), storagePath: "p/0.jpg")]
        let batch = try await repository.batchAnalyzeItems(requests)
        #expect(batch.results.count == 1)
    }

    @Test("The 30th item succeeds; the 31st is rejected with a typed free-tier error")
    func thirtiethSucceedsThirtyFirstIsRejected() async throws {
        let userID = UUID()
        let base = MockClosetRepository(items: [])
        try await seed(base, count: FreeTierLimits.maxClosetItems - 1, userID: userID)
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { false }
        )

        let thirtieth = try await repository.createItem(makeItem(userID: userID, name: "Item 30"), images: [])
        #expect(thirtieth.name == "Item 30")

        let afterThirty = try await repository.fetchItems()
        #expect(afterThirty.count == FreeTierLimits.maxClosetItems)

        do {
            _ = try await repository.createItem(makeItem(userID: userID, name: "Item 31"), images: [])
            Issue.record("Expected the 31st free-tier item to be rejected with FreeTierClosetError.capReached")
        } catch let error as FreeTierClosetError {
            #expect(error == .capReached(limit: FreeTierLimits.maxClosetItems))
        } catch {
            Issue.record("Expected FreeTierClosetError.capReached, got \(error)")
        }

        let afterRejection = try await repository.fetchItems()
        #expect(afterRejection.count == FreeTierLimits.maxClosetItems)
    }

    @Test("A premium-entitled session is never blocked by the free-tier cap")
    func premiumIsNeverBlocked() async throws {
        let userID = UUID()
        let base = MockClosetRepository(items: [])
        try await seed(base, count: FreeTierLimits.maxClosetItems, userID: userID)
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { true }
        )

        let extra = try await repository.createItem(
            makeItem(userID: userID, name: "Premium piece 31"),
            images: []
        )
        #expect(extra.name == "Premium piece 31")

        let items = try await repository.fetchItems()
        #expect(items.count == FreeTierLimits.maxClosetItems + 1)
    }

    @Test("Archiving an item frees a free-tier cap slot")
    func archivingFreesCapSlot() async throws {
        let userID = UUID()
        let base = MockClosetRepository(items: [])
        try await seed(base, count: FreeTierLimits.maxClosetItems, userID: userID)
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { false }
        )

        let existing = try await repository.fetchItems()
        let toArchive = try #require(existing.first)
        try await repository.archiveItem(id: toArchive.id)

        let replacement = try await repository.createItem(
            makeItem(userID: userID, name: "Replacement"),
            images: []
        )
        #expect(replacement.name == "Replacement")
    }

    @Test("An expired subscription fixture resolves as non-premium for the cap")
    func expiredSubscriptionFixtureIsNotEntitled() {
        let subscription = Subscription(userID: UUID(), status: .expired)
        #expect(subscription.isEntitledToPremium == false)
    }
}
