//
//  GuestMigrationServiceTests.swift
//  AstraStyleTests
//
//  Spec §7 "Guest migration to account"; ADR 0011. Confirms
//  `LiveGuestMigrationService` moves every local guest item to the account
//  under the *authenticated session's* id (never a client-supplied one),
//  clears local guest state on full success, and — on a partial failure —
//  retains exactly what wasn't migrated rather than dropping it.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("GuestMigrationService — spec §7 guest migration to account")
struct GuestMigrationServiceTests {

    /// Creates `count` guest items with strictly increasing `createdAt`
    /// timestamps (rather than the default `.now`, which could tie under
    /// clock resolution) so `GuestClosetStore.items(for:)`'s
    /// newest-first ordering — and therefore the order
    /// `LiveGuestMigrationService` processes them in — is deterministic for
    /// the partial-failure test below.
    private func makeGuestItems(count: Int, guestRepository: GuestClosetRepository) async throws -> [ClosetItem] {
        var created: [ClosetItem] = []
        let base = Date.now
        for index in 1...count {
            created.append(
                try await guestRepository.createItem(
                    ClosetItem(id: UUID(), userID: UUID(), name: "Item \(index)", category: .top, createdAt: base.addingTimeInterval(Double(index))),
                    images: []
                )
            )
        }
        return created
    }

    @Test("Migration moves every local item to the account and clears local guest state")
    func migrationMovesItemsAndClearsGuestState() async throws {
        let guestID = UUID()
        let realUserID = UUID()
        let store = InMemoryGuestClosetStore()
        let guestRepository = GuestClosetRepository(store: store, currentGuestUserID: { guestID })
        _ = try await makeGuestItems(count: 5, guestRepository: guestRepository)

        let liveRepository = MockClosetRepository(items: [])
        let service = LiveGuestMigrationService(closetRepository: liveRepository, guestClosetStore: store)
        let session = AuthSession(userID: realUserID, accessToken: "token", refreshToken: "refresh-token", expiresAt: .distantFuture)

        let result = await service.migrateClosetItems(guestUserID: guestID, to: session)

        #expect(result.migratedItemCount == 5)
        #expect(result.remainingItemCount == 0)
        #expect(result.isComplete)

        let remainingLocal = await store.items(for: guestID)
        #expect(remainingLocal.isEmpty)

        let migrated = try await liveRepository.fetchItems()
        #expect(migrated.count == 5)
        #expect(migrated.allSatisfy { $0.userID == realUserID })
    }

    @Test("Ownership of migrated items comes from the authenticated session, not the guest record")
    func migratedItemsAreOwnedByTheNewSessionNotTheOldGuestRecord() async throws {
        let guestID = UUID()
        let realUserID = UUID()
        let store = InMemoryGuestClosetStore()
        let guestRepository = GuestClosetRepository(store: store, currentGuestUserID: { guestID })
        _ = try await makeGuestItems(count: 1, guestRepository: guestRepository)

        let liveRepository = MockClosetRepository(items: [])
        let service = LiveGuestMigrationService(closetRepository: liveRepository, guestClosetStore: store)
        let session = AuthSession(userID: realUserID, accessToken: "token", refreshToken: "refresh-token", expiresAt: .distantFuture)

        _ = await service.migrateClosetItems(guestUserID: guestID, to: session)

        let migrated = try await liveRepository.fetchItems()
        #expect(migrated.count == 1)
        #expect(migrated.first?.userID == realUserID)
        #expect(migrated.first?.userID != guestID)
    }

    @Test("A partial failure retains the unmigrated remainder locally instead of dropping it")
    func partialFailureRetainsRemainingItems() async throws {
        let guestID = UUID()
        let realUserID = UUID()
        let store = InMemoryGuestClosetStore()
        let guestRepository = GuestClosetRepository(store: store, currentGuestUserID: { guestID })
        let created = try await makeGuestItems(count: 3, guestRepository: guestRepository)

        let failingRepository = FailingAfterNClosetRepository(successCount: 1)
        let service = LiveGuestMigrationService(closetRepository: failingRepository, guestClosetStore: store)
        let session = AuthSession(userID: realUserID, accessToken: "token", refreshToken: "refresh-token", expiresAt: .distantFuture)

        let result = await service.migrateClosetItems(guestUserID: guestID, to: session)

        #expect(result.migratedItemCount == 1)
        #expect(result.remainingItemCount == 2)
        #expect(!result.isComplete)

        let remainingLocal = await store.items(for: guestID)
        #expect(remainingLocal.count == 2)
        // `GuestClosetStore.items(for:)` returns newest-first, so the
        // single success is the most-recently-created item (`created.last`)
        // and the two left behind are the two oldest — the specific items
        // left behind are exactly the ones that never succeeded, nothing
        // was migrated twice or lost.
        #expect(Set(remainingLocal.map(\.id)) == Set(created.dropLast().map(\.id)))
    }

    @Test("No guest items to migrate resolves cleanly with zero counts")
    func emptyGuestClosetMigratesCleanly() async throws {
        let guestID = UUID()
        let realUserID = UUID()
        let store = InMemoryGuestClosetStore()
        let liveRepository = MockClosetRepository(items: [])
        let service = LiveGuestMigrationService(closetRepository: liveRepository, guestClosetStore: store)
        let session = AuthSession(userID: realUserID, accessToken: "token", refreshToken: "refresh-token", expiresAt: .distantFuture)

        let result = await service.migrateClosetItems(guestUserID: guestID, to: session)

        #expect(result.migratedItemCount == 0)
        #expect(result.remainingItemCount == 0)
        #expect((try? await liveRepository.fetchItems())?.isEmpty == true)
    }
}

/// A `ClosetRepository` double that succeeds `successCount` times, then
/// fails every call after that — used to simulate a migration interrupted
/// partway through (a network drop, the app backgrounded mid-upload).
private actor FailingAfterNClosetRepository: ClosetRepository {
    private var successesRemaining: Int
    private(set) var createdItems: [ClosetItem] = []

    init(successCount: Int) {
        successesRemaining = successCount
    }

    func fetchItems() async throws -> [ClosetItem] { createdItems }
    func fetchItem(id: UUID) async throws -> ClosetItem { throw AstraError.server("Not implemented in this test double.") }
    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] { [] }
    func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        throw AstraError.server("Not implemented in this test double.")
    }
    func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch { ClosetItemAnalysisBatch(results: []) }

    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        guard successesRemaining > 0 else {
            throw AstraError.network("Simulated upload failure.")
        }
        successesRemaining -= 1
        createdItems.append(item)
        return item
    }

    func updateItem(_ item: ClosetItem) async throws -> ClosetItem { item }
    func archiveItem(id: UUID) async throws {}
    func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem { throw AstraError.server("Not implemented in this test double.") }
    func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem { throw AstraError.server("Not implemented in this test double.") }
    func fetchWardrobeScore() async throws -> WardrobeScore { throw AstraError.server("Not implemented in this test double.") }
}
