//
//  LiveKyraRepository.swift
//  AstraStyle
//
//  `kyra_threads` / `kyra_messages` / `style_memories` reads go through
//  Postgrest; sending a message is an orchestration call (spec §14
//  `kyra/respond`) since it invokes `StylistReasoningProvider` and Kyra's
//  server-side tool calls (spec §11).
//

import Foundation
import Supabase

public final class LiveKyraRepository: KyraRepository, @unchecked Sendable {
    private let apiClient: AstraAPIClient
    private let supabase: SupabaseClient
    private let weatherService: WeatherService

    public init(
        apiClient: AstraAPIClient,
        weatherService: WeatherService,
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)
    ) {
        self.apiClient = apiClient
        self.weatherService = weatherService
        self.supabase = supabase
    }

    public func fetchThreads() async throws -> [KyraThread] {
        do {
            return try await supabase.from("kyra_threads")
                .select()
                .order("last_message_at", ascending: false)
                .execute()
                .value
        } catch {
            throw AstraError.network("Couldn't load your conversations with Kyra.")
        }
    }

    public func fetchMessages(threadID: UUID) async throws -> [KyraMessage] {
        do {
            return try await supabase.from("kyra_messages")
                .select()
                .eq("thread_id", value: threadID)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't load that conversation.")
        }
    }

    public func send(threadID: UUID?, message: KyraOutgoingMessage) async throws -> KyraMessage {
        // Read-only and never prompts. The same WeatherService instance feeds
        // Home, so Kyra cannot answer from a different forecast. When location
        // is unavailable the body sends null and the server tool says so.
        let weather: WeatherSnapshot?
        if weatherService.currentAuthorization() == .authorized {
            weather = try? await weatherService.currentSnapshot()
        } else {
            weather = nil
        }
        let body = KyraRespondBody(threadID: threadID, message: message, weatherSnapshot: weather)
        return try await apiClient.send(.kyraRespond, body: body, as: KyraMessage.self)
    }

    public func fetchMemories() async throws -> [StyleMemory] {
        do {
            return try await supabase.from("style_memories")
                .select()
                .eq("is_user_visible", value: true)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't load your style memories.")
        }
    }

    public func confirmMemoryProposal(_ proposal: KyraMemoryProposal, sourceMessageID: UUID) async throws -> StyleMemory {
        do {
            let session = try await supabase.auth.session
            let memory = StyleMemory(
                id: UUID(),
                userID: session.user.id,
                memoryType: proposal.memoryType,
                content: proposal.content,
                confidence: proposal.confidence,
                sourceMessageID: sourceMessageID
            )
            return try await supabase.from("style_memories").insert(memory).select().single().execute().value
        } catch {
            throw AstraError.server("Couldn't save that preference.")
        }
    }

    public func deleteMemory(id: UUID) async throws {
        do {
            try await supabase.from("style_memories").delete().eq("id", value: id).execute()
        } catch {
            throw AstraError.network("Couldn't delete that memory while offline.")
        }
    }
}

/// `POST /kyra/respond` request body (spec §6.20 input kinds -> §11
/// context packet's "Requested task").
private struct KyraRespondBody: Encodable, Sendable {
    let threadID: UUID?
    let text: String
    let attachments: [AttachmentBody]
    let weatherSnapshot: WeatherSnapshot?

    init(threadID: UUID?, message: KyraOutgoingMessage, weatherSnapshot: WeatherSnapshot?) {
        self.threadID = threadID
        self.text = message.text
        self.attachments = message.attachments.map(AttachmentBody.init)
        self.weatherSnapshot = weatherSnapshot
    }

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case text
        case attachments
        case weatherSnapshot = "weather_snapshot"
    }

    struct AttachmentBody: Encodable, Sendable {
        let type: String
        let value: String

        init(_ attachment: KyraOutgoingMessage.Attachment) {
            switch attachment {
            case .photo(let storagePath):
                type = "photo"
                value = storagePath
            case .productLink(let url):
                type = "product_link"
                value = url.absoluteString
            case .closetItem(let closetItemID):
                type = "closet_item"
                value = closetItemID.uuidString
            case .outfit(let outfitID):
                type = "outfit"
                value = outfitID.uuidString
            }
        }
    }
}
