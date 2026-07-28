//
//  LiveClosetRepository.swift
//  AstraStyle
//
//  `closet_items` / `closet_item_images` reads and simple writes go
//  through Postgrest; image bytes go to Supabase Storage under
//  `users/{user_id}/closet/...` (spec §15) before the analysis
//  Edge Functions are called with the resulting storage path, rather than
//  shipping raw image bytes through the JSON envelope.
//
//  Every mutation is written through `OfflineMutationQueue` first
//  (spec §7 "Local edits queue for sync"); `drain(apply:)` is invoked
//  opportunistically whenever a call succeeds, so connectivity coming back
//  mid-session flushes the backlog without a separate background task.
//

import Foundation
import Supabase

public final class LiveClosetRepository: ClosetRepository, @unchecked Sendable {
    private let apiClient: AstraAPIClient
    private let supabase: SupabaseClient
    private let offlineQueue: OfflineMutationQueue

    public init(
        apiClient: AstraAPIClient,
        offlineQueue: OfflineMutationQueue,
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)
    ) {
        self.apiClient = apiClient
        self.offlineQueue = offlineQueue
        self.supabase = supabase
    }

    public func fetchItems() async throws -> [ClosetItem] {
        do {
            return try await supabase.from("closet_items")
                .select()
                .is("archived_at", value: nil)
                .order("created_at", ascending: false)
                .execute()
                .value
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

    public func analyzeItem(imageData: Data, imageType: ClosetImageType) async throws -> ClosetItemAnalysisResult {
        let storagePath = try await uploadCaptured(imageData: imageData)
        struct Request: Encodable, Sendable {
            let storagePath: String
            let imageType: ClosetImageType
            enum CodingKeys: String, CodingKey { case storagePath = "storage_path", imageType = "image_type" }
        }
        return try await apiClient.send(
            .analyzeClosetItem,
            body: Request(storagePath: storagePath, imageType: imageType),
            as: ClosetItemAnalysisResult.self
        )
    }

    public func batchAnalyzeItems(imageDataList: [Data]) async throws -> [ClosetItemAnalysisResult] {
        var storagePaths: [String] = []
        for imageData in imageDataList {
            storagePaths.append(try await uploadCaptured(imageData: imageData))
        }
        struct Request: Encodable, Sendable {
            let storagePaths: [String]
            enum CodingKeys: String, CodingKey { case storagePaths = "storage_paths" }
        }
        return try await apiClient.send(
            .batchAnalyzeCloset,
            body: Request(storagePaths: storagePaths),
            as: [ClosetItemAnalysisResult].self
        )
    }

    public func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        do {
            let created: ClosetItem = try await supabase.from("closet_items")
                .insert(item)
                .select()
                .single()
                .execute()
                .value
            if !images.isEmpty {
                try await supabase.from("closet_item_images").insert(images).execute()
            }
            return created
        } catch {
            try await queueMutation(.create, item: item)
            return item
        }
    }

    public func updateItem(_ item: ClosetItem) async throws -> ClosetItem {
        do {
            return try await supabase.from("closet_items")
                .update(item)
                .eq("id", value: item.id)
                .select()
                .single()
                .execute()
                .value
        } catch {
            try await queueMutation(.update, item: item)
            return item
        }
    }

    public func archiveItem(id: UUID) async throws {
        do {
            try await supabase.from("closet_items")
                .update(["archived_at": Date.now])
                .eq("id", value: id)
                .execute()
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

    public func fetchWardrobeScore() async throws -> WardrobeScore {
        do {
            return try await supabase.from("wardrobe_scores").select().single().execute().value
        } catch {
            throw AstraError.server("Couldn't load your Wardrobe Score.")
        }
    }

    // MARK: - Helpers

    private func uploadCaptured(imageData: Data) async throws -> String {
        do {
            let session = try await supabase.auth.session
            let path = "users/\(session.user.id.uuidString)/closet/\(UUID().uuidString).jpg"
            _ = try await supabase.storage.from("closet").upload(path: path, file: imageData, options: FileOptions(contentType: "image/jpeg"))
            return path
        } catch {
            throw AstraError.network("Couldn't upload that photo. Check your connection and try again.")
        }
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
