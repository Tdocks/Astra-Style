//
//  FreeTierClosetCapTests.swift
//  AstraStyleTests
//
//  Ticket P3-CLOSET-11 — free-tier 30-item closet cap (spec §16), enforced
//  at the `ClosetRepository` boundary via `FreeTierCappedClosetRepository`.
//

import Foundation
import Supabase
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

    @Test("Guest limit becomes the Free limit on the same live repository")
    func guestToFreeTransitionUpdatesCapWithoutReinstall() async throws {
        let userID = UUID()
        let base = MockClosetRepository(items: [])
        try await seed(base, count: GuestLimits.maxClosetItems, userID: userID)
        let entitlement = MutableClosetEntitlement(isPremium: false, isAnonymous: true)
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { await entitlement.isPremium },
            isAnonymous: { await entitlement.isAnonymous }
        )

        await #expect(throws: FreeTierClosetError.capReached(limit: GuestLimits.maxClosetItems)) {
            _ = try await repository.createItem(makeItem(userID: userID, name: "Guest limit"), images: [])
        }
        await entitlement.setAnonymous(false)
        for index in (GuestLimits.maxClosetItems + 1)...FreeTierLimits.maxClosetItems {
            _ = try await repository.createItem(makeItem(userID: userID, name: "Free \(index)"), images: [])
        }
        #expect(try await repository.fetchItems().count == FreeTierLimits.maxClosetItems)
    }

    @Test("Premium expiry changes the same live repository to Free limits")
    func premiumExpiryUpdatesCapWithoutReinstall() async throws {
        let userID = UUID()
        let base = MockClosetRepository(items: [])
        try await seed(base, count: FreeTierLimits.maxClosetItems, userID: userID)
        let entitlement = MutableClosetEntitlement(isPremium: true, isAnonymous: false)
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { await entitlement.isPremium }
        )

        _ = try await repository.createItem(makeItem(userID: userID, name: "Premium extra"), images: [])
        await entitlement.setPremium(false)
        await #expect(throws: FreeTierClosetError.capReached(limit: FreeTierLimits.maxClosetItems)) {
            _ = try await repository.createItem(makeItem(userID: userID, name: "After expiry"), images: [])
        }
        #expect(try await repository.fetchItems().count == FreeTierLimits.maxClosetItems + 1)
    }

    @Test("The free-tier wrapper forwards the server-owned scan unlock count")
    func scanUnlockCountPassesThroughWrapper() async throws {
        let base = MockClosetRepository(items: [])
        let item = makeItem(name: "Saved coat")
        await base.setScanUnlockCountResult(.count(4), for: item.id)
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { false }
        )

        let result = try await repository.fetchScanUnlockCount(savedItemID: item.id)
        #expect(result == .count(4))
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

    @Test("A free account at its cap cannot restore an archived item")
    func restoreIsBlockedAtCapAndArchivedDataRemains() async throws {
        let userID = UUID()
        let base = MockClosetRepository(items: [])
        try await seed(base, count: FreeTierLimits.maxClosetItems, userID: userID)
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { false }
        )
        let seededItems = try await base.fetchItems()
        let archived = try #require(seededItems.first)
        try await base.archiveItem(id: archived.id)
        let fillers = makeItem(userID: userID, name: "Over-cap restoration fixture")
        _ = try await base.createItem(fillers, images: [])

        var restore = try await base.fetchItem(id: archived.id)
        restore.archivedAt = nil
        await #expect(throws: FreeTierClosetError.capReached(limit: FreeTierLimits.maxClosetItems)) {
            _ = try await repository.updateItem(restore)
        }

        #expect(try await base.fetchItem(id: archived.id).isArchived)
    }

    @Test("Existing active items remain editable after Premium lapses above the cap")
    func editingExistingOverCapItemRemainsAllowed() async throws {
        let userID = UUID()
        let base = MockClosetRepository(items: [])
        try await seed(base, count: FreeTierLimits.maxClosetItems + 1, userID: userID)
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { false }
        )
        let seededItems = try await base.fetchItems()
        let original = try #require(seededItems.first)
        var edited = original
        edited.name = "Still editable"

        let saved = try await repository.updateItem(edited)
        #expect(saved.name == "Still editable")
        #expect(try await base.fetchItems().count == FreeTierLimits.maxClosetItems + 1)
    }

    @Test("An anonymous guest uses the 10-item cap when restoring")
    func guestRestoreUsesGuestCap() async throws {
        let userID = UUID()
        let base = MockClosetRepository(items: [])
        try await seed(base, count: GuestLimits.maxClosetItems, userID: userID)
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { false },
            isAnonymous: { true }
        )
        let seededItems = try await base.fetchItems()
        let archived = try #require(seededItems.first)
        try await base.archiveItem(id: archived.id)
        _ = try await base.createItem(makeItem(userID: userID, name: "Guest replacement"), images: [])
        var restore = try await base.fetchItem(id: archived.id)
        restore.archivedAt = nil

        await #expect(throws: FreeTierClosetError.capReached(limit: GuestLimits.maxClosetItems)) {
            _ = try await repository.updateItem(restore)
        }
    }

    @Test("An expired subscription fixture resolves as non-premium for the cap")
    func expiredSubscriptionFixtureIsNotEntitled() {
        let subscription = Subscription(userID: UUID(), status: .expired)
        #expect(subscription.isEntitledToPremium == false)
    }
}

