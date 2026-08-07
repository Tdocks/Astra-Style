//
//  LiveOutfitRepositoryCacheTests.swift
//  AstraStyleTests
//
//  P4-OUTFIT-15 — "Reading outfits with no network connection returns
//  cached results" (spec §7). Mirrors
//  `Tests/UnitTests/LiveClosetRepositoryCacheTests.swift`'s coverage for
//  `fetchItems`, against `fetchOutfits`/`fetchOutfitItems`.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("LiveOutfitRepository local read cache")
struct LiveOutfitRepositoryCacheTests {

    private actor NeverCalledOutfitWriter: OutfitWriting {
        func updateOutfit(_ outfit: Outfit) async throws -> Outfit { outfit }
        func createWear(_ wear: OutfitWear) async throws -> OutfitWear { wear }
    }

    private func makeRepository(
        cache: InMemoryOutfitCache,
        userID: UUID,
        outfitsFetcher: (@Sendable () async throws -> [Outfit])? = nil,
        itemsFetcher: (@Sendable (UUID) async throws -> [OutfitItem])? = nil
    ) -> LiveOutfitRepository {
        LiveOutfitRepository(
            apiClient: AstraAPIClient(environment: .preview),
            offlineQueue: InMemoryOfflineMutationQueue(),
            supabase: AstraSupabaseClientFactory.previewClient,
            writer: NeverCalledOutfitWriter(),
            cache: cache,
            currentUserID: { userID },
            activeOutfitsFetcher: outfitsFetcher,
            activeOutfitItemsFetcher: itemsFetcher
        )
    }

    private func outfit(userID: UUID, name: String) -> Outfit {
        Outfit(id: UUID(), userID: userID, name: name)
    }

    // MARK: - fetchOutfits

    @Test("A successful fetch writes through to the local cache")
    func successfulFetchCachesOutfits() async throws {
        let userID = UUID()
        let cache = InMemoryOutfitCache()
        let weekend = outfit(userID: userID, name: "Weekend Errands")
        let repository = makeRepository(cache: cache, userID: userID, outfitsFetcher: { [weekend] })

        let fetched = try await repository.fetchOutfits()
        #expect(fetched.map(\.id) == [weekend.id])

        let cached = await cache.outfits(for: userID)
        #expect(cached.map(\.id) == [weekend.id])
        #expect(cached.first?.name == "Weekend Errands")
    }

    @Test("An offline fetch returns the last cached outfits instead of failing empty-handed")
    func offlineFetchServesCache() async throws {
        let userID = UUID()
        let cachedOutfit = outfit(userID: userID, name: "Cached Client Dinner")
        let cache = InMemoryOutfitCache(seed: [cachedOutfit])
        let repository = makeRepository(cache: cache, userID: userID, outfitsFetcher: {
            throw AstraError.network("offline")
        })

        let fetched = try await repository.fetchOutfits()
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == cachedOutfit.id)
        #expect(fetched.first?.name == "Cached Client Dinner")
    }

    @Test("An offline fetch with an empty cache still surfaces the network error")
    func offlineFetchWithEmptyCacheThrows() async throws {
        let userID = UUID()
        let cache = InMemoryOutfitCache()
        let repository = makeRepository(cache: cache, userID: userID, outfitsFetcher: {
            throw AstraError.network("offline")
        })

        do {
            _ = try await repository.fetchOutfits()
            Issue.record("Expected a network error when there is nothing cached")
        } catch let error as AstraError {
            #expect(error.category == .network)
        } catch {
            Issue.record("Expected AstraError.network, got \(error)")
        }
    }

    @Test("A list refresh preserves a still-listed outfit's already-cached items")
    func listRefreshPreservesCachedItems() async throws {
        let userID = UUID()
        let cache = InMemoryOutfitCache()
        let dinner = outfit(userID: userID, name: "Dinner Party")
        await cache.upsert(dinner, items: [
            OutfitItem(outfitID: dinner.id, closetItemID: UUID(), role: .top, sortOrder: 0)
        ])

        // The list endpoint never returns items — a second `fetchOutfits`
        // for the same outfit must not wipe what `fetchOutfitItems` already
        // cached for it.
        let repository = makeRepository(cache: cache, userID: userID, outfitsFetcher: { [dinner] })
        _ = try await repository.fetchOutfits()

        let items = await cache.items(forOutfit: dinner.id)
        #expect(items.count == 1)
    }

    @Test("A list refresh drops an outfit (and its items) the server no longer lists")
    func listRefreshDropsDeletedOutfits() async throws {
        let userID = UUID()
        let cache = InMemoryOutfitCache()
        let deleted = outfit(userID: userID, name: "No Longer There")
        await cache.upsert(deleted, items: [
            OutfitItem(outfitID: deleted.id, closetItemID: UUID(), role: .top, sortOrder: 0)
        ])

        let repository = makeRepository(cache: cache, userID: userID, outfitsFetcher: { [] })
        _ = try await repository.fetchOutfits()

        #expect(await cache.outfits(for: userID).isEmpty)
        #expect(await cache.items(forOutfit: deleted.id).isEmpty)
    }

    // MARK: - fetchOutfitItems

    @Test("A successful item fetch caches the items for that outfit")
    func successfulItemFetchCachesItems() async throws {
        let userID = UUID()
        let cache = InMemoryOutfitCache()
        let look = outfit(userID: userID, name: "Gallery Opening")
        await cache.upsert(look, items: nil)
        let shoes = OutfitItem(outfitID: look.id, closetItemID: UUID(), role: .shoes, sortOrder: 0)

        let repository = makeRepository(cache: cache, userID: userID, itemsFetcher: { _ in [shoes] })
        let fetched = try await repository.fetchOutfitItems(outfitID: look.id)

        #expect(fetched.map(\.role) == [.shoes])
        let cached = await cache.items(forOutfit: look.id)
        #expect(cached.map(\.role) == [.shoes])
    }

    @Test("An offline item fetch returns the last cached items")
    func offlineItemFetchServesCache() async throws {
        let userID = UUID()
        let cache = InMemoryOutfitCache()
        let look = outfit(userID: userID, name: "Rainy Commute")
        let top = OutfitItem(outfitID: look.id, closetItemID: UUID(), role: .top, sortOrder: 0)
        await cache.upsert(look, items: [top])

        let repository = makeRepository(cache: cache, userID: userID, itemsFetcher: { _ in
            throw AstraError.network("offline")
        })
        let fetched = try await repository.fetchOutfitItems(outfitID: look.id)

        #expect(fetched.map(\.role) == [.top])
    }

    @Test("An offline item fetch with nothing cached surfaces the server error")
    func offlineItemFetchWithEmptyCacheThrows() async throws {
        let userID = UUID()
        let cache = InMemoryOutfitCache()
        let repository = makeRepository(cache: cache, userID: userID, itemsFetcher: { _ in
            throw AstraError.server("down")
        })

        do {
            _ = try await repository.fetchOutfitItems(outfitID: UUID())
            Issue.record("Expected a server error when there is nothing cached")
        } catch let error as AstraError {
            #expect(error.category == .server)
        } catch {
            Issue.record("Expected AstraError.server, got \(error)")
        }
    }
}
