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
    private let calendarService: CalendarService?
    private let historyCache: KyraHistoryCaching?

    public init(
        apiClient: AstraAPIClient,
        weatherService: WeatherService,
        calendarService: CalendarService? = nil,
        historyCache: KyraHistoryCaching? = nil,
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)
    ) {
        self.apiClient = apiClient
        self.weatherService = weatherService
        self.calendarService = calendarService
        self.historyCache = historyCache
        self.supabase = supabase
    }

    public func fetchThreads() async throws -> [KyraThread] {
        let ownerID = try await authenticatedOwnerID()
        do {
            let threads: [KyraThread] = try await supabase.from("kyra_threads")
                .select()
                .eq("user_id", value: ownerID)
                .order("last_message_at", ascending: false)
                .execute()
                .value
            guard threads.allSatisfy({ $0.userID == ownerID }) else {
                throw AstraError.auth("A conversation belongs to another account.")
            }
            try? await historyCache?.replaceThreads(threads, ownerID: ownerID)
            try await verifyActiveOwner(ownerID)
            return threads
        } catch {
            if Self.shouldFallbackToHistoryCache(for: error),
               let historyCache,
               let cached = try? await historyCache.cachedThreads(ownerID: ownerID) {
                try await verifyActiveOwner(ownerID)
                guard cached.allSatisfy({ $0.userID == ownerID }) else {
                    throw AstraError.auth("A saved conversation belongs to another account.")
                }
                return cached
            }
            if let error = error as? AstraError { throw error }
            if Self.shouldFallbackToHistoryCache(for: error) {
                throw AstraError.network("Couldn't load your conversations with Kyra.")
            }
            throw AstraError.server("Couldn't load your conversations with Kyra.")
        }
    }

    public func fetchMessages(threadID: UUID) async throws -> [KyraMessage] {
        let ownerID = try await authenticatedOwnerID()
        do {
            let messages: [KyraMessage] = try await supabase.from("kyra_messages")
                .select()
                .eq("user_id", value: ownerID)
                .eq("thread_id", value: threadID)
                .order("created_at", ascending: true)
                .execute()
                .value
            guard messages.allSatisfy({ $0.threadID == threadID }) else {
                throw AstraError.auth("A conversation message belongs to another thread.")
            }
            try? await historyCache?.replaceMessages(messages, threadID: threadID, ownerID: ownerID)
            try await verifyActiveOwner(ownerID)
            return messages
        } catch {
            if Self.shouldFallbackToHistoryCache(for: error),
               let historyCache,
               let cached = try? await historyCache.cachedMessages(threadID: threadID, ownerID: ownerID) {
                try await verifyActiveOwner(ownerID)
                guard cached.allSatisfy({ $0.threadID == threadID }) else {
                    throw AstraError.auth("A saved message belongs to another conversation.")
                }
                return cached
            }
            if let error = error as? AstraError { throw error }
            if Self.shouldFallbackToHistoryCache(for: error) {
                throw AstraError.network("Couldn't load that conversation.")
            }
            throw AstraError.server("Couldn't load that conversation.")
        }
    }

    private func authenticatedOwnerID() async throws -> UUID {
        do {
            return try await supabase.auth.session.user.id
        } catch {
            throw AstraError.auth("Sign in again to access your conversations.")
        }
    }

    private func verifyActiveOwner(_ expectedOwnerID: UUID) async throws {
        try Self.validateActiveOwner(expected: expectedOwnerID, actual: await authenticatedOwnerID())
    }

    static func validateActiveOwner(expected: UUID, actual: UUID) throws {
        guard actual == expected else {
            throw AstraError.auth("Your account changed while loading Kyra history.")
        }
    }

    static func shouldFallbackToHistoryCache(for error: Error) -> Bool {
        if let error = error as? AstraError {
            return error.category == .network
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code != URLError.cancelled.rawValue
    }

    public func send(threadID: UUID?, message: KyraOutgoingMessage) async throws -> KyraMessage {
        let ownerID = try await authenticatedOwnerID()
        // Read-only and never prompts. The same WeatherService instance feeds
        // Home, so Kyra cannot answer from a different forecast. When location
        // is unavailable the body sends null and the server tool says so.
        let weather: WeatherSnapshot?
        if weatherService.currentAuthorization() == .authorized {
            weather = try? await weatherService.currentSnapshot()
        } else {
            weather = nil
        }
        let schedule = await currentScheduleSnapshotIfAuthorized()
        let body = KyraRespondBody(
            threadID: threadID,
            message: message,
            weatherSnapshot: weather,
            scheduleSnapshot: schedule
        )
        try await verifyActiveOwner(ownerID)
        let reply = try await apiClient.send(.kyraRespond, body: body, as: KyraMessage.self)
        try await verifyActiveOwner(ownerID)
        // Refresh the authoritative transcript so the just-completed turn is
        // available for offline rereading. The extra read is best-effort and
        // cannot turn a successful paid response into a visible failure. The
        // assistant response alone is not enough to cache: the server owns
        // the canonical user-message ID. This never replays the provider call.
        _ = try? await fetchMessages(threadID: reply.threadID)
        try await verifyActiveOwner(ownerID)
        return reply
    }

    private func currentScheduleSnapshotIfAuthorized() async -> ScheduleSnapshot? {
        guard let calendarService, calendarService.currentAuthorization() == .authorized,
              let userID = try? await supabase.auth.session.user.id else { return nil }
        let calendar = Calendar.current
        guard let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: .now) else { return nil }
        let events = await calendarService.fetchUpcomingEvents(
            in: DateInterval(start: .now, end: end),
            userID: userID
        )
        return ScheduleSnapshotBuilder.build(from: events)
    }

    public func fetchMemories() async throws -> [StyleMemory] {
        let ownerID = try await authenticatedOwnerID()
        do {
            let memories: [StyleMemory] = try await supabase.from("style_memories")
                .select()
                .eq("user_id", value: ownerID)
                .eq("is_user_visible", value: true)
                .order("created_at", ascending: false)
                .execute()
                .value
            guard memories.allSatisfy({ $0.userID == ownerID }) else {
                throw AstraError.auth("A style memory belongs to another account.")
            }
            try await verifyActiveOwner(ownerID)
            return memories
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.server("Couldn't load your style memories.")
        }
    }

    public func confirmMemoryProposal(_ proposal: KyraMemoryProposal, sourceMessageID: UUID) async throws -> StyleMemory {
        do {
            let ownerID = try await authenticatedOwnerID()
            let memory = StyleMemory(
                id: UUID(),
                userID: ownerID,
                memoryType: proposal.memoryType,
                content: proposal.content,
                confidence: proposal.confidence,
                sourceMessageID: sourceMessageID
            )
            let saved: StyleMemory = try await supabase.from("style_memories").insert(memory).select().single().execute().value
            try await verifyActiveOwner(ownerID)
            return saved
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.server("Couldn't save that preference.")
        }
    }

    public func deleteMemory(id: UUID) async throws {
        let ownerID = try await authenticatedOwnerID()
        do {
            try await supabase.from("style_memories")
                .delete()
                .eq("id", value: id)
                .eq("user_id", value: ownerID)
                .execute()
            try await verifyActiveOwner(ownerID)
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.network("Couldn't delete that memory while offline.")
        }
    }
}