private actor MutableClosetEntitlement {
    private(set) var isPremium: Bool
    private(set) var isAnonymous: Bool

    init(isPremium: Bool, isAnonymous: Bool) {
        self.isPremium = isPremium
        self.isAnonymous = isAnonymous
    }

    func setPremium(_ value: Bool) { isPremium = value }
    func setAnonymous(_ value: Bool) { isAnonymous = value }
}

@Suite("Concurrent closet server quota errors")
struct ClosetServerQuotaErrorTests {
    private actor RejectingClosetWriter: ClosetWriting {
        let error: PostgrestError

        init(limit: Int) {
            error = PostgrestError(
                detail: #"{"limit":\#(limit),"active_count":\#(limit)}"#,
                code: "PT409",
                message: "closet_item_limit_reached"
            )
        }

        func fetch(id: UUID) async throws -> ClosetItem? { nil }
        func create(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem { throw error }
        func update(_ item: ClosetItem) async throws -> ClosetItem { throw error }
        func archive(id: UUID) async throws {}
    }

    private func makeRepository(
        ownerID: UUID,
        limit: Int
    ) -> (LiveClosetRepository, InMemoryOfflineMutationQueue) {
        let queue = InMemoryOfflineMutationQueue()
        let repository = LiveClosetRepository(
            apiClient: AstraAPIClient(environment: .preview),
            offlineQueue: queue,
            supabase: AstraSupabaseClientFactory.previewClient,
            writer: RejectingClosetWriter(limit: limit),
            cache: InMemoryClosetItemCache(),
            currentUserID: { ownerID }
        )
        return (repository, queue)
    }

    private func item(ownerID: UUID) -> ClosetItem {
        ClosetItem(id: UUID(), userID: ownerID, name: "Quota fixture", category: .top)
    }

    @Test("A concurrent create rejection is typed and never queued offline")
    func serverCreateCapRejectionDoesNotEnterOfflineQueue() async throws {
        let owner = UUID()
        let (repository, queue) = makeRepository(ownerID: owner, limit: FreeTierLimits.maxClosetItems)

        await #expect(throws: FreeTierClosetError.capReached(limit: FreeTierLimits.maxClosetItems)) {
            _ = try await repository.createItem(item(ownerID: owner), images: [])
        }

        #expect(await queue.pendingMutations().isEmpty)
    }

    @Test("A concurrent restore rejection is typed and never queued offline")
    func serverRestoreCapRejectionDoesNotEnterOfflineQueue() async throws {
        let owner = UUID()
        let original = item(ownerID: owner)
        var restored = ClosetItem(
            id: original.id,
            userID: owner,
            name: original.name,
            category: original.category,
            archivedAt: .now.addingTimeInterval(-60)
        )
        restored.archivedAt = nil
        let (repository, queue) = makeRepository(ownerID: owner, limit: GuestLimits.maxClosetItems)

        await #expect(throws: FreeTierClosetError.capReached(limit: GuestLimits.maxClosetItems)) {
            _ = try await repository.updateItem(restored)
        }

        #expect(await queue.pendingMutations().isEmpty)
    }
}
