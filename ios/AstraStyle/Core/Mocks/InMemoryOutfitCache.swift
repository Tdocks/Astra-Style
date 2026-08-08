//
//  InMemoryOutfitCache.swift
//  AstraStyle
//
//  In-memory `OutfitCaching` for unit tests and any preview path that
//  constructs a `LiveOutfitRepository` without SwiftData. Mirrors
//  `InMemoryClosetItemCache`.
//

import Foundation

public actor InMemoryOutfitCache: OutfitCaching {
    private var outfitsByID: [UUID: Outfit] = [:]
    private var itemsByOutfitID: [UUID: [OutfitItem]] = [:]

    public init(seed: [Outfit] = []) {
        for outfit in seed { outfitsByID[outfit.id] = outfit }
    }

    public func outfits(for userID: UUID) async -> [Outfit] {
        outfitsByID.values
            .filter { $0.userID == userID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func items(forOutfit outfitID: UUID) async -> [OutfitItem] {
        itemsByOutfitID[outfitID] ?? []
    }

    public func replaceAll(_ outfits: [Outfit], for userID: UUID) async {
        // Only ids the server dropped are purged (metadata + items); ids
        // that persist keep whatever items they already had cached — see
        // the protocol doc for why a full wipe-and-reinsert is wrong here.
        let previousIDsForUser = Set(outfitsByID.values.filter { $0.userID == userID }.map(\.id))
        let incomingIDs = Set(outfits.map(\.id))
        for staleID in previousIDsForUser.subtracting(incomingIDs) {
            outfitsByID[staleID] = nil
            itemsByOutfitID[staleID] = nil
        }
        for outfit in outfits {
            var owned = outfit
            owned.userID = userID
            outfitsByID[owned.id] = owned
        }
    }

    public func upsert(_ outfit: Outfit, items: [OutfitItem]?) async {
        outfitsByID[outfit.id] = outfit
        if let items {
            itemsByOutfitID[outfit.id] = items
        }
    }

    public func upsertItems(_ items: [OutfitItem], forOutfit outfitID: UUID) async {
        guard outfitsByID[outfitID] != nil else { return }
        itemsByOutfitID[outfitID] = items
    }

    public func remove(id: UUID) async {
        outfitsByID[id] = nil
        itemsByOutfitID[id] = nil
    }
}
