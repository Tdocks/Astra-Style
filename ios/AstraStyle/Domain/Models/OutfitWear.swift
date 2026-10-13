//
//  OutfitWear.swift
//  AstraStyle
//
//  Maps `outfit_wears` (spec §9). Recorded whenever a user marks an outfit
//  worn (spec §5.2, §6.12 "Mark Worn"), and the primary input to cost-per-
//  wear and Wardrobe Score calculations (spec §10).
//

import Foundation

public struct OutfitWear: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var outfitID: UUID
    public var userID: UUID
    public var wornAt: Date
    public var occasion: String?
    public var rating: Int?
    public var feedback: String?

    /// Cached weather at the moment of wear, for later "did this actually
    /// suit the conditions" analysis. Free-form — see `AstraJSONValue`.
    public var weatherSnapshot: WeatherSnapshot?

    public init(
        id: UUID,
        outfitID: UUID,
        userID: UUID,
        wornAt: Date,
        occasion: String? = nil,
        rating: Int? = nil,
        feedback: String? = nil,
        weatherSnapshot: WeatherSnapshot? = nil
    ) {
        self.id = id
        self.outfitID = outfitID
        self.userID = userID
        self.wornAt = wornAt
        self.occasion = occasion
        self.rating = rating
        self.feedback = feedback
        self.weatherSnapshot = weatherSnapshot
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        outfitID = try values.decode(UUID.self, forKey: .outfitID)
        userID = try values.decode(UUID.self, forKey: .userID)
        wornAt = try values.decode(Date.self, forKey: .wornAt)
        occasion = try values.decodeIfPresent(String.self, forKey: .occasion)
        rating = try values.decodeIfPresent(Int.self, forKey: .rating)
        feedback = try values.decodeIfPresent(String.self, forKey: .feedback)
        // Postgres defaults missing weather to {}. It means no observation,
        // not a corrupt wear record or a reason to retry a committed write.
        let weather = try values.decodeIfPresent([String: AstraJSONValue].self, forKey: .weatherSnapshot)
        if let weather, !weather.isEmpty {
            weatherSnapshot = try values.decode(WeatherSnapshot.self, forKey: .weatherSnapshot)
        } else {
            weatherSnapshot = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case outfitID = "outfit_id"
        case userID = "user_id"
        case wornAt = "worn_at"
        case occasion
        case rating
        case feedback
        case weatherSnapshot = "weather_snapshot"
    }
}
