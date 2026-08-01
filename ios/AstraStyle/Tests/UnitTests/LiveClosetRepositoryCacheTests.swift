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

    private actor StubClosetWriter: ClosetWriting {
        func fetch(id: UUID) async throws -> ClosetItem? { nil }
        func create(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem { item }
        func update(_ item: ClosetItem) async throws -> ClosetItem { item }
        func archive(id: UUID) async throws {}
    }

    private func makeRepository(
        cache: InMemoryClosetItemCache,
        userID: UUID,
        fetcher: (@Sendable () async throws -> [ClosetItem])?
    ) -> LiveClosetRepository {
        LiveClosetRepository(
            apiClient: AstraAPIClient(environment: .preview),
            offlineQueue: InMemoryOfflineMutationQueue(),
            supabase: AstraSupabaseClientFactory.previewClient,
            writer: StubClosetWriter(),
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
}
