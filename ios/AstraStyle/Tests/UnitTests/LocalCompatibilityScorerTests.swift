//
//  LocalCompatibilityScorerTests.swift
//  AstraStyleTests
//
//  Derived from `LocalCompatibilityScorer`'s own stated contract (its
//  file header): every dimension it cannot measure from what it was
//  given must fall back to the documented flat prior rather than a
//  fabricated reading, and every dimension it CAN measure must actually
//  move when the underlying data changes.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("LocalCompatibilityScorer")
struct LocalCompatibilityScorerTests {

    private func item(
        color: String? = nil,
        formality: Int? = nil,
        seasonality: [Season] = [],
        laundry: LaundryState = .clean,
        availability: AvailabilityState = .available
    ) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: "Fixture",
            category: .top,
            primaryColor: color,
            seasonality: seasonality,
            formalityScore: formality,
            laundryState: laundry,
            availabilityState: availability
        )
    }

    // MARK: - Color compatibility

    @Test("Fewer than two colored items falls back to the flat prior, not a fabricated score")
    func colorFallsBackWithInsufficientData() {
        let breakdown = LocalCompatibilityScorer().scoreOutfit(items: [item(color: "navy")], context: CompatibilityContext())
        #expect(breakdown.colorCompatibility == LocalCompatibilityScorer.unmeasuredPrior)
    }

    @Test("Two garments of the same color score higher than two unrelated chromatic colors")
    func monochromeScoresHigherThanUnrelatedChromatic() {
        let monochrome = LocalCompatibilityScorer.colorCompatibility([item(color: "navy"), item(color: "navy")])
        let unrelated = LocalCompatibilityScorer.colorCompatibility([item(color: "red"), item(color: "green")])
        #expect(monochrome > unrelated)
    }

    @Test("A neutral paired with a chromatic color scores between monochrome and unrelated-chromatic")
    func neutralPairingIsBetweenTheOtherTwoBands() {
        let monochrome = LocalCompatibilityScorer.colorCompatibility([item(color: "navy"), item(color: "navy")])
        let neutralPaired = LocalCompatibilityScorer.colorCompatibility([item(color: "black"), item(color: "red")])
        let unrelated = LocalCompatibilityScorer.colorCompatibility([item(color: "red"), item(color: "green")])
        #expect(neutralPaired < monochrome)
        #expect(neutralPaired > unrelated)
    }

    // MARK: - Formality alignment

    @Test("Same-formality items align perfectly")
    func sameFormalityAlignsPerfectly() {
        let score = LocalCompatibilityScorer.formalityAlignment([item(formality: 50), item(formality: 50)])
        #expect(score == 1)
    }

    @Test("Maximally distant formality scores align at zero")
    func maximallyDistantFormalityIsZero() {
        let score = LocalCompatibilityScorer.formalityAlignment([item(formality: 0), item(formality: 100)])
        #expect(score == 0)
    }

    @Test("Fewer than two formality-scored items falls back to the flat prior")
    func formalityFallsBackWithInsufficientData() {
        let score = LocalCompatibilityScorer.formalityAlignment([item(formality: 50)])
        #expect(score == LocalCompatibilityScorer.unmeasuredPrior)
    }

    // MARK: - Season/weather suitability

    @Test("No weather context falls back to the flat prior")
    func seasonFallsBackWithNoWeather() {
        let score = LocalCompatibilityScorer.seasonWeatherSuitability([item(seasonality: [.winter])], weather: nil)
        #expect(score == LocalCompatibilityScorer.unmeasuredPrior)
    }

    @Test("A winter coat scores fully suitable in cold weather; a summer-only piece scores unsuitable")
    func seasonMatchesColdWeather() {
        let coldWeather = WeatherSnapshot(temperatureHigh: -2, temperatureLow: -8, condition: .snow)
        let winterCoat = LocalCompatibilityScorer.seasonWeatherSuitability([item(seasonality: [.winter])], weather: coldWeather)
        let summerPiece = LocalCompatibilityScorer.seasonWeatherSuitability([item(seasonality: [.summer])], weather: coldWeather)
        #expect(winterCoat == 1)
        #expect(summerPiece == 0)
    }

    @Test("Items with no seasonality recorded are excluded, not counted as mismatched")
    func unrecordedSeasonalityIsExcludedNotPenalized() {
        let coldWeather = WeatherSnapshot(temperatureHigh: -2, temperatureLow: -8, condition: .snow)
        let score = LocalCompatibilityScorer.seasonWeatherSuitability(
            [item(seasonality: [.winter]), item(seasonality: [])],
            weather: coldWeather
        )
        #expect(score == 1, "The untagged item must not drag the average down")
    }

    // MARK: - Historical co-wear

    @Test("No feedback at all is a cold start and falls back to the flat prior")
    func historicalCoWearColdStart() {
        let score = LocalCompatibilityScorer.historicalCoWear([item()], feedback: [])
        #expect(score == LocalCompatibilityScorer.unmeasuredPrior)
    }

    @Test("Feedback naming these items skews the score toward their signals")
    func historicalCoWearReflectsRelevantFeedback() {
        let liked = item()
        let feedback = [
            StyleFeedback(id: UUID(), userID: UUID(), targetType: .closetItem, targetID: liked.id, signal: .like),
            StyleFeedback(id: UUID(), userID: UUID(), targetType: .closetItem, targetID: liked.id, signal: .wore)
        ]
        let score = LocalCompatibilityScorer.historicalCoWear([liked], feedback: feedback)
        #expect(score == 1)
    }

    @Test("Feedback about a different garment does not affect this outfit's score")
    func historicalCoWearIgnoresUnrelatedFeedback() {
        let subject = item()
        let feedback = [
            StyleFeedback(id: UUID(), userID: UUID(), targetType: .closetItem, targetID: UUID(), signal: .dislike)
        ]
        let score = LocalCompatibilityScorer.historicalCoWear([subject], feedback: feedback)
        #expect(score == LocalCompatibilityScorer.unmeasuredPrior)
    }

    // MARK: - Occasion relevance

    @Test("No occasion falls back to the flat prior")
    func occasionRelevanceFallsBackWithNoOccasion() {
        let score = LocalCompatibilityScorer.occasionRelevance([item(formality: 50)], occasion: nil)
        #expect(score == LocalCompatibilityScorer.unmeasuredPrior)
    }

    @Test("An outfit whose formality matches black tie scores higher than one that does not")
    func occasionRelevanceRewardsMatchingFormality() {
        let occasion = Occasion(id: UUID(), userID: UUID(), title: "Gala", startsAt: .now, dressCode: .blackTie)
        let matching = LocalCompatibilityScorer.occasionRelevance([item(formality: 95)], occasion: occasion)
        let mismatched = LocalCompatibilityScorer.occasionRelevance([item(formality: 5)], occasion: occasion)
        #expect(matching > mismatched)
    }

    // MARK: - Availability/laundry

    @Test("An empty outfit does not penalize availability")
    func availabilityIsFullForNoItems() {
        #expect(LocalCompatibilityScorer.availabilityLaundry([]) == 1)
    }

    @Test("An item in the laundry drags the availability score down")
    func laundryItemLowersAvailability() {
        let clean = item(laundry: .clean)
        let dirty = item(laundry: .laundry)
        let score = LocalCompatibilityScorer.availabilityLaundry([clean, dirty])
        #expect(score == 0.5)
    }

    // MARK: - Dimensions with no client-side data source

    @Test("Silhouette and user preference are always the flat prior — there is no local data source for either")
    func silhouetteAndUserPreferenceAreAlwaysUnmeasured() {
        let breakdown = LocalCompatibilityScorer().scoreOutfit(
            items: [item(color: "navy", formality: 50), item(color: "navy", formality: 50)],
            context: CompatibilityContext()
        )
        #expect(breakdown.silhouetteCompatibility == LocalCompatibilityScorer.unmeasuredPrior)
        #expect(breakdown.userPreference == LocalCompatibilityScorer.unmeasuredPrior)
    }

    // MARK: - scoreItem delegates to scoreOutfit

    @Test("scoreItem(_:against:context:) scores the candidate joined with the existing items")
    func scoreItemDelegatesToScoreOutfit() {
        let scorer = LocalCompatibilityScorer()
        let existing = [item(formality: 50)]
        let candidate = item(formality: 50)
        let viaScoreItem = scorer.scoreItem(candidate, against: existing, context: CompatibilityContext())
        let viaScoreOutfit = scorer.scoreOutfit(items: existing + [candidate], context: CompatibilityContext())
        #expect(viaScoreItem == viaScoreOutfit)
    }
}
