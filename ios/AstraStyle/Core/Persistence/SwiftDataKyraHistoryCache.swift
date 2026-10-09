import Foundation
import SwiftData

/// Persistent, owner-scoped cache for server-confirmed Kyra threads/messages.
/// All SwiftData access runs on the model actor's serialized executor.
@ModelActor
public actor SwiftDataKyraHistoryCache: KyraHistoryCaching {
    public func cachedThreads(ownerID: UUID) async throws -> [KyraThread]? {
        let snapshotDescriptor = FetchDescriptor<PersistedKyraThreadListSnapshot>(
            predicate: #Predicate { $0.ownerID == ownerID }
        )
        guard try modelContext.fetch(snapshotDescriptor).first != nil else { return nil }
        let descriptor = FetchDescriptor<PersistedKyraThread>(
            predicate: #Predicate { $0.ownerID == ownerID }
        )
        let rows = try modelContext.fetch(descriptor)
        return rows.map {
            KyraThread(id: $0.id, userID: $0.ownerID, title: $0.title, lastMessageAt: $0.lastMessageAt)
        }.sorted { lhs, rhs in
            switch (lhs.lastMessageAt, rhs.lastMessageAt) {
            case let (left?, right?): left > right
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    public func replaceThreads(_ threads: [KyraThread], ownerID: UUID) async throws {
        guard threads.allSatisfy({ $0.userID == ownerID }) else {
            throw AstraError.auth("A conversation belongs to another account.")
        }
        let ids = threads.map(\.id)
        guard Set(ids).count == ids.count else {
            throw AstraError.validation("The conversation list contains duplicate IDs.")
        }

        let descriptor = FetchDescriptor<PersistedKyraThread>(
            predicate: #Predicate { $0.ownerID == ownerID }
        )
        let existing = try modelContext.fetch(descriptor)
        var staleByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for thread in threads {
            if let row = staleByID.removeValue(forKey: thread.id) {
                row.title = thread.title
                row.lastMessageAt = thread.lastMessageAt
                row.updatedAt = .now
            } else {
                modelContext.insert(PersistedKyraThread(
                    id: thread.id,
                    ownerID: ownerID,
                    title: thread.title,
                    lastMessageAt: thread.lastMessageAt,
                    updatedAt: .now
                ))
            }
        }

        let staleThreadIDs = Set(staleByID.keys)
        for row in staleByID.values { modelContext.delete(row) }
        if !staleThreadIDs.isEmpty {
            let messageDescriptor = FetchDescriptor<PersistedKyraMessage>(
                predicate: #Predicate { $0.ownerID == ownerID }
            )
            for row in try modelContext.fetch(messageDescriptor) where staleThreadIDs.contains(row.threadID) {
                modelContext.delete(row)
            }
        }

        let snapshots = try modelContext.fetch(FetchDescriptor<PersistedKyraThreadListSnapshot>(
            predicate: #Predicate { $0.ownerID == ownerID }
        ))
        if let snapshot = snapshots.first {
            snapshot.fetchedAt = .now
        } else {
            modelContext.insert(PersistedKyraThreadListSnapshot(ownerID: ownerID, fetchedAt: .now))
        }
        try modelContext.save()
    }

    public func cachedMessages(threadID: UUID, ownerID: UUID) async throws -> [KyraMessage]? {
        let threadDescriptor = FetchDescriptor<PersistedKyraThread>(
            predicate: #Predicate { $0.id == threadID && $0.ownerID == ownerID }
        )
        guard let thread = try modelContext.fetch(threadDescriptor).first,
              thread.messagesFetchedAt != nil else { return nil }
        let messageDescriptor = FetchDescriptor<PersistedKyraMessage>(
            predicate: #Predicate { $0.threadID == threadID && $0.ownerID == ownerID }
        )
        return try modelContext.fetch(messageDescriptor)
            .sorted { $0.createdAt < $1.createdAt }
            .map { row in
                let message = try JSONDecoder().decode(KyraMessage.self, from: row.encodedMessage)
                guard message.id == row.id, message.threadID == threadID else {
                    throw AstraError.server("A saved conversation couldn't be read.")
                }
                return message
            }
    }

    public func replaceMessages(_ messages: [KyraMessage], threadID: UUID, ownerID: UUID) async throws {
        guard messages.allSatisfy({ $0.threadID == threadID }) else {
            throw AstraError.auth("A conversation message belongs to another thread.")
        }
        let ids = messages.map(\.id)
        guard Set(ids).count == ids.count else {
            throw AstraError.validation("The conversation contains duplicate message IDs.")
        }

        let threadDescriptor = FetchDescriptor<PersistedKyraThread>(
            predicate: #Predicate { $0.id == threadID && $0.ownerID == ownerID }
        )
        let thread: PersistedKyraThread
        if let existing = try modelContext.fetch(threadDescriptor).first {
            thread = existing
        } else {
            // A deep-linked message history can be loaded before the thread
            // list. The server read is caller-authorized, so this placeholder
            // remains safely bound to that same authenticated owner.
            thread = PersistedKyraThread(
                id: threadID,
                ownerID: ownerID,
                title: nil,
                lastMessageAt: nil,
                updatedAt: .now
            )
            modelContext.insert(thread)
        }

        try upsertMessageRows(messages, threadID: threadID, ownerID: ownerID, thread: thread)
    }

    private func upsertMessageRows(
        _ messages: [KyraMessage],
        threadID: UUID,
        ownerID: UUID,
        thread: PersistedKyraThread
    ) throws {
        let descriptor = FetchDescriptor<PersistedKyraMessage>(
            predicate: #Predicate { $0.threadID == threadID && $0.ownerID == ownerID }
        )
        let existing = try modelContext.fetch(descriptor)
        var staleByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for message in messages {
            let safeMessage = Self.cacheSafeMessage(message)
            let encoded = try JSONEncoder().encode(safeMessage)
            if let row = staleByID.removeValue(forKey: message.id) {
                row.encodedMessage = encoded
                row.createdAt = message.createdAt
            } else {
                modelContext.insert(PersistedKyraMessage(
                    id: message.id,
                    ownerID: ownerID,
                    threadID: threadID,
                    createdAt: message.createdAt,
                    encodedMessage: encoded
                ))
            }
        }
        for row in staleByID.values { modelContext.delete(row) }
        thread.messagesFetchedAt = .now
        thread.updatedAt = .now
        if let latest = messages.max(by: { $0.createdAt < $1.createdAt }) {
            thread.lastMessageAt = max(thread.lastMessageAt ?? latest.createdAt, latest.createdAt)
        }
        try modelContext.save()
    }

    public func removeAll(ownerID: UUID) async throws {
        for row in try modelContext.fetch(FetchDescriptor<PersistedKyraThread>(
            predicate: #Predicate { $0.ownerID == ownerID }
        )) {
            modelContext.delete(row)
        }
        for row in try modelContext.fetch(FetchDescriptor<PersistedKyraMessage>(
            predicate: #Predicate { $0.ownerID == ownerID }
        )) {
            modelContext.delete(row)
        }
        for row in try modelContext.fetch(FetchDescriptor<PersistedKyraThreadListSnapshot>(
            predicate: #Predicate { $0.ownerID == ownerID }
        )) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    private static func cacheSafeMessage(_ message: KyraMessage) -> KyraMessage {
        let safePayload = message.structuredPayload.map { payload in
            KyraStructuredResponse(
                message: Self.stripPrivateStorageURL(payload.message),
                intent: payload.intent,
                cards: payload.cards.map { card in
                    if case .comparisonTable(let table) = card {
                        return .comparisonTable(ComparisonTable(
                            title: Self.stripPrivateStorageURL(table.title),
                            columnHeaders: table.columnHeaders.map(Self.stripPrivateStorageURL),
                            rows: table.rows.map { $0.map(Self.stripPrivateStorageURL) }
                        ))
                    }
                    return card
                },
                suggestedActions: payload.suggestedActions.map {
                    KyraSuggestedAction(
                        id: Self.stripPrivateStorageURL($0.id),
                        label: Self.stripPrivateStorageURL($0.label),
                        kind: $0.kind
                    )
                },
                memoryProposals: payload.memoryProposals.map {
                    KyraMemoryProposal(
                        memoryType: $0.memoryType,
                        content: Self.stripPrivateStorageURL($0.content),
                        confidence: $0.confidence
                    )
                },
                confidence: payload.confidence
            )
        }
        let safeMetadata: AstraJSONValue? = {
            guard case .object(let values)? = message.modelMetadata else { return nil }
            var safe: [String: AstraJSONValue] = [:]
            for key in ["model_identifier", "fallback_reason"] {
                if case .string(let value)? = values[key] { safe[key] = .string(Self.stripPrivateStorageURL(value)) }
            }
            return safe.isEmpty ? nil : .object(safe)
        }()
        return KyraMessage(
            id: message.id,
            threadID: message.threadID,
            role: message.role,
            content: Self.stripPrivateStorageURL(message.content),
            structuredPayload: safePayload,
            modelMetadata: safeMetadata,
            createdAt: message.createdAt
        )
    }

    private static func stripPrivateStorageURL(_ value: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"https?://[^\s)\]]*(?:/storage/v1/object/sign/|%2fstorage%2fv1%2fobject%2fsign%2f)[^\s)\]]+"#,
            options: [.caseInsensitive]
        ) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: "[private image omitted]"
        )
    }
}
