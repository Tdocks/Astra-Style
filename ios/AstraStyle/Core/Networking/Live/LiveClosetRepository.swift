//
//  LiveClosetRepository.swift
//  AstraStyle
//
//  `closet_items` / `closet_item_images` reads and simple writes go
//  through Postgrest; image bytes go to the `user-content` Storage bucket
//  under `users/{user_id}/closet/...` (spec §15) before the analysis
//  Edge Functions are called with the resulting storage path, rather than
//  shipping raw image bytes through the JSON envelope.
//
//  Offline behaviour (spec §7 "Local edits queue for sync" / "Cached
//  closet … remain viewable"), stated precisely:
//
//  * `createItem` and `updateItem` fall back to `OfflineMutationQueue` when
//    the write fails, and return the local value so the UI stays consistent.
//  * Successful reads and writes refresh `ClosetItemCaching`
//    (`PersistedClosetItem` via `SwiftDataClosetItemCache`). A failed
//    `fetchItems` serves the last cached active closet when one exists, so
//    an authenticated offline cold start shows garments rather than only
//    an error state.
//  * `archiveItem`, `markWorn` and `updateLaundryState` do NOT queue yet —
//    the queue's payload is an encoded `ClosetItem`, and those three only
//    have an id (or need a read-modify-write) at the point of failure.
//    They surface the error instead of pretending to have succeeded.
//  * `drainPendingMutations()` replays the backlog and IS actually called:
//    after every successful `fetchItems`, `createItem`, `updateItem` and
//    `archiveItem`. That is what makes "connectivity coming back mid-session
//    flushes the backlog" true rather than aspirational — before this, the
//    header claimed it and nothing in the app called `drain(` at all.
//

import Foundation
import Supabase

public final class LiveClosetRepository: ClosetRepository, @unchecked Sendable {
    // Internal, not private: `LiveClosetRepository+Scan` is an extension in
    // another file, and Swift's `private` is file-scoped.
    let apiClient: AstraAPIClient
    let supabase: SupabaseClient
    let offlineQueue: OfflineMutationQueue
    let writer: any ClosetWriting
    let conflictRecorder: OfflineConflictRecording
    private let cache: ClosetItemCaching
    private let currentUserID: @Sendable () async -> UUID?
    /// Test seam: when non-nil, `fetchItems` uses this instead of Postgrest
    /// so cache write-through / offline fallback can be asserted without a
    /// live Supabase project.
    private let activeItemsFetcher: (@Sendable () async throws -> [ClosetItem])?

    /// Guards against two concurrent drains replaying the same mutation
    /// twice. `drain(apply:)` suspends inside the queue actor while `apply`
    /// runs, which lets a second drain observe a mutation that the first has
    /// applied but not yet removed. A lock here is enough because a drain
    /// never triggers another drain — replay goes straight to `writer`.
    /// Internal so `LiveClosetRepository+Offline` can share the flag.
    let drainLock = NSLock()
    var isDraining = false

