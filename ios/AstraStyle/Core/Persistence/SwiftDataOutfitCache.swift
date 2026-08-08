//
//  SwiftDataOutfitCache.swift
//  AstraStyle
//
//  Production `OutfitCaching` conformance, scoped by the authenticated
//  account's `userID` (same rationale as `SwiftDataClosetItemCache`).
//
//  `@ModelActor` so every `ModelContext` access is serialized on its own
//  executor (`ModelContext` is not `Sendable`).
//

import Foundation
import SwiftData

@ModelActor
public actor SwiftDataOutfitCache: OutfitCaching {

    public func outfits(for userID: UUID) async -> [Outfit] {
        let descriptor = FetchDescriptor<PersistedOutfit>(
            predicate: #Predicate { $0.userID == userID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map(PersistenceMapping.domainModel(from:))
    }

    public func items(forOutfit outfitID: UUID) async -> [OutfitItem] {
        let descriptor = FetchDescriptor<PersistedOutfit>(predicate: #Predicate { $0.id == outfitID })
        guard let row = try? modelContext.fetch(descriptor).first else { return [] }
        return PersistenceMapping.domainOutfitItems(from: row)
    }

    /// Merges rather than replaces: an id already cached keeps its
    /// `encodedItems` (see this type's protocol doc for why), an id not in
    /// `outfits` any more is deleted outright, and everything else is a
    /// fresh insert with an empty item list.
    public func replaceAll(_ outfits: [Outfit], for userID: UUID) async {
        let existingDescriptor = FetchDescriptor<PersistedOutfit>(predicate: #Predicate { $0.userID == userID })
        let existingRows = (try? modelContext.fetch(existingDescriptor)) ?? []
        var staleByID = Dictionary(uniqueKeysWithValues: existingRows.map { ($0.id, $0) })

        for outfit in outfits {
            if let row = staleByID.removeValue(forKey: outfit.id) {
                PersistenceMapping.update(row, with: outfit)
            } else {
                modelContext.insert(PersistenceMapping.persistedModel(from: outfit, items: []))
            }
        }
        // Whatever is left in staleByID is a row the server no longer lists.
        for row in staleByID.values {
            modelContext.delete(row)
        }
        try? modelContext.save()
    }

    public func upsert(_ outfit: Outfit, items: [OutfitItem]?) async {
        let outfitID = outfit.id
        let descriptor = FetchDescriptor<PersistedOutfit>(predicate: #Predicate { $0.id == outfitID })
        if let row = try? modelContext.fetch(descriptor).first {
            PersistenceMapping.update(row, with: outfit)
            if let items {
                row.encodedItems = (try? JSONEncoder.astraDefault.encode(items)) ?? row.encodedItems
            }
        } else {
            modelContext.insert(PersistenceMapping.persistedModel(from: outfit, items: items ?? []))
        }
        try? modelContext.save()
    }

    public func upsertItems(_ items: [OutfitItem], forOutfit outfitID: UUID) async {
        let descriptor = FetchDescriptor<PersistedOutfit>(predicate: #Predicate { $0.id == outfitID })
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        row.encodedItems = (try? JSONEncoder.astraDefault.encode(items)) ?? row.encodedItems
        try? modelContext.save()
    }

    public func remove(id: UUID) async {
        let descriptor = FetchDescriptor<PersistedOutfit>(predicate: #Predicate { $0.id == id })
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(row)
        try? modelContext.save()
    }
}
