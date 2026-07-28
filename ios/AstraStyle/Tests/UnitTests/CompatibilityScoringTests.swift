//
//  CompatibilityScoringTests.swift
//  AstraStyleTests
//
//  Spec §22 "Unit tests: Compatibility scoring". Verifies
//  `CompatibilityBreakdown.score(weights:)` matches spec §10's published
//  formula exactly:
//    0.25 color + 0.20 formality + 0.15 silhouette + 0.10 season/weather
//    + 0.10 user preference + 0.10 historical co-wear + 0.05 occasion
//    + 0.05 availability/laundry
//

import Testing
@testable import AstraStyle

@Suite("CompatibilityBreakdown scoring")
struct CompatibilityScoringTests {

    @Test("A perfect score across every dimension yields 100")
    func perfectScoreIsOneHundred() {
        let breakdown = CompatibilityBreakdown(
            colorCompatibility: 1, formalityAlignment: 1, silhouetteCompatibility: 1,
            seasonWeatherSuitability: 1, userPreference: 1, historicalCoWear: 1,
            occasionRelevance: 1, availabilityLaundry: 1
        )
        #expect(breakdown.score() == 100)
    }

    @Test("A zero score across every dimension yields 0")
    func zeroScoreIsZero() {
        let breakdown = CompatibilityBreakdown(
            colorCompatibility: 0, formalityAlignment: 0, silhouetteCompatibility: 0,
            seasonWeatherSuitability: 0, userPreference: 0, historicalCoWear: 0,
            occasionRelevance: 0, availabilityLaundry: 0
        )
        #expect(breakdown.score() == 0)
    }

    @Test("Color compatibility alone contributes exactly its 25% weight")
    func colorAloneContributesQuarter() {
        let breakdown = CompatibilityBreakdown(
            colorCompatibility: 1, formalityAlignment: 0, silhouetteCompatibility: 0,
            seasonWeatherSuitability: 0, userPreference: 0, historicalCoWear: 0,
            occasionRelevance: 0, availabilityLaundry: 0
        )
        #expect(breakdown.score() == 25)
    }

    @Test("Formality alignment alone contributes exactly its 20% weight")
    func formalityAloneContributesTwenty() {
        let breakdown = CompatibilityBreakdown(
            colorCompatibility: 0, formalityAlignment: 1, silhouetteCompatibility: 0,
            seasonWeatherSuitability: 0, userPreference: 0, historicalCoWear: 0,
            occasionRelevance: 0, availabilityLaundry: 0
        )
        #expect(breakdown.score() == 20)
    }

    @Test("Occasion relevance and availability/laundry each contribute exactly 5%")
    func smallestWeightsContributeFivePercentEach() {
        let occasionOnly = CompatibilityBreakdown(
            colorCompatibility: 0, formalityAlignment: 0, silhouetteCompatibility: 0,
            seasonWeatherSuitability: 0, userPreference: 0, historicalCoWear: 0,
            occasionRelevance: 1, availabilityLaundry: 0
        )
        let availabilityOnly = CompatibilityBreakdown(
            colorCompatibility: 0, formalityAlignment: 0, silhouetteCompatibility: 0,
            seasonWeatherSuitability: 0, userPreference: 0, historicalCoWear: 0,
            occasionRelevance: 0, availabilityLaundry: 1
        )
        #expect(occasionOnly.score() == 5)
        #expect(availabilityOnly.score() == 5)
    }

    @Test("Custom weights override the spec §10 defaults")
    func customWeightsAreRespected() {
        var weights = CompatibilityBreakdown.Weights()
        weights.color = 1.0
        weights.formality = 0
        weights.silhouette = 0
        weights.seasonWeather = 0
        weights.userPreference = 0
        weights.historicalCoWear = 0
        weights.occasionRelevance = 0
        weights.availabilityLaundry = 0

        let breakdown = CompatibilityBreakdown(
            colorCompatibility: 0.5, formalityAlignment: 1, silhouetteCompatibility: 1,
            seasonWeatherSuitability: 1, userPreference: 1, historicalCoWear: 1,
            occasionRelevance: 1, availabilityLaundry: 1
        )
        #expect(breakdown.score(weights: weights) == 50)
    }
}
