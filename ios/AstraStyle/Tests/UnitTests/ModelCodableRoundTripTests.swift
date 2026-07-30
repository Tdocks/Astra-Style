//
//  ModelCodableRoundTripTests.swift
//  AstraStyleTests
//
//  Spec §22 "Unit tests: Mapping API models to local models". Decodes
//  hand-written snake_case JSON shaped like what Postgrest/Edge Functions
//  actually return, confirming every `CodingKeys` mapping is correct in
//  both directions — not just that `Codable` was synthesized.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Model Codable round-trips")
struct ModelCodableRoundTripTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    @Test("ClosetItem decodes snake_case Postgrest JSON")
    func closetItemDecodesSnakeCaseJSON() throws {
        let json = """
        {
          "id": "9B3F1B3E-9E2C-4A9A-8A2B-5B6E1D9F2C11",
          "user_id": "00000000-0000-4000-8000-000000000001",
          "name": "Merino Crewneck Sweater",
          "brand": "Uniqlo",
          "category": "top",
          "subcategory": "Sweater",
          "primary_color": "navy",
          "secondary_colors": [],
          "pattern": "solid",
          "material": ["merino wool"],
          "size": "M",
          "fit": "regular",
          "condition": "good",
          "seasonality": ["fall", "winter"],
          "formality_score": 45,
          "warmth_score": 70,
          "water_resistance_score": null,
          "purchase_date": "2024-01-15T00:00:00Z",
          "price_paid": 50,
          "currency": "USD",
          "retailer": "Uniqlo",
          "product_url": null,
          "wear_count": 30,
          "last_worn_at": "2026-07-27T00:00:00Z",
          "laundry_state": "clean",
          "availability_state": "available",
          "archived_at": null,
          "embedding": null,
          "created_at": "2024-01-15T00:00:00Z",
          "updated_at": "2026-07-27T00:00:00Z"
        }
        """
        let item = try decoder.decode(ClosetItem.self, from: Data(json.utf8))

        #expect(item.name == "Merino Crewneck Sweater")
        #expect(item.category == .top)
        #expect(item.laundryState == .clean)
        #expect(item.wearCount == 30)
        #expect(item.pricePaid == 50)
        #expect(item.seasonality == [.fall, .winter])
    }

    @Test("ClosetItem round-trips through encode -> decode with identical semantic content")
    func closetItemRoundTrips() throws {
        let original = ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: "Selvedge Denim",
            brand: "Buck Mason",
            category: .bottom,
            subcategory: "Jeans",
            primaryColor: "indigo",
            secondaryColors: [],
            pattern: .solid,
            material: ["cotton denim"],
            size: "33x32",
            fit: .slim,
            condition: .good,
            seasonality: [.allSeason],
            formalityScore: 20,
            pricePaid: 128,
            currency: "USD",
            retailer: "Buck Mason",
            wearCount: 55,
            laundryState: .clean,
            availabilityState: .available
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ClosetItem.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.category == original.category)
        #expect(decoded.pricePaid == original.pricePaid)
        #expect(decoded.wearCount == original.wearCount)
    }

    @Test("DailyBrief decodes snake_case JSON with nested weather/schedule snapshots")
    func dailyBriefDecodesNestedSnapshots() throws {
        let json = """
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "user_id": "00000000-0000-4000-8000-000000000001",
          "brief_date": "2026-07-28T00:00:00Z",
          "primary_outfit_id": "22222222-2222-4222-8222-222222222222",
          "alternative_outfit_ids": [],
          "weather_snapshot": {
            "temperature_high": 74,
            "temperature_low": 61,
            "apparent_temperature": 73,
            "condition": "partly_cloudy",
            "precipitation_chance": 0.1,
            "wind_speed": 8,
            "humidity": 0.45,
            "location_name": "Brooklyn, NY"
          },
          "schedule_snapshot": {
            "event_count": 3,
            "earliest_formality_level": "balanced",
            "headline": "Client meeting at 10:30 AM"
          },
          "kyra_message": "I'd wear the olive knit polo today."
        }
        """
        let brief = try decoder.decode(DailyBrief.self, from: Data(json.utf8))

        #expect(brief.weatherSnapshot?.condition == .partlyCloudy)
        #expect(brief.weatherSnapshot?.temperatureHigh == 74)
        #expect(brief.scheduleSnapshot?.eventCount == 3)
        #expect(brief.scheduleSnapshot?.earliestFormalityLevel == .balanced)
        #expect(brief.hasPrimaryOutfit)
    }

    @Test("KyraCard round-trips its custom Codable envelope for every case")
    func kyraCardRoundTrips() throws {
        let cards: [KyraCard] = [
            .outfit(outfitID: UUID()),
            .product(productCandidateID: UUID()),
            .closetItem(closetItemID: UUID()),
            .comparisonTable(ComparisonTable(title: "Compare", columnHeaders: ["A", "B"], rows: [["1", "2"]])),
            .action(KyraSuggestedAction(id: "wear", label: "Wear This", kind: .wearOutfit))
        ]

        for card in cards {
            let data = try encoder.encode(card)
            let decoded = try decoder.decode(KyraCard.self, from: data)
            #expect(decoded == card)
        }
    }

    @Test("KyraStructuredResponse decodes the full response schema from spec §11, including intent")
    func kyraStructuredResponseDecodesFullSchema() throws {
        let json = """
        {
          "message": "I'd wear the olive knit polo with stone trousers.",
          "intent": "daily_outfit",
          "cards": [{"type": "outfit", "outfit_id": "33333333-3333-4333-8333-333333333333"}],
          "suggested_actions": [{"id": "wear", "label": "Wear This", "kind": "wear_outfit"}],
          "memory_proposals": [{"memory_type": "preference", "content": "Prefers tapered trousers.", "confidence": 0.8}],
          "confidence": 0.91
        }
        """
        let response = try decoder.decode(KyraStructuredResponse.self, from: Data(json.utf8))

        #expect(response.intent == .dailyOutfit)
        #expect(response.cards.count == 1)
        #expect(response.suggestedActions.first?.kind == .wearOutfit)
        #expect(response.memoryProposals.first?.memoryType == .preference)
        #expect(response.confidence == 0.91)
    }

    @Test("StyleFeedback decodes every documented signal value from spec §9")
    func styleFeedbackSignalsAllDecode() throws {
        let signals = ["like", "dislike", "wore", "skipped", "saved", "purchased", "returned", "too_formal", "too_casual", "bad_fit", "wrong_color"]
        for raw in signals {
            let json = """
            {"id":"\(UUID().uuidString)","user_id":"\(UUID().uuidString)","target_type":"outfit","target_id":"\(UUID().uuidString)","signal":"\(raw)","reason_tags":[],"free_text":null,"created_at":"2026-07-28T00:00:00Z"}
            """
            let feedback = try decoder.decode(StyleFeedback.self, from: Data(json.utf8))
            #expect(feedback.signal.rawValue == raw)
        }
    }
}
