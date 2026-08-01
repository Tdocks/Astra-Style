//
//  SwiftDataClosetItemCache.swift
//  AstraStyle
//
//  Production `ClosetItemCaching` conformance. Reuses
//  `PersistedClosetItem` / `PersistenceMapping` — the same SwiftData model
//  the guest store writes — scoped by the authenticated account's
//  `userID` so guest rows and signed-in cache rows never collide in the
//  shared store (guest ids are locally minted; account ids come from
//  Supabase Auth).
//
//  `@ModelActor` so every `ModelContext` access is serialized on its own
//  executor (`ModelContext` is not `Sendable`).
//

import Foundation
import SwiftData

@ModelActor
public actor SwiftDataClosetItemCache: ClosetItemCaching {

    public func items(for userID: UUID) async -> [ClosetItem] {
        let descriptor = FetchDescriptor<PersistedClosetItem>(
            predicate: #Predicate { $0.userID == userID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map(PersistenceMapping.domainModel(from:))
    }

    public func replaceAll(_ items: [ClosetItem], for userID: UUID) async {
        let existing = FetchDescriptor<PersistedClosetItem>(
            predicate: #Predicate { $0.userID == userID }
        )
        if let rows = try? modelContext.fetch(existing) {
            for row in rows {
                modelContext.delete(row)
            }
        }
        for item in items {
            var owned = item
            owned.userID = userID
            modelContext.insert(PersistenceMapping.persistedModel(from: owned))
        }
        try? modelContext.save()
    }

    public func upsert(_ item: ClosetItem) async {
        let itemID = item.id
        let descriptor = FetchDescriptor<PersistedClosetItem>(predicate: #Predicate { $0.id == itemID })
        if let row = try? modelContext.fetch(descriptor).first {
            PersistenceMapping.update(row, with: item)
        } else {
            modelContext.insert(PersistenceMapping.persistedModel(from: item))
        }
        try? modelContext.save()
    }

    public func archive(id: UUID, for userID: UUID, archivedAt: Date) async {
        let descriptor = FetchDescriptor<PersistedClosetItem>(
            predicate: #Predicate { $0.id == id && $0.userID == userID }
        )
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        row.archivedAt = archivedAt
        row.updatedAt = .now
        try? modelContext.save()
    }
}
