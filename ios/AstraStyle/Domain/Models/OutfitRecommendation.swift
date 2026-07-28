//
//  OutfitRecommendation.swift
//  AstraStyle
//
//  Matches spec §26 "Sample Domain Types" verbatim. This is the transient
//  ranked-outfit shape returned by `POST /outfits/generate` and
//  `POST /outfits/rank` (spec §14) — distinct from the persisted `Outfit`
//  entity: a recommendation becomes an `Outfit` (+ `OutfitItem` rows) only
//  once the user saves, schedules, or wears it (spec §5.4).
//

import Foundation

public struct OutfitRecommendation: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let reason: String
    public let compatibilityScore: Int
    public let itemIDs: [UUID]
    public let missingProductIDs: [UUID]

    public init(
        id: UUID,
        name: String,
        reason: String,
        compatibilityScore: Int,
        itemIDs: [UUID],
        missingProductIDs: [UUID]
    ) {
        self.id = id
        self.name = name
        self.reason = reason
        self.compatibilityScore = compatibilityScore
        self.itemIDs = itemIDs
        self.missingProductIDs = missingProductIDs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case reason
        case compatibilityScore = "compatibility_score"
        case itemIDs = "item_ids"
        case missingProductIDs = "missing_product_ids"
    }
}
