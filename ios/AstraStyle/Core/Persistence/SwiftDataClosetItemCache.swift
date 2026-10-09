//
//  SwiftDataClosetItemCache.swift
//  AstraStyle
//
//  Production `ClosetItemCaching` conformance. Reuses
//  `PersistedClosetItem` / `PersistenceMapping`, scoped by the
//  authenticated account's `userID` so two accounts on one device never
//  collide in the shared store.
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
        let careDescriptor = FetchDescriptor<PersistedClosetCareInstructions>(
            predicate: #Predicate { $0.userID == userID }
        )
        let careRows = (try? modelContext.fetch(careDescriptor)) ?? []
        let careByItemID = Dictionary(careRows.map { ($0.itemID, $0.instructions) }, uniquingKeysWith: { _, latest in latest })
        return rows.map { row in
            var item = PersistenceMapping.domainModel(from: row)
            item.careInstructions = careByItemID[row.id]
            return item
        }
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
        let existingCare = FetchDescriptor<PersistedClosetCareInstructions>(
            predicate: #Predicate { $0.userID == userID }
        )
        if let rows = try? modelContext.fetch(existingCare) {
            for row in rows { modelContext.delete(row) }
        }
        for item in items {
            var owned = item
            owned.userID = userID
            modelContext.insert(PersistenceMapping.persistedModel(from: owned))
            if let instructions = Self.cleanedInstructions(item.careInstructions) {
                modelContext.insert(PersistedClosetCareInstructions(itemID: item.id, userID: userID, instructions: instructions))
            }
        }
        try? modelContext.save()
    }

    public func upsert(_ item: ClosetItem) async {
        let itemID = item.id
        let descriptor = FetchDescriptor<PersistedClosetItem>(predicate: #Predicate { $0.id == itemID })
        if let row = try? modelContext.fetch(descriptor).first {
            guard row.userID == item.userID else { return }
            PersistenceMapping.update(row, with: item)
        } else {
            modelContext.insert(PersistenceMapping.persistedModel(from: item))
        }
        let careDescriptor = FetchDescriptor<PersistedClosetCareInstructions>(predicate: #Predicate { $0.itemID == itemID })
        let careRow = try? modelContext.fetch(careDescriptor).first
        if let instructions = Self.cleanedInstructions(item.careInstructions) {
            if let careRow, careRow.userID == item.userID {
                careRow.instructions = instructions
            } else if careRow == nil {
                modelContext.insert(PersistedClosetCareInstructions(itemID: item.id, userID: item.userID, instructions: instructions))
            }
        } else if let careRow, careRow.userID == item.userID {
            modelContext.delete(careRow)
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

    public func removeAll(for userID: UUID) async throws {
        let itemDescriptor = FetchDescriptor<PersistedClosetItem>(predicate: #Predicate { $0.userID == userID })
        let itemRows = try modelContext.fetch(itemDescriptor)
        let careDescriptor = FetchDescriptor<PersistedClosetCareInstructions>(predicate: #Predicate { $0.userID == userID })
        let careRows = try modelContext.fetch(careDescriptor)
        for row in itemRows { modelContext.delete(row) }
        for row in careRows { modelContext.delete(row) }
        do {
            try modelContext.save()
        } catch {
            for row in itemRows { modelContext.insert(row) }
            for row in careRows { modelContext.insert(row) }
            throw error
        }
    }

    private static func cleanedInstructions(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