    public convenience init(
        apiClient: AstraAPIClient,
        offlineQueue: OfflineMutationQueue,
        cache: ClosetItemCaching,
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)
    ) {
        self.init(
            apiClient: apiClient,
            offlineQueue: offlineQueue,
            supabase: supabase,
            writer: SupabaseClosetWriter(supabase: supabase),
            conflictRecorder: InMemoryOfflineConflictRecorder(),
            cache: cache,
            currentUserID: {
                // Lowercased elsewhere for Storage paths; UUID equality does
                // not care about string casing, so the session id is used as-is.
                try? await supabase.auth.session.user.id
            }
        )
    }

    /// Internal so tests can substitute the writer, cache, and fetcher and
    /// drive offline / cache behaviour without a live Supabase project.
    init(
        apiClient: AstraAPIClient,
        offlineQueue: OfflineMutationQueue,
        supabase: SupabaseClient,
        writer: any ClosetWriting,
        conflictRecorder: OfflineConflictRecording = InMemoryOfflineConflictRecorder(),
        cache: ClosetItemCaching = InMemoryClosetItemCache(),
        currentUserID: @escaping @Sendable () async -> UUID? = { nil },
        activeItemsFetcher: (@Sendable () async throws -> [ClosetItem])? = nil
    ) {
        self.apiClient = apiClient
        self.offlineQueue = offlineQueue
        self.supabase = supabase
        self.writer = writer
        self.conflictRecorder = conflictRecorder
        self.cache = cache
        self.currentUserID = currentUserID
        self.activeItemsFetcher = activeItemsFetcher
    }

    public func fetchItems() async throws -> [ClosetItem] {
        do {
            let items: [ClosetItem]
            if let activeItemsFetcher {
                items = try await activeItemsFetcher()
            } else {
                items = try await supabase.from("closet_items")
                    .select()
                    .is("archived_at", value: nil)
                    .order("created_at", ascending: false)
                    .execute()
                    .value
            }
            if let userID = await currentUserID() {
                await cache.replaceAll(items, for: userID)
            }
            // A successful read is the cheapest reliable signal that the
            // network is back, and the closet list is the screen a returning
            // user lands on — so it is the natural moment to flush anything
            // that was written while offline.
            await drainPendingMutations()
            return items
        } catch {
            if let userID = await currentUserID() {
                let cached = await cache.items(for: userID).filter { !$0.isArchived }
                if !cached.isEmpty {
                    return cached
                }
            }
            throw AstraError.network("Couldn't load your closet. Showing your last saved copy if available.")
        }
    }

    public func fetchItem(id: UUID) async throws -> ClosetItem {
        do {
            let item: ClosetItem = try await supabase.from("closet_items")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
            await cache.upsert(item)
            return item
        } catch {
            if let userID = await currentUserID(),
               let cached = await cache.items(for: userID).first(where: { $0.id == id }) {
                return cached
            }
            throw AstraError.server("Couldn't load that item.")
        }
    }

    public func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] {
        do {
            return try await supabase.from("closet_item_images")
                .select()
                .eq("closet_item_id", value: itemID)
                .order("is_primary", ascending: false)
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't load photos for that item.")
        }
    }

    public func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        do {
            let created = try await writer.create(item, images: images)
            await cache.upsert(created)
            await drainPendingMutations()
            return created
        } catch {
            try await queueMutation(.create, item: item)
            // Keep the offline cold-start cache coherent with what the UI
            // just accepted locally — otherwise a relaunch before reconnect
            // would hide a garment the user already "saved".
            await cache.upsert(item)
            return item
        }
    }

    public func updateItem(_ item: ClosetItem) async throws -> ClosetItem {
        do {
            let updated = try await writer.update(item)
            await cache.upsert(updated)
            await drainPendingMutations()
            return updated
        } catch {
            try await queueMutation(.update, item: item)
            await cache.upsert(item)
            return item
        }
    }

    /// - Note: Does not queue. See this file's header for why archive, wear
    ///   and laundry writes surface their error instead.
    public func archiveItem(id: UUID) async throws {
        do {
            try await writer.archive(id: id)
            if let userID = await currentUserID() {
                await cache.archive(id: id, for: userID, archivedAt: .now)
            }
            await drainPendingMutations()
        } catch {
            throw AstraError.network("Couldn't archive that item while offline. It will sync when you're back online.")
        }
    }

    public func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem {
        do {
            var item: ClosetItem = try await fetchItem(id: id)
            item.wearCount += 1
            item.lastWornAt = wornAt
            item.laundryState = .wornOnce
            return try await updateItem(item)
        } catch {
            throw AstraError.server("Couldn't record that wear.")
        }
    }

    public func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        do {
            return try await supabase.from("closet_items")
                .update(["laundry_state": state])
                .eq("id", value: id)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't update laundry status.")
        }
    }

    /// - Note: **Not implemented.** This used to `select()` from a
    ///   `wardrobe_scores` table that no migration in supabase/migrations
    ///   creates, so it failed on every call in production — invisibly,
    ///   because `HomeBriefProviding.fetchWardrobeScoreSafely()` does
    ///   `try?` and Home simply hides the module. The result was a screen
    ///   that has never once shown a real score and never reported why.
    ///
    ///   Updated 2026-08-07 (P4-HOME-04): the scorer itself is no longer
    ///   the missing piece — `computeWardrobeScore`
    ///   (`supabase/functions/_shared/scoring/wardrobeScore.ts`, P4-OUTFIT-10)
    ///   is implemented and unit-tested. What is still missing is
    ///   everything between here and it: no `closet/` route calls it (only
    ///   `analyze-item` / `batch-analyze` / `batch-status` are deployed —
    ///   see `closet/index.ts`), and there is still no `wardrobe_scores`
    ///   table (or any other persistence) for a route to write to or this
    ///   method to read from. `WardrobeScoring` (Domain/Services) — a
    ///   client-side protocol for an offline-safe estimate — still has no
    ///   conforming type either. Wiring an Edge Function route to the now-
    ///   real TypeScript scorer is P4-HOME-04's honest blocker, checked and
    ///   confirmed rather than assumed while building that ticket: do not
    ///   have this method fabricate a score from partial local data in the
    ///   meantime — an unmeasured composite that LOOKS measured is exactly
    ///   what "absent is honest; a confounded reading is not" forbids.
    public func fetchWardrobeScore() async throws -> WardrobeScore {
        throw AstraError.unimplemented(
            String(localized: "Your Wardrobe Score isn't ready yet.")
        )
    }

    public func migrateGuestLocalImages() async throws {
        struct ImageRow: Decodable, Sendable {
            let id: UUID
            let storagePath: String
            enum CodingKeys: String, CodingKey {
                case id
                case storagePath = "storage_path"
            }
        }
        let rows: [ImageRow]
        do {
            rows = try await supabase.from("closet_item_images")
                .select("id,storage_path")
                .like("storage_path", pattern: "\(GuestLocalImageStore.pathPrefix)%")
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't find guest photos to move into your account.")
        }
        for row in rows where GuestLocalImageStore.isLocal(row.storagePath) {
            guard let data = GuestLocalImageStore.jpegData(for: row.storagePath), !data.isEmpty else {
                continue
            }
            let remotePath: String
            do {
                remotePath = try await uploadCaptured(imageData: data)
            } catch {
                throw AstraError.network("Couldn't upload a closet photo after linking your account.")
            }
            do {
                try await supabase.from("closet_item_images")
                    .update(["storage_path": remotePath])
                    .eq("id", value: row.id)
                    .execute()
            } catch {
                throw AstraError.server("Couldn't attach that photo to your closet after linking.")
            }
            try? GuestLocalImageStore.delete(row.storagePath)
        }
    }
}

extension JSONEncoder {
    static let astraDefault: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let astraDefault: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
