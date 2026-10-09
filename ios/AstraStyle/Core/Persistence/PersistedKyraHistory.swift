import Foundation
import SwiftData

/// An account-scoped snapshot marker lets an empty server thread list be
/// distinguished from a cache that has never successfully loaded.
@Model
public final class PersistedKyraThreadListSnapshot {
    @Attribute(.unique) public var ownerID: UUID
    public var fetchedAt: Date

    public init(ownerID: UUID, fetchedAt: Date) {
        self.ownerID = ownerID
        self.fetchedAt = fetchedAt
    }
}

/// Server-owned thread metadata copied locally for offline transcript access.
@Model
public final class PersistedKyraThread {
    @Attribute(.unique) public var id: UUID
    public var ownerID: UUID
    public var title: String?
    public var lastMessageAt: Date?
    public var updatedAt: Date
    /// Non-nil only after a successful server read (including an empty result).
    public var messagesFetchedAt: Date?

    public init(
        id: UUID,
        ownerID: UUID,
        title: String?,
        lastMessageAt: Date?,
        updatedAt: Date,
        messagesFetchedAt: Date? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.title = title
        self.lastMessageAt = lastMessageAt
        self.updatedAt = updatedAt
        self.messagesFetchedAt = messagesFetchedAt
    }
}

/// One server message, serialized from the typed Codable DTO rather than raw
/// PostgREST JSON. Kyra cards carry canonical entity IDs and are hydrated when
/// rendered; private signed image URLs are never persisted in this cache.
@Model
public final class PersistedKyraMessage {
    @Attribute(.unique) public var id: UUID
    public var ownerID: UUID
    public var threadID: UUID
    public var createdAt: Date
    public var encodedMessage: Data

    public init(
        id: UUID,
        ownerID: UUID,
        threadID: UUID,
        createdAt: Date,
        encodedMessage: Data
    ) {
        self.id = id
        self.ownerID = ownerID
        self.threadID = threadID
        self.createdAt = createdAt
        self.encodedMessage = encodedMessage
    }
}
