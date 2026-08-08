//
//  LocalCompatibilityScorer.swift
//  AstraStyle
//
//  `CompatibilityScoring`'s client-side conformance (P4-OUTFIT-12), for the
//  Outfit builder's live compatibility meter (spec §6.13 "Compatibility
//  meter updates live") and, per `CompatibilityScoring.swift`'s own header,
//  as an offline-safe fallback preview. Not a re-implementation of the
//  server's Wardrobe Graph scorer (`P4-OUTFIT-02`'s `CompatibilityScorer`,
//  a separate server-side type this file's name deliberately does not
//  collide with) — it is a MUCH simpler heuristic that only reads what a
//  device already has in memory: the closet items on the canvas, plus
//  whatever `CompatibilityContext` was handed.
//
//  THE GOVERNING CONSTRAINT: A PRIOR IS A LEGITIMATE RANKING INPUT AND NOT
//  EVIDENCE (`OutfitRecommendation.unmeasured`'s header states this rule
//  for the server; it applies here with equal force). Every dimension
//  below that cannot be computed from data this scorer actually has falls
//  back to a documented flat value rather than a fabricated one — and two
//  dimensions (silhouette, user preference) are ALWAYS a flat value here,
//  because there is no client-side data source for either: silhouette
//  compatibility is a Wardrobe Graph judgement with no client model, and
//  user preference reads a server-computed preference vector this scorer
//  never receives. Neither is guessed at.
//
//  What this file does NOT do, and why that is the caller's job, not
//  this one's: it never decides that "not enough is known to show a
//  score at all" — that is `OutfitBuilderViewModel.currentCompatibility`'s
//  call, gated on how many canvas slots are actually filled, before this
//  type is ever invoked. This type only answers "given these garments,
//  what is the honest 0...1 reading per dimension", never "should a
//  number be shown".
//

import Foundation

public struct LocalCompatibilityScorer: CompatibilityScoring {

    /// Flat prior used whenever a dimension genuinely cannot be measured
    /// from what this scorer has. 0.6 rather than 0.5 (a true coin flip):
    /// an outfit a user is actively assembling in the builder is already
    /// more likely coherent than random, the same reasoning the server's
    /// own documented priors use to avoid punishing a thin profile on a
    /// user's first morning.
    static let unmeasuredPrior: Double = 0.6

    public init() {}

    public func scoreOutfit(items: [ClosetItem], context: CompatibilityContext) -> CompatibilityBreakdown {
        CompatibilityBreakdown(
            colorCompatibility: Self.colorCompatibility(items),
            formalityAlignment: Self.formalityAlignment(items),
            silhouetteCompatibility: Self.unmeasuredPrior,
            seasonWeatherSuitability: Self.seasonWeatherSuitability(items, weather: context.weather),
            userPreference: Self.unmeasuredPrior,
            historicalCoWear: Self.historicalCoWear(items, feedback: context.recentFeedback),
            occasionRelevance: Self.occasionRelevance(items, occasion: context.occasion),
            availabilityLaundry: Self.availabilityLaundry(items)
        )
    }

    public func scoreItem(_ candidate: ClosetItem, against existingItems: [ClosetItem], context: CompatibilityContext) -> CompatibilityBreakdown {
        scoreOutfit(items: existingItems + [candidate], context: context)
    }
}

// MARK: - Color compatibility (25%)

extension LocalCompatibilityScorer {
    /// Words this heuristic treats as pairing with anything, mirroring
    /// menswear convention (and, loosely, `ClosetColorSpectrumOrder`'s
    /// real HSV-based neutral test — reimplemented here as a small word
    /// list rather than shared with it, since that type lives in
    /// `Features/Closet` and `Domain/Services` does not depend on
    /// `Features/`; see this file's header on scope).
    static let neutralColorWords: Set<String> = [
        "black", "white", "grey", "gray", "navy", "beige", "tan", "brown",
        "cream", "ivory", "khaki", "charcoal", "stone", "bone", "camel",
        "taupe", "oatmeal", "ecru", "denim"
    ]

    /// The colour word this scorer actually compares: trimmed, lowercased,
    /// last word — "tobacco brown" reduces to "brown" the same way
    /// `AstraGarmentColor.swatch(for:)` reduces it, so a modifier never
    /// hides a colour this heuristic would otherwise recognize.
    static func baseColorWord(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.split(separator: " ").last.map(String.init)
    }

    /// Average pairwise harmony across every resolvable colour pair.
    ///
    /// Fewer than two garments with a recorded colour leaves nothing to
    /// compare, so this returns the flat prior rather than a fabricated
    /// reading — the same "absent is honest" rule this file's header
    /// states.
    static func colorCompatibility(_ items: [ClosetItem]) -> Double {
        let words = items.compactMap { baseColorWord($0.primaryColor) }
        guard words.count >= 2 else { return unmeasuredPrior }

        var total = 0.0
        var pairCount = 0
        for i in 0..<words.count {
            for j in (i + 1)..<words.count {
                total += pairHarmony(words[i], words[j])
                pairCount += 1
            }
        }
        guard pairCount > 0 else { return unmeasuredPrior }
        return total / Double(pairCount)
    }

    /// One pair's harmony, 0...1. Three bands, in order of how confident
    /// the rule actually is:
    ///   - the same word: a monochrome pairing, which menswear treats as
    ///     always safe.
    ///   - either word is neutral: neutrals pair with anything by
    ///     definition, so this is nearly as safe.
    ///   - two different chromatic colours: genuinely unclear without a
    ///     real colour-harmony model (that is `ClosetColorSpectrumOrder`'s
    ///     job, not this one's), so this returns a modest prior leaning
    ///     positive rather than guessing a clash — a considered outfit is
    ///     more often intentional than accidental.
    private static func pairHarmony(_ first: String, _ second: String) -> Double {
        if first == second { return 0.9 }
        if neutralColorWords.contains(first) || neutralColorWords.contains(second) { return 0.85 }
        return 0.55
    }
}