/// `POST /kyra/respond` request body (spec §6.20 input kinds -> §11
/// context packet's "Requested task").
struct KyraRespondBody: Encodable, Sendable {
    let threadID: UUID?
    let text: String
    let attachments: [AttachmentBody]
    let weatherSnapshot: WeatherSnapshot?
    let scheduleSnapshot: ScheduleSnapshot?

    init(
        threadID: UUID?,
        message: KyraOutgoingMessage,
        weatherSnapshot: WeatherSnapshot?,
        scheduleSnapshot: ScheduleSnapshot?
    ) {
        self.threadID = threadID
        self.text = message.text
        self.attachments = message.attachments.map(AttachmentBody.init)
        self.weatherSnapshot = weatherSnapshot
        self.scheduleSnapshot = scheduleSnapshot
    }

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case text
        case attachments
        case weatherSnapshot = "weather_snapshot"
        case scheduleSnapshot = "schedule_snapshot"
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
            case .studioInspiration(let generationID):
                type = "studio_inspiration"
                value = generationID.uuidString
            }
        }
    }
}

extension LiveKyraRepository: KyraHistoryCachePurging {
    public func purgeCachedKyraHistory(ownerID: UUID) async throws {
        try await historyCache?.removeAll(ownerID: ownerID)
    }
}
