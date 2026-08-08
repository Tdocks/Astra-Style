//
//  OutfitRecommendationWireTests.swift
//  AstraStyleTests
//
//  The contract between `/outfits/rank` and every screen that shows a
//  recommendation.
//
//  THESE TESTS ARE WRITTEN AGAINST LITERAL JSON, ON PURPOSE. Encoding a Swift
//  value and decoding it back proves the type is self-consistent and proves
//  nothing at all about whether it agrees with the server — which is the only
//  question that matters here, and the one that produced this file. The
//  payloads below are hand-written to match
//  `supabase/functions/_shared/scoring/wire.ts` exactly. If the server's keys
//  change, these fail; if only Swift changes, these fail. A round-trip test
//  would have sailed through both.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("OutfitRecommendation — the /outfits/rank wire contract")
struct OutfitRecommendationWireTests {

    private func decode(_ json: String) throws -> OutfitRecommendation {
        try JSONDecoder().decode(OutfitRecommendation.self, from: Data(json.utf8))
    }

    /// Exactly what `toScoredOutfit` emits, keys and all.
    private let fullPayload = """
    {
      "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
      "name": "Olive polo, stone chinos",
      "reason": "Three neutrals with real value separation.",
      "compatibility_score": 84,
      "item_ids": ["3F2504E0-4F89-11D3-9A0C-0305E82C3302"],
      "missing_product_ids": [],
      "breakdown": {
        "color_compatibility": 0.97,
        "formality_alignment": 0.71,
        "silhouette_internal": 0.9,
        "season_weather_suitability": 0.75,
        "user_preference": 0.7,
        "historical_co_wear": 0.667,
        "occasion_relevance": 0.8,
        "availability_laundry": 1.0
      },
      "unmeasured": ["today's weather (no forecast available)"],
      "formality_register": 30
    }
    """

    @Test("Every snake_case key the server sends lands on the right property")
    func decodesTheServersKeys() throws {
        let recommendation = try decode(fullPayload)
        #expect(recommendation.compatibilityScore == 84)
        #expect(recommendation.itemIDs.count == 1)
        #expect(recommendation.formalityRegister == 30)

        let breakdown = try #require(recommendation.breakdown)
        // Each one asserted separately: a single wrong CodingKey throws, but a
        // wrong MAPPING between two keys of the same type would not, and that
        // is the mistake a hand-written key list actually makes.
        #expect(breakdown.colorCompatibility == 0.97)
        #expect(breakdown.formalityAlignment == 0.71)
        #expect(breakdown.silhouetteInternal == 0.9)
        #expect(breakdown.seasonWeatherSuitability == 0.75)
        #expect(breakdown.userPreference == 0.7)
        #expect(breakdown.historicalCoWear == 0.667)
        #expect(breakdown.occasionRelevance == 0.8)
        #expect(breakdown.availabilityLaundry == 1.0)
    }

    @Test("A camelCase breakdown does NOT decode, which is how we know the keys are load-bearing")
    func camelCaseIsRejected() throws {
        // The bug this file was written to catch. `CompatibilityBreakdown` was
        // `Codable` with no `CodingKeys` for its whole life — harmless while it
        // stayed inside the app, wrong the moment it crossed the network,
        // because `AstraAPIClient` uses a plain `JSONDecoder` with no key
        // strategy. If someone deletes those keys, this test is what notices.
        let camel = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "name": "n", "reason": "r", "compatibility_score": 50,
          "item_ids": [], "missing_product_ids": [],
          "breakdown": {
            "colorCompatibility": 0.9, "formalityAlignment": 0.9,
            "silhouetteInternal": 0.9, "seasonWeatherSuitability": 0.9,
            "userPreference": 0.9, "historicalCoWear": 0.9,
            "occasionRelevance": 0.9, "availabilityLaundry": 0.9
          },
          "unmeasured": []
        }
        """
        #expect(throws: (any Error).self) { try decode(camel) }
    }

    @Test("frame_harmony is absent from the server and decodes as nil, not zero")
    func frameHarmonyIsNilNotZero() throws {
        // Nil collapses `silhouetteCompatibility` to `silhouetteInternal`.
        // Zero would say the garments actively do not suit this wearer, which
        // the server has no basis whatsoever to claim — it never sees a body.
        let breakdown = try #require(try decode(fullPayload).breakdown)
        #expect(breakdown.frameHarmony == nil)
        #expect(breakdown.silhouetteCompatibility == breakdown.silhouetteInternal)
    }

    @Test("unmeasured survives the wire, because the whole honesty rule rests on it")
    func unmeasuredSurvives() throws {
        let recommendation = try decode(fullPayload)
        #expect(recommendation.unmeasured == ["today's weather (no forecast available)"])
        #expect(!recommendation.isFullyMeasured)
    }

    @Test("An empty unmeasured means fully measured, and that state is reachable")
    func fullyMeasuredIsReachable() throws {
        // If this were unreachable, `unmeasured` would be noise and every
        // screen would learn to ignore it. It has to be able to be empty.
        let json = fullPayload.replacingOccurrences(
            of: "[\"today's weather (no forecast available)\"]",
            with: "[]"
        )
        let recommendation = try decode(json)
        #expect(recommendation.isFullyMeasured)
        #expect(recommendation.unmeasured.isEmpty)
    }

    @Test("A response with no breakdown still decodes and shows the total alone")
    func breakdownIsOptional() throws {
        let minimal = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "name": "n", "reason": "r", "compatibility_score": 61,
          "item_ids": [], "missing_product_ids": [], "unmeasured": []
        }
        """
        let recommendation = try decode(minimal)
        #expect(recommendation.breakdown == nil)
        #expect(recommendation.compatibilityScore == 61)
    }

    @Test("A §26-era payload with none of the new fields still decodes")
    func legacyPayloadStillDecodes() throws {
        // The reason both fields are additive rather than a change to §26's
        // shape. An older server, or a cached response written before this
        // change, must not become undecodable.
        let legacy = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "name": "n", "reason": "r", "compatibility_score": 61,
          "item_ids": [], "missing_product_ids": []
        }
        """
        let recommendation = try decode(legacy)
        #expect(recommendation.unmeasured.isEmpty)
        #expect(recommendation.formalityRegister == nil)
    }

    @Test("The §26 fields are still required — a malformed payload throws")
    func requiredFieldsStayRequired() throws {
        // Additive must not mean lenient. A response missing its score is
        // broken, and decoding it to a zero would put "0" on a card.
        let missingScore = """
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"n","reason":"r","item_ids":[]}
        """
        #expect(throws: (any Error).self) { try decode(missingScore) }
    }
}
