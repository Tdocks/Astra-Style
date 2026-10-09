//
//  LiveClosetRepositoryCacheTests.swift
//  AstraStyleTests
//
//  Ticket P3-CLOSET-02 — authenticated closet reads refresh
//  `ClosetItemCaching` on success and serve that cache when the network
//  fetch fails (spec §7 "Cached closet … remain viewable").
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("LiveClosetRepository local read cache")
struct LiveClosetRepositoryCacheTests {

    private actor FailingOfflineQueue: OfflineMutationQueue {
        func enqueue(_ mutation: OfflineMutation) async throws {
            throw AstraError.server("queue persistence failed")
        }
        func pendingMutations() async -> [OfflineMutation] { [] }
        func drain(apply: @Sendable (OfflineMutation) async throws -> Void) async {}
        func remove(id: UUID) async {}
        func clear() async {}
    }

    private actor StubClosetWriter: ClosetWriting {
        let failsWrites: Bool
        let remoteItem: ClosetItem?
        init(failsWrites: Bool = false, remoteItem: ClosetItem? = nil) {
            self.failsWrites = failsWrites
            self.remoteItem = remoteItem
        }
        func fetch(id: UUID) async throws -> ClosetItem? { remoteItem?.id == id ? remoteItem : nil }
        func create(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
            if failsWrites { throw AstraError.network("offline") }; return item
        }
        func update(_ item: ClosetItem) async throws -> ClosetItem {
            if failsWrites { throw AstraError.network("offline") }; return item
        }
        func archive(id: UUID) async throws {
            if failsWrites { throw AstraError.network("offline") }
        }
    }

    private func makeRepository(
        cache: InMemoryClosetItemCache,
        userID: UUID,
        fetcher: (@Sendable () async throws -> [ClosetItem])?,
        writer: StubClosetWriter = StubClosetWriter()
    ) -> LiveClosetRepository {
        LiveClosetRepository(
            apiClient: AstraAPIClient(environment: .preview),
            offlineQueue: InMemoryOfflineMutationQueue(),
            supabase: AstraSupabaseClientFactory.previewClient,
            writer: writer,
            cache: cache,
            currentUserID: { userID },
            activeItemsFetcher: fetcher
        )
    }

    private func item(userID: UUID, name: String) -> ClosetItem {
        ClosetItem(id: UUID(), userID: userID, name: name, category: .top)
    }

    @Test("A successful fetch writes through to the local cache")
    func successfulFetchCachesItems() async throws {
        let userID = UUID()
        let cache = InMemoryClosetItemCache()
        let navy = item(userID: userID, name: "Navy Crewneck")
        let repository = makeRepository(cache: cache, userID: userID) {
            [navy]
        }

        let fetched = try await repository.fetchItems()
        #expect(fetched.map(\.id) == [navy.id])

        let cached = await cache.items(for: userID)
        #expect(cached.map(\.id) == [navy.id])
        #expect(cached.first?.name == "Navy Crewneck")
    }

