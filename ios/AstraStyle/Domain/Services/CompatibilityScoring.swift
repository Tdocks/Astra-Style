//
//  CompatibilityScoring.swift
//  AstraStyle
//
//  Protocol surface for the Wardrobe Graph's compatibility scorer
//  (spec §10 "MVP implementation"). The authoritative scoring computation
//  runs server-side (weights are configurable server-side per spec §10),
//  but the client needs the same shape locally for:
//    - optimistic UI in the outfit builder's live compatibility meter
//      (spec §6.13 "Compatibility meter updates live"), before the
//      server round-trip confirms it, and
//    - unit-testable, offline-safe fallback scoring when generating a
//      quick preview with no network (spec §7 "Generative features require
//      network" — this is deliberately NOT used to replace server
//      generation, only to keep the builder UI responsive).
//

import Foundation

/// The five-dimension score breakdown from spec §10's weighted formula:
/// ```
/// 0.25 color compatibility
/// 0.20 formality alignment
/// 0.15 silhouette compatibility
/// 0.10 season/weather suitability
/// 0.10 user preference
/// 0.10 historical co-wear/feedback
/// 0.05 occasion relevance
/// 0.05 availability/laundry
/// ```
public struct CompatibilityBreakdown: Codable, Hashable, Sendable {
    public var colorCompatibility: Double
    public var formalityAlignment: Double
    public var silhouetteCompatibility: Double
    public var seasonWeatherSuitability: Double
    public var userPreference: Double
    public var historicalCoWear: Double
    public var occasionRelevance: Double
    public var availabilityLaundry: Double

    public init(
        colorCompatibility: Double,
        formalityAlignment: Double,
        silhouetteCompatibility: Double,
        seasonWeatherSuitability: Double,
        userPreference: Double,
        historicalCoWear: Double,
        occasionRelevance: Double,
        availabilityLaundry: Double
    ) {
        self.colorCompatibility = colorCompatibility
        self.formalityAlignment = formalityAlignment
        self.silhouetteCompatibility = silhouetteCompatibility
        self.seasonWeatherSuitability = seasonWeatherSuitability
        self.userPreference = userPreference
        self.historicalCoWear = historicalCoWear
        self.occasionRelevance = occasionRelevance
        self.availabilityLaundry = availabilityLaundry
    }

    /// The configurable weights, defaulted to spec §10's published values.
    /// A server-driven override can be substituted at call sites once the
    /// admin tool (spec §28 "Compatibility weights") ships.
    public struct Weights: Sendable {
        public var color = 0.25
        public var formality = 0.20
        public var silhouette = 0.15
        public var seasonWeather = 0.10
        public var userPreference = 0.10
        public var historicalCoWear = 0.10
        public var occasionRelevance = 0.05
        public var availabilityLaundry = 0.05

        public init() {}
    }

    /// Weighted 0–100 composite.
    public func score(weights: Weights = Weights()) -> Int {
        let weighted =
            colorCompatibility * weights.color
            + formalityAlignment * weights.formality
            + silhouetteCompatibility * weights.silhouette
            + seasonWeatherSuitability * weights.seasonWeather
            + userPreference * weights.userPreference
            + historicalCoWear * weights.historicalCoWear
            + occasionRelevance * weights.occasionRelevance
            + availabilityLaundry * weights.availabilityLaundry
        return Int((weighted * 100).rounded())
    }
}

/// Scores how well a candidate item/outfit combination fits together.
public protocol CompatibilityScoring: Sendable {
    /// Scores a proposed set of closet items as a single outfit.
    func scoreOutfit(items: [ClosetItem], context: CompatibilityContext) -> CompatibilityBreakdown

    /// Scores a single candidate item against an existing set of items it
    /// would be paired with (used by the outfit builder's "replace item"
    /// flow and by product evaluation's compatibility component).
    func scoreItem(_ candidate: ClosetItem, against existingItems: [ClosetItem], context: CompatibilityContext) -> CompatibilityBreakdown
}

/// Contextual inputs the scorer needs beyond the garments themselves.
public struct CompatibilityContext: Sendable {
    public var styleProfile: StyleProfile?
    public var weather: WeatherSnapshot?
    public var occasion: Occasion?
    public var recentFeedback: [StyleFeedback]

    public init(
        styleProfile: StyleProfile? = nil,
        weather: WeatherSnapshot? = nil,
        occasion: Occasion? = nil,
        recentFeedback: [StyleFeedback] = []
    ) {
        self.styleProfile = styleProfile
        self.weather = weather
        self.occasion = occasion
        self.recentFeedback = recentFeedback
    }
}
