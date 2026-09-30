//
//  PublicWornLook.swift
//  AstraStyle
//
//  Sanitized summary fields for another user's public, worn look. This shape
//  deliberately has no owner id, favorite state, private image URL, embedding,
//  or internal timestamps.
//

import Foundation

public struct PublicWornLook: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let occasionTags: [String]
    public let weatherMinCelsius: Double?
    public let weatherMaxCelsius: Double?
    public let formalityScore: Int?
    public let compatibilityScore: Int?

    public init(
        id: UUID,
        name: String,
        description: String? = nil,
        occasionTags: [String] = [],
        weatherMinCelsius: Double? = nil,
        weatherMaxCelsius: Double? = nil,
        formalityScore: Int? = nil,
        compatibilityScore: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.occasionTags = occasionTags
        self.weatherMinCelsius = weatherMinCelsius
        self.weatherMaxCelsius = weatherMaxCelsius
        self.formalityScore = formalityScore
        self.compatibilityScore = compatibilityScore
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case occasionTags = "occasion_tags"
        case weatherMinCelsius = "weather_min_celsius"
        case weatherMaxCelsius = "weather_max_celsius"
        case formalityScore = "formality_score"
        case compatibilityScore = "compatibility_score"
    }
}
