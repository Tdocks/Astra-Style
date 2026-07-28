//
//  PersistedOutfit.swift
//  AstraStyle
//
//  SwiftData cache of `Outfit` (spec §7 offline viewability). Outfit items
//  are cached as a flat array of encoded rows rather than a SwiftData
//  relationship, since they're small, always read as a whole, and never
//  queried independently — this avoids the relationship-fetch complexity
//  for data that has no offline-mutation requirement of its own (only the
//  parent outfit and closet items are ever edited offline).
//

import Foundation
import SwiftData

@Model
public final class PersistedOutfit {
    @Attribute(.unique) public var id: UUID
    public var userID: UUID
    public var name: String
    public var itemDescription: String?
    public var occasionTags: [String]
    public var formalityScore: Int?
    public var compatibilityScore: Int?
    public var sourceRaw: String
    public var heroImageURLString: String?
    public var isFavorite: Bool
    public var createdAt: Date
    public var updatedAt: Date

    /// JSON-encoded `[OutfitItem]`, decoded lazily by
    /// `PersistenceMapping.domainOutfitItems(from:)`.
    public var encodedItems: Data

    public var pendingSync: Bool

    public init(
        id: UUID,
        userID: UUID,
        name: String,
        itemDescription: String?,
        occasionTags: [String],
        formalityScore: Int?,
        compatibilityScore: Int?,
        sourceRaw: String,
        heroImageURLString: String?,
        isFavorite: Bool,
        createdAt: Date,
        updatedAt: Date,
        encodedItems: Data,
        pendingSync: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.itemDescription = itemDescription
        self.occasionTags = occasionTags
        self.formalityScore = formalityScore
        self.compatibilityScore = compatibilityScore
        self.sourceRaw = sourceRaw
        self.heroImageURLString = heroImageURLString
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.encodedItems = encodedItems
        self.pendingSync = pendingSync
    }
}
