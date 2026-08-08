//
//  InMemoryClosetItemCache.swift
//  AstraStyle
//
//  In-memory `ClosetItemCaching` for unit tests and for any preview path
//  that constructs a `LiveClosetRepository` without SwiftData. Mirrors
//  the SwiftData-backed cache.
//

import Foundation

public actor InMemoryClosetItemCache: ClosetItemCaching {
    private var itemsByID: [UUID: ClosetItem] = [:]

    public init(seed: [ClosetItem] = []) {
        for item in seed { itemsByID[item.id] = item }
    }

    public func items(for userID: UUID) async -> [ClosetItem] {
        itemsByID.values
            .filter { $0.userID == userID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func replaceAll(_ items: [ClosetItem], for userID: UUID) async {
        itemsByID = itemsByID.filter { $0.value.userID != userID }
        for item in items {
            var owned = item
            owned.userID = userID
            itemsByID[owned.id] = owned
        }
    }

    public func upsert(_ item: ClosetItem) async {
        itemsByID[item.id] = item
    }

    public func archive(id: UUID, for userID: UUID, archivedAt: Date) async {
        guard var item = itemsByID[id], item.userID == userID else { return }
        item.archivedAt = archivedAt
        item.updatedAt = .now
        itemsByID[id] = item
    }
}