// MARK: - Formality alignment (20%)

extension LocalCompatibilityScorer {
    /// How tightly the outfit's `formalityScore`s cluster, 0...1.
    ///
    /// Uses the RANGE (max − min) rather than variance: this is a small,
    /// human-legible signal (two items 0 and 100 apart are maximally
    /// misaligned; two items at the same score are perfectly aligned),
    /// and a scorer whose whole point is transparency to the UI gains
    /// nothing from a statistic nobody reading this file could sanity-
    /// check by eye.
    static func formalityAlignment(_ items: [ClosetItem]) -> Double {
        let scores = items.compactMap(\.formalityScore).map(Double.init)
        guard scores.count >= 2, let minScore = scores.min(), let maxScore = scores.max() else {
            return unmeasuredPrior
        }
        let range = maxScore - minScore
        return max(0, min(1, 1 - range / 100))
    }
}

// MARK: - Season/weather suitability (10%)

extension LocalCompatibilityScorer {
    /// Fraction of season-tagged garments whose `seasonality` covers the
    /// weather's implied season, 0...1. Garments with no `seasonality`
    /// recorded are excluded from the average rather than counted
    /// against the outfit — an empty tag list is "not recorded", not
    /// "wrong for every season".
    static func seasonWeatherSuitability(_ items: [ClosetItem], weather: WeatherSnapshot?) -> Double {
        guard let weather else { return unmeasuredPrior }
        let expected = impliedSeason(forCelsius: weather.temperatureHigh)

        let tagged = items.filter { !$0.seasonality.isEmpty }
        guard !tagged.isEmpty else { return unmeasuredPrior }

        let matching = tagged.filter { $0.seasonality.contains(expected) || $0.seasonality.contains(.allSeason) }
        return Double(matching.count) / Double(tagged.count)
    }

    /// A coarse, documented Celsius→season mapping. Not a calendar season
    /// (this app has users in both hemispheres) — purely a "how warm does
    /// a garment need to be" bucket, which is the only thing
    /// `seasonality` actually encodes.
    private static func impliedSeason(forCelsius high: Double) -> Season {
        switch high {
        case ..<8: .winter
        case 8..<18: .fall
        case 18..<24: .spring
        default: .summer
        }
    }
}

// MARK: - Historical co-wear/feedback (10%)

extension LocalCompatibilityScorer {
    /// Positive-signal fraction among the `style_feedback` rows that
    /// target one of these garments, 0...1.
    ///
    /// A user with no feedback on any of these items is a cold start, not
    /// evidence of anything, and gets the flat prior — matching
    /// `P4-OUTFIT-06`'s acceptance criterion for the server's own
    /// historical co-wear sub-scorer ("returns a neutral default for a
    /// user with no wear history, not an error").
    static func historicalCoWear(_ items: [ClosetItem], feedback: [StyleFeedback]) -> Double {
        guard !feedback.isEmpty else { return unmeasuredPrior }
        let itemIDs = Set(items.map(\.id))
        let relevant = feedback.filter { $0.targetType == .closetItem && itemIDs.contains($0.targetID) }
        guard !relevant.isEmpty else { return unmeasuredPrior }

        let positive = relevant.filter(isPositiveSignal).count
        return Double(positive) / Double(relevant.count)
    }

    private static func isPositiveSignal(_ entry: StyleFeedback) -> Bool {
        switch entry.signal {
        case .like, .wore, .saved, .purchased: true
        case .dislike, .skipped, .returned, .tooFormal, .tooCasual, .badFit, .wrongColor: false
        }
    }
}

// MARK: - Occasion relevance (5%)

extension LocalCompatibilityScorer {
    /// How close the outfit's average formality sits to the occasion's
    /// dress code, 0...1. Absent either half of that comparison — no
    /// occasion, no dress code, or no item carries a `formalityScore` —
    /// returns the flat prior.
    static func occasionRelevance(_ items: [ClosetItem], occasion: Occasion?) -> Double {
        guard let dressCode = occasion?.dressCode else { return unmeasuredPrior }
        let scores = items.compactMap(\.formalityScore).map(Double.init)
        guard !scores.isEmpty else { return unmeasuredPrior }

        let outfitFormality = scores.reduce(0, +) / Double(scores.count)
        let expectedFormality = expectedFormalityScore(for: dressCode)
        return max(0, min(1, 1 - abs(outfitFormality - expectedFormality) / 100))
    }

    /// A documented, approximate midpoint for each dress code on the same
    /// 0-100 scale `closet_items.formality_score` uses. Approximate by
    /// necessity — a dress code names a register, not a single number —
    /// but a midpoint is the honest way to compare against a garment
    /// score that IS a single number.
    private static func expectedFormalityScore(for dressCode: DressCode) -> Double {
        switch dressCode {
        case .athletic: 5
        case .ultraCasual: 10
        case .casual: 25
        case .smartCasual: 40
        case .businessCasual: 55
        case .businessFormal: 70
        case .formal: 85
        case .blackTie: 95
        }
    }
}

// MARK: - Availability/laundry (5%)

extension LocalCompatibilityScorer {
    /// Fraction of garments actually wearable today, 0...1. Unlike every
    /// dimension above, this is always fully computable — `isWearableToday`
    /// reads only fields every `ClosetItem` already carries — so there is
    /// no flat-prior branch here.
    static func availabilityLaundry(_ items: [ClosetItem]) -> Double {
        guard !items.isEmpty else { return 1 }
        let wearable = items.filter(\.isWearableToday).count
        return Double(wearable) / Double(items.count)
    }
}
