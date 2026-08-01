//
//  FreeTierClosetCapTests.swift
//  AstraStyleTests
//
//  Ticket P3-CLOSET-11 — free-tier 30-item closet cap (spec §16), enforced
//  at the `ClosetRepository` boundary via `FreeTierCappedClosetRepository`.
//  Guest 10-item coverage remains in `GuestClosetRepositoryTests`.
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

    @Test("GuestAware non-guest path still hits the free-tier wrapper")
    func guestAwareNonGuestHitsFreeTierCap() async throws {
        let userID = UUID()
        let guestRepository = GuestClosetRepository(
            store: InMemoryGuestClosetStore(),
            currentGuestUserID: { UUID() }
        )
        let base = MockClosetRepository(items: [])
        try await seed(base, count: FreeTierLimits.maxClosetItems, userID: userID)
        let capped = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { false }
        )
        let repository = GuestAwareClosetRepository(
            isGuest: { false },
            guestRepository: guestRepository,
            liveRepository: capped
        )

        do {
            _ = try await repository.createItem(makeItem(userID: userID, name: "Over cap"), images: [])
            Issue.record("Expected free-tier cap through GuestAwareClosetRepository")
        } catch let error as FreeTierClosetError {
            #expect(error == .capReached(limit: FreeTierLimits.maxClosetItems))
        }
    }

    @Test("An expired subscription fixture resolves as non-premium for the cap")
    func expiredSubscriptionFixtureIsNotEntitled() {
        let subscription = Subscription(userID: UUID(), status: .expired)
        #expect(subscription.isEntitledToPremium == false)
    }
}
