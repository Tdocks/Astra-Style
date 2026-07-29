//
//  SwiftDataGuestClosetStore.swift
//  AstraStyle
//
//  Production `GuestClosetStore` conformance (ADR 0011: guest closet items
//  "live only in SwiftData and local file storage on-device"). Reuses
//  `PersistedClosetItem`/`PersistenceMapping` — the same SwiftData model
//  the offline cache uses for authenticated users' closets — scoped by
//  `userID` to the guest session's own (locally-generated, never
//  server-issued) id, so guest rows never collide with a real account's
//  cached rows in the same store.
//
//  `@ModelActor`, mirroring `SwiftDataOfflineMutationQueue`: every access
//  to the underlying `ModelContext` is serialized on its own executor,
//  which is the supported SwiftData pattern for touching persistence from
//  arbitrary concurrent call sites (`ModelContext` itself is not
//  `Sendable`).
//

import Foundation
import SwiftData

@ModelActor
public actor SwiftDataGuestClosetStore: GuestClosetStore {

    public func items(for guestUserID: UUID) async -> [ClosetItem] {
        let descriptor = FetchDescriptor<PersistedClosetItem>(
            predicate: #Predicate { $0.userID == guestUserID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map(PersistenceMapping.domainModel(from:))
    }

    public func item(id: UUID, for guestUserID: UUID) async -> ClosetItem? {
        let descriptor = FetchDescriptor<PersistedClosetItem>(
            predicate: #Predicate { $0.id == id && $0.userID == guestUserID }
        )
        guard let row = try? modelContext.fetch(descriptor).first else { return nil }
        return PersistenceMapping.domainModel(from: row)
    }

    public func insert(_ item: ClosetItem) async {
        let row = PersistenceMapping.persistedModel(from: item)
        modelContext.insert(row)
        try? modelContext.save()
    }

    public func update(_ item: ClosetItem) async {
        let itemID = item.id
        let descriptor = FetchDescriptor<PersistedClosetItem>(predicate: #Predicate { $0.id == itemID })
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        PersistenceMapping.update(row, with: item)
        try? modelContext.save()
    }

    public func archive(id: UUID, for guestUserID: UUID, archivedAt: Date) async {
        let descriptor = FetchDescriptor<PersistedClosetItem>(
            predicate: #Predicate { $0.id == id && $0.userID == guestUserID }
        )
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        row.archivedAt = archivedAt
        row.updatedAt = .now
        try? modelContext.save()
    }

    public func remove(id: UUID, for guestUserID: UUID) async {
        let descriptor = FetchDescriptor<PersistedClosetItem>(
            predicate: #Predicate { $0.id == id && $0.userID == guestUserID }
        )
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(row)
        try? modelContext.save()
    }
}
