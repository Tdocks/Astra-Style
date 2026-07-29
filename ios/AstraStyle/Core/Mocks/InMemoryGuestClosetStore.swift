//
//  InMemoryGuestClosetStore.swift
//  AstraStyle
//
//  In-memory `GuestClosetStore` used by `AppContainer.preview()` and
//  available to unit tests that want to exercise guest-cap enforcement and
//  migration without SwiftData (mirrors `InMemoryOfflineMutationQueue`'s
//  role for `OfflineMutationQueue`).
//

import Foundation

public actor InMemoryGuestClosetStore: GuestClosetStore {
    private var itemsByID: [UUID: ClosetItem] = [:]

    public init(seed: [ClosetItem] = []) {
        for item in seed { itemsByID[item.id] = item }
    }

    public func items(for guestUserID: UUID) async -> [ClosetItem] {
        itemsByID.values
            .filter { $0.userID == guestUserID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func item(id: UUID, for guestUserID: UUID) async -> ClosetItem? {
        guard let item = itemsByID[id], item.userID == guestUserID else { return nil }
        return item
    }

    public func insert(_ item: ClosetItem) async {
        itemsByID[item.id] = item
    }

    public func update(_ item: ClosetItem) async {
        guard itemsByID[item.id] != nil else { return }
        itemsByID[item.id] = item
    }

    public func archive(id: UUID, for guestUserID: UUID, archivedAt: Date) async {
        guard var item = itemsByID[id], item.userID == guestUserID else { return }
        item.archivedAt = archivedAt
        item.updatedAt = .now
        itemsByID[id] = item
    }

    public func remove(id: UUID, for guestUserID: UUID) async {
        guard let item = itemsByID[id], item.userID == guestUserID else { return }
        itemsByID.removeValue(forKey: id)
    }
}
