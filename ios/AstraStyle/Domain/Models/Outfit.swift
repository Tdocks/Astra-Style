//
//  Outfit.swift
//  AstraStyle
//
//  Maps `outfits` (spec §9).
//

import Foundation

public struct Outfit: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var userID: UUID
    public var name: String
    public var description: String?
    public var occasionTags: [String]
    public var weatherMin: Double?
    public var weatherMax: Double?
    public var formalityScore: Int?
    public var compatibilityScore: Int?
    public var source: OutfitSource
    public var heroImageURL: URL?
    public var generatedPreviewURL: URL?
    public var isFavorite: Bool

    /// Soft-delete timestamp. `nil` means active.
    ///
    /// `ClosetItem` has had `archivedAt` plus an `isArchived` convenience since
    /// the start; `Outfit` did not, despite the column existing. The app could
    /// therefore not tell an archived outfit from a live one and would have
    /// listed both — the kind of gap that reads as "the app resurrected
    /// something I deleted".
    public var archivedAt: Date?

    public var embedding: [Float]?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        userID: UUID,
        name: String,
        description: String? = nil,
        occasionTags: [String] = [],
        weatherMin: Double? = nil,
        weatherMax: Double? = nil,
        formalityScore: Int? = nil,
        compatibilityScore: Int? = nil,
        source: OutfitSource = .aiGenerated,
        heroImageURL: URL? = nil,
        generatedPreviewURL: URL? = nil,
        isFavorite: Bool = false,
        archivedAt: Date? = nil,
        embedding: [Float]? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.description = description
        self.occasionTags = occasionTags
        self.weatherMin = weatherMin
        self.weatherMax = weatherMax
        self.formalityScore = formalityScore
        self.compatibilityScore = compatibilityScore
        self.source = source
        self.heroImageURL = heroImageURL
        self.generatedPreviewURL = generatedPreviewURL
        self.isFavorite = isFavorite
        self.archivedAt = archivedAt
        self.embedding = embedding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case description
        case occasionTags = "occasion_tags"
        case weatherMin = "weather_min_celsius"
        case weatherMax = "weather_max_celsius"
        case formalityScore = "formality_score"
        case compatibilityScore = "compatibility_score"
        case source
        case heroImageURL = "hero_image_url"
        case generatedPreviewURL = "generated_preview_url"
        case isFavorite = "is_favorite"
        case archivedAt = "archived_at"
        case embedding
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Mirrors `ClosetItem.isArchived` so call sites read the same way for both.
    public var isArchived: Bool { archivedAt != nil }
}
