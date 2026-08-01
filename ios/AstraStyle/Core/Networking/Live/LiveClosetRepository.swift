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
//  Offline behaviour (spec §7 "Local edits queue for sync"), stated
//  precisely, because the previous version of this comment was not true:
//
//  * `createItem` and `updateItem` fall back to `OfflineMutationQueue` when
//    the write fails, and return the local value so the UI stays consistent.
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
    private let apiClient: AstraAPIClient
    private let supabase: SupabaseClient
    private let offlineQueue: OfflineMutationQueue
    private let writer: any ClosetWriting

    /// Guards against two concurrent drains replaying the same mutation
    /// twice. `drain(apply:)` suspends inside the queue actor while `apply`
    /// runs, which lets a second drain observe a mutation that the first has
    /// applied but not yet removed. A lock here is enough because a drain
    /// never triggers another drain — replay goes straight to `writer`.
    private let drainLock = NSLock()
    private var isDraining = false

    public convenience init(
        apiClient: AstraAPIClient,
        offlineQueue: OfflineMutationQueue,
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)
    ) {
        self.init(
            apiClient: apiClient,
            offlineQueue: offlineQueue,
            supabase: supabase,
            writer: SupabaseClosetWriter(supabase: supabase)
        )
    }

    /// Internal so tests can substitute the writer and drive the offline
    /// queueing/replay behaviour without a live Supabase project.
    init(
        apiClient: AstraAPIClient,
        offlineQueue: OfflineMutationQueue,
        supabase: SupabaseClient,
        writer: any ClosetWriting
    ) {
        self.apiClient = apiClient
        self.offlineQueue = offlineQueue
        self.supabase = supabase
        self.writer = writer
    }

    public func fetchItems() async throws -> [ClosetItem] {
        do {
            let items: [ClosetItem] = try await supabase.from("closet_items")
                .select()
                .is("archived_at", value: nil)
                .order("created_at", ascending: false)
                .execute()
                .value
            // A successful read is the cheapest reliable signal that the
            // network is back, and the closet list is the screen a returning
            // user lands on — so it is the natural moment to flush anything
            // that was written while offline.
            await drainPendingMutations()
            return items
        } catch {
            throw AstraError.network("Couldn't load your closet. Showing your last saved copy if available.")
        }
    }

    public func fetchItem(id: UUID) async throws -> ClosetItem {
        do {
            return try await supabase.from("closet_items").select().eq("id", value: id).single().execute().value
        } catch {
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

    /// The wire element both analyze endpoints take: the uploaded object's
    /// path plus the correlation id the server must echo back. Image bytes
    /// go to Storage, never into the JSON body (`docs/08` §2's
    /// `imageStoragePath`, "signed, private Supabase Storage path — never a
    /// public URL").
    private struct AnalyzeRequestElement: Encodable, Sendable {
        let requestID: UUID
        let storagePath: String
        let imageType: ClosetImageType
        let deviceHints: GarmentDeviceHints?

        enum CodingKeys: String, CodingKey {
            case requestID = "request_id"
            case storagePath = "storage_path"
            case imageType = "image_type"
            case deviceHints = "device_hints"
        }
    }

    private func uploadedElement(for request: ClosetItemAnalysisRequest) async throws -> AnalyzeRequestElement {
        AnalyzeRequestElement(
            requestID: request.id,
            storagePath: try await uploadCaptured(imageData: request.imageData),
            imageType: request.imageType,
            deviceHints: request.deviceHints
        )
    }

    public func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        try await apiClient.send(
            .analyzeClosetItem,
            body: uploadedElement(for: request),
            as: ClosetItemAnalysisResult.self
        )
    }

    public func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        struct BatchRequest: Encodable, Sendable {
            let items: [AnalyzeRequestElement]
        }
        // Uploads run in submission order rather than concurrently on
        // purpose: the upload leg is bandwidth-bound on a phone, and firing
        // N image uploads at once on a weak connection makes every one of
        // them slower and the first result later. Concurrency belongs on the
        // server side of this call (`docs/08` §2.3 recommends the provider's
        // own batch endpoint), where it does not compete for one uplink.
        var elements: [AnalyzeRequestElement] = []
        elements.reserveCapacity(requests.count)
        for request in requests {
            elements.append(try await uploadedElement(for: request))
        }
        return try await apiClient.send(
            .batchAnalyzeCloset,
            body: BatchRequest(items: elements),
            as: ClosetItemAnalysisBatch.self
        )
    }

    public func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        do {
            let created = try await writer.create(item, images: images)
            await drainPendingMutations()
            return created
        } catch {
            try await queueMutation(.create, item: item)
            return item
        }
    }

    public func updateItem(_ item: ClosetItem) async throws -> ClosetItem {
        do {
            let updated = try await writer.update(item)
            await drainPendingMutations()
            return updated
        } catch {
            try await queueMutation(.update, item: item)
            return item
        }
    }

    /// - Note: Does not queue. See this file's header for why archive, wear
    ///   and laundry writes surface their error instead.
    public func archiveItem(id: UUID) async throws {
        do {
            try await writer.archive(id: id)
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
    ///   The table is not the missing piece. `WardrobeScoring` (Domain/
    ///   Services) is a protocol plus the §10 weights with **no conforming
    ///   scorer anywhere**, so nothing in this repo can compute a score to
    ///   put in such a table; adding the migration would produce a table
    ///   that is permanently empty and a call that returns "no rows" instead
    ///   of "relation does not exist" — the same blank module, with more
    ///   schema to maintain. Implement the scorer (P4-OUTFIT-10) and then
    ///   the table, in that order.
    public func fetchWardrobeScore() async throws -> WardrobeScore {
        throw AstraError.unimplemented(
            String(localized: "Your Wardrobe Score isn't ready yet.")
        )
    }

    // MARK: - Helpers

    /// Uploads one captured image and returns its storage path.
    ///
    /// Two things here are load-bearing and were both wrong before:
    ///
    /// 1. The bucket is `user-content`. There is exactly one bucket
    ///    (`20260728101000_storage_buckets.sql`) and it is not called
    ///    "closet" — `closet` is a folder *inside* it, which is the whole
    ///    point of the shared `users/{user_id}/...` prefix that migration
    ///    documents. Uploading to a nonexistent bucket fails outright.
    /// 2. The user id is lowercased. The four storage policies compare
    ///    `(storage.foldername(name))[2]` against `auth.uid()::text`, and
    ///    Postgres renders a uuid lowercase while Swift's
    ///    `UUID.uuidString` is UPPERCASE. Without `.lowercased()` the path
    ///    is well-formed, the bucket is right, and the insert is still
    ///    rejected by RLS — the most expensive kind of wrong, because it
    ///    looks correct in the debugger.
    ///
    /// The path has no `{closet_item_id}` segment (the migration's comment
    /// illustrates `users/{uid}/closet/{closet_item_id}/{image_id}.jpg`)
    /// because this runs during a scan, BEFORE the user has confirmed the
    /// analysis and a `ClosetItem` exists. Only segments [1] and [2] are
    /// policy-relevant, so this is a valid path under the same convention.
    private func uploadCaptured(imageData: Data) async throws -> String {
        do {
            let session = try await supabase.auth.session
            let userID = session.user.id.uuidString.lowercased()
            let path = "users/\(userID)/closet/\(UUID().uuidString.lowercased()).jpg"
            _ = try await supabase.storage
                .from("user-content")
                .upload(path, data: imageData, options: FileOptions(contentType: "image/jpeg"))
            return path
        } catch {
            throw AstraError.network("Couldn't upload that photo. Check your connection and try again.")
        }
    }

    /// Replays everything the offline queue is holding, oldest first.
    ///
    /// Called after every successful network call in this type. The queue
    /// stops at the first failure and counts an attempt against it, so a
    /// mutation that cannot apply blocks the ones behind it rather than
    /// letting a later write for the same item land first.
    func drainPendingMutations() async {
        guard beginDraining() else { return }
        defer { endDraining() }

        await offlineQueue.drain { [writer] mutation in
            // The queue is shared: `LiveOutfitRepository` enqueues `.outfit`
            // and `.outfitWear` into the same one. Those are not this type's
            // to replay, and neither failing on them (which would stop the
            // drain forever) nor applying them (which would corrupt data
            // through the wrong writer) is acceptable — so say "not mine" and
            // let them stay queued for their owner. NOTE: nothing drains
            // outfit mutations yet; see P1-CORE-06 in docs/03-progress.md.
            guard mutation.entity == .closetItem else { throw OfflineMutationNotHandled() }
            let item = try JSONDecoder.astraDefault.decode(ClosetItem.self, from: mutation.payloadData)
            switch mutation.operation {
            case .create: _ = try await writer.create(item, images: [])
            case .update: _ = try await writer.update(item)
            case .delete: try await writer.archive(id: item.id)
            }
        }
    }

    private func beginDraining() -> Bool {
        drainLock.lock()
        defer { drainLock.unlock() }
        if isDraining { return false }
        isDraining = true
        return true
    }

    private func endDraining() {
        drainLock.lock()
        isDraining = false
        drainLock.unlock()
    }

    private func queueMutation(_ operation: OfflineMutation.Operation, item: ClosetItem) async throws {
        let payload = try JSONEncoder.astraDefault.encode(item)
        await offlineQueue.enqueue(
            OfflineMutation(entity: .closetItem, operation: operation, payloadData: payload)
        )
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
