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

    /// Do these garments work *with each other* — the original meaning of the
    /// silhouette dimension, and still the majority of it.
    public var silhouetteInternal: Double

    /// Does this silhouette work *on this wearer* (`docs/14-frame-fit.md`).
    ///
    /// `nil` whenever the frame was too thin to support a conclusion, which is
    /// the normal case rather than the exception: spec §6.6 requires "I don't
    /// know" on every measurement field, so most users will have partial data
    /// and many will have none. When `nil`, `silhouetteCompatibility` collapses
    /// to `silhouetteInternal` and the composite is bit-for-bit what it was
    /// before frame fit existed.
    public var frameHarmony: Double?

    public var seasonWeatherSuitability: Double
    public var userPreference: Double
    public var historicalCoWear: Double
    public var occasionRelevance: Double
    public var availabilityLaundry: Double

    /// The silhouette dimension spec §10 weights at 0.15.
    ///
    /// Frame fit deliberately splits this EXISTING dimension rather than adding
    /// a ninth one. §10's weight table is a published contract summing to 1.0;
    /// adding a dimension forces a rebalance of all eight and silently changes
    /// every score in the app. Splitting one leaves the contract intact.
    public var silhouetteCompatibility: Double {
        silhouetteCompatibility(weights: Weights())
    }

    /// The blended silhouette score under a specific weight set.
    ///
    /// Takes `weights` rather than reading the default, because `score(weights:)`
    /// below accepts a server-driven override and a computed property that
    /// quietly ignored it would make the composite disagree with its own
    /// breakdown — the kind of bug that shows up as a number being "a bit off"
    /// and takes a day to find.
    public func silhouetteCompatibility(weights: Weights) -> Double {
        guard let frameHarmony else { return silhouetteInternal }
        let share = max(0, min(1, weights.frameHarmonyShare))
        return silhouetteInternal * (1 - share) + frameHarmony * share
    }

    public init(
        colorCompatibility: Double,
        formalityAlignment: Double,
        silhouetteCompatibility: Double,
        frameHarmony: Double? = nil,
        seasonWeatherSuitability: Double,
        userPreference: Double,
        historicalCoWear: Double,
        occasionRelevance: Double,
        availabilityLaundry: Double
    ) {
        self.colorCompatibility = colorCompatibility
        self.formalityAlignment = formalityAlignment
        // The label stays `silhouetteCompatibility` so the ~dozen existing call
        // sites keep compiling and keep meaning what they meant. What they were
        // always passing is the internal, garment-to-garment score.
        self.silhouetteInternal = silhouetteCompatibility
        self.frameHarmony = frameHarmony
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

        /// How much of the silhouette dimension frame harmony takes when the
        /// frame is known. Server-configurable alongside the weights above.
        ///
        /// At 0.45 of 0.15, frame fit is worth about 7 points of 100 at full
        /// confidence — enough to break a tie between two otherwise equal
        /// outfits, and nowhere near enough to overrule colour, occasion, or
        /// what the user has actually told us he likes. That ceiling is the
        /// design, not a tuning accident: a man who owns four pairs of wide-leg
        /// trousers and wears them constantly has told us something more
        /// reliable than his inseam did.
        public var frameHarmonyShare = 0.45

        public init() {}
    }

    /// Weighted 0–100 composite.
    public func score(weights: Weights = Weights()) -> Int {
        let weighted =
            colorCompatibility * weights.color
            + formalityAlignment * weights.formality
            + silhouetteCompatibility(weights: weights) * weights.silhouette
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