    @Test("An offline fetch returns the last cached closet instead of failing empty-handed")
    func offlineFetchServesCache() async throws {
        let userID = UUID()
        let cachedItem = item(userID: userID, name: "Cached Chore Coat")
        let cache = InMemoryClosetItemCache(seed: [cachedItem])
        let repository = makeRepository(cache: cache, userID: userID) {
            throw AstraError.network("offline")
        }

        let fetched = try await repository.fetchItems()
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == cachedItem.id)
        #expect(fetched.first?.name == "Cached Chore Coat")
    }

    @Test("An offline fetch with an empty cache still surfaces the network error")
    func offlineFetchWithEmptyCacheThrows() async throws {
        let userID = UUID()
        let cache = InMemoryClosetItemCache()
        let repository = makeRepository(cache: cache, userID: userID) {
            throw AstraError.network("offline")
        }

        do {
            _ = try await repository.fetchItems()
            Issue.record("Expected a network error when there is nothing cached")
        } catch let error as AstraError {
            #expect(error.category == .network)
        } catch {
            Issue.record("Expected AstraError.network, got \(error)")
        }
    }

    @Test("Archived cached rows are filtered out of the offline closet view")
    func offlineFetchOmitsArchivedCachedRows() async throws {
        let userID = UUID()
        var archived = item(userID: userID, name: "Archived Blazer")
        archived.archivedAt = .now
        let active = item(userID: userID, name: "Active Oxford")
        let cache = InMemoryClosetItemCache(seed: [archived, active])
        let repository = makeRepository(cache: cache, userID: userID) {
            throw AstraError.network("offline")
        }

        let fetched = try await repository.fetchItems()
        #expect(fetched.map(\.name) == ["Active Oxford"])
    }

    @Test("A successful create upserts into the cache")
    func successfulCreateUpdatesCache() async throws {
        let userID = UUID()
        let cache = InMemoryClosetItemCache()
        let repository = makeRepository(cache: cache, userID: userID, fetcher: nil)
        let garment = item(userID: userID, name: "Suede Chukkas")

        _ = try await repository.createItem(garment, images: [])

        let cached = await cache.items(for: userID)
        #expect(cached.map(\.id) == [garment.id])
    }

    @Test("A failed durable enqueue is surfaced and does not update the local cache")
    func failedQueuePersistenceDoesNotClaimCreateSuccess() async throws {
        let owner = UUID()
        let cache = InMemoryClosetItemCache()
        let garment = item(userID: owner, name: "Unqueued jacket")
        let repo = LiveClosetRepository(
            apiClient: AstraAPIClient(environment: .preview), offlineQueue: FailingOfflineQueue(),
            supabase: AstraSupabaseClientFactory.previewClient, writer: StubClosetWriter(failsWrites: true),
            cache: cache, currentUserID: { owner }, activeItemsFetcher: nil
        )

        await #expect(throws: AstraError.self) { try await repo.createItem(garment, images: []) }
        #expect(await cache.items(for: owner).isEmpty)
    }

    @Test("Failed durable enqueue surfaces update, archive, and laundry actions")
    func failedQueuePersistenceSurfacesClosetMutations() async throws {
        let owner = UUID()
        let garment = item(userID: owner, name: "Unqueued oxford")
        let cache = InMemoryClosetItemCache(seed: [garment])
        let repo = LiveClosetRepository(
            apiClient: AstraAPIClient(environment: .preview), offlineQueue: FailingOfflineQueue(),
            supabase: AstraSupabaseClientFactory.previewClient, writer: StubClosetWriter(failsWrites: true),
            cache: cache, currentUserID: { owner },
            activeItemsFetcher: { throw AstraError.network("offline") }
        )
        var edited = garment
        edited.name = "Unpersisted edit"
        edited.updatedAt = .now

        await #expect(throws: AstraError.self) { try await repo.updateItem(edited) }
        await #expect(throws: AstraError.self) { try await repo.archiveItem(id: garment.id) }
        await #expect(throws: AstraError.self) { try await repo.updateLaundryState(id: garment.id, state: .laundry) }
        let cached = await cache.items(for: owner)
        #expect(cached.count == 1)
        #expect(cached.first?.name == garment.name)
        #expect(cached.first?.laundryState == garment.laundryState)
        #expect(cached.first?.isArchived == false)
    }

    @Test("Offline archive is queued and hides the owned item optimistically")
    func offlineArchiveQueuesAndUpdatesCache() async throws {
        let owner = UUID()
        let garment = item(userID: owner, name: "Field jacket")
        let queue = InMemoryOfflineMutationQueue()
        let cache = InMemoryClosetItemCache(seed: [garment])
        let repo = LiveClosetRepository(
            apiClient: AstraAPIClient(environment: .preview), offlineQueue: queue,
            supabase: AstraSupabaseClientFactory.previewClient, writer: StubClosetWriter(failsWrites: true, remoteItem: garment),
            cache: cache, currentUserID: { owner }, activeItemsFetcher: { [] }
        )

        try await repo.archiveItem(id: garment.id)
        #expect((await queue.pendingMutations()).map(\.operation) == [.delete])
        #expect((await cache.items(for: owner)).first?.isArchived == true)
    }

    @Test("Offline laundry edit queues the full updated item")
    func offlineLaundryEditQueuesUpdatedItem() async throws {
        let owner = UUID()
        let garment = item(userID: owner, name: "Oxford")
        let queue = InMemoryOfflineMutationQueue()
        let cache = InMemoryClosetItemCache(seed: [garment])
        let repo = LiveClosetRepository(
            apiClient: AstraAPIClient(environment: .preview), offlineQueue: queue,
            supabase: AstraSupabaseClientFactory.previewClient, writer: StubClosetWriter(failsWrites: true, remoteItem: garment),
            cache: cache, currentUserID: { owner }, activeItemsFetcher: { throw AstraError.network("offline") }
        )

        let updated = try await repo.updateLaundryState(id: garment.id, state: .laundry)
        #expect(updated.laundryState == .laundry)
        let pending = await queue.pendingMutations()
        #expect(pending.count == 1)
        let queued = try JSONDecoder.astraDefault.decode(ClosetItem.self, from: pending[0].payloadData)
        #expect(queued.laundryState == .laundry)
    }

    @Test("A server refresh preserves a queued local update in its returned snapshot")
    func refreshPreservesPendingUpdate() async throws {
        let owner = UUID()
        let server = item(userID: owner, name: "Server name")
        var local = server
        local.name = "Offline edit"
        let queue = InMemoryOfflineMutationQueue()
        try await queue.enqueue(OfflineMutation(entity: .closetItem, operation: .update,
                                            payloadData: try JSONEncoder.astraDefault.encode(local)))
        let repo = LiveClosetRepository(
            apiClient: AstraAPIClient(environment: .preview), offlineQueue: queue,
            supabase: AstraSupabaseClientFactory.previewClient, writer: StubClosetWriter(failsWrites: true),
            cache: InMemoryClosetItemCache(), currentUserID: { owner }, activeItemsFetcher: { [server] }
        )
        let shown = try await repo.fetchItems()
        #expect(shown.first?.name == "Offline edit")
    }

    @Test("A queued archive stays out of the active fetch while remaining archived in cache")
    func refreshKeepsQueuedArchiveOutOfActiveItems() async throws {
        let owner = UUID()
        let garment = item(userID: owner, name: "Archived overshirt")
        var server = garment
        var localArchive = garment
        server.updatedAt = Date(timeIntervalSince1970: 1_000)
        let remote = server
        localArchive.updatedAt = Date(timeIntervalSince1970: 2_000)
        let queue = InMemoryOfflineMutationQueue()
        try await queue.enqueue(OfflineMutation(entity: .closetItem, operation: .delete,
                                            payloadData: try JSONEncoder.astraDefault.encode(localArchive)))
        let cache = InMemoryClosetItemCache()
        let repo = LiveClosetRepository(
            apiClient: AstraAPIClient(environment: .preview), offlineQueue: queue,
            supabase: AstraSupabaseClientFactory.previewClient, writer: StubClosetWriter(failsWrites: true, remoteItem: remote),
            cache: cache, currentUserID: { owner }, activeItemsFetcher: { [remote] }
        )

        let active = try await repo.fetchItems()
        #expect(active.isEmpty)
        #expect(await cache.items(for: owner).first?.isArchived == true)
        #expect(await queue.pendingMutations().count == 1)
    }
}
