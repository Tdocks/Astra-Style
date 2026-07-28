//
//  SliceCodableRoundTripTests.swift
//  AstraStyleTests
//
//  Codable round-trips for the vertical slice's own wire contracts (spec
//  §22 "Unit tests: Mapping API models to local models" — see also
//  `ModelCodableRoundTripTests.swift` for the app-wide equivalents this
//  file deliberately doesn't duplicate).
//
//  Covers:
//   - The minimal add-garment `ClosetItem` shape (name, category,
//     primary_color only) that `SliceViewModel.addGarment()` sends.
//   - The `POST /outfits/generate` response contract this slice assumes
//     from the Edge Function: `AstraResponseEnvelope<[OutfitRecommendation]>`
//     with snake_case keys.
//   - The `outfit_wears` insert shape `OutfitRepository.recordWear` sends
//     for "Mark Worn".
//   - `OutfitSource.kyraGenerated`'s wire value, which the
//     `LiveOutfitRepository.saveOutfit` fix in this same change now
//     actually writes to the database — regression coverage for a real
//     bug found while wiring the slice up: its raw value used to be
//     `"kyra_generated"`, which is not a member of Postgres's
//     `outfit_source` enum type at all (valid values are `ai_generated`,
//     `user_created`, `kyra_suggested`, `studio_derived` — see
//     `supabase/migrations/20260728100100_core_enums.sql`), so every
//     insert through that path failed with an invalid-enum-value error
//     before this fix.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Vertical slice Codable round-trips")
struct SliceCodableRoundTripTests {

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

    // MARK: - Add-garment request shape

    @Test("Minimal add-garment ClosetItem encodes without nulling NOT NULL-with-default columns")
    func minimalClosetItemEncodesCleanly() throws {
        let item = ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: "Navy Merino Sweater",
            category: .top,
            primaryColor: "navy"
        )

        let data = try encoder.encode(item)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Swift's synthesized `Encodable` omits (not `null`s) unset
        // Optional properties via `encodeIfPresent` — asserting that here
        // matters because `closet_items.currency` is `NOT NULL DEFAULT
        // 'USD'`: an explicit JSON `null` would violate that constraint on
        // insert, whereas an omitted key lets Postgres apply the column
        // default. If this assertion ever starts failing, the insert path
        // in `LiveClosetRepository.createItem` needs a real fix, not just
        // a different test.
        #expect(object["currency"] == nil)
        #expect(object["brand"] == nil)
        #expect(object["subcategory"] == nil)

        #expect(object["name"] as? String == "Navy Merino Sweater")
        #expect(object["category"] as? String == "top")
        #expect(object["primary_color"] as? String == "navy")
        #expect(object["wear_count"] as? Int == 0)
    }

    @Test("Minimal add-garment ClosetItem round-trips through encode -> decode")
    func minimalClosetItemRoundTrips() throws {
        let original = ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: "Charcoal Chinos",
            category: .bottom,
            primaryColor: "charcoal"
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ClosetItem.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.category == .bottom)
        #expect(decoded.primaryColor == "charcoal")
        #expect(decoded.wearCount == 0)
        #expect(decoded.laundryState == .clean)
    }

    // MARK: - `POST /outfits/generate` response contract

    @Test("AstraResponseEnvelope<[OutfitRecommendation]> decodes the assumed outfits/generate response")
    func outfitsGenerateResponseDecodes() throws {
        let json = """
        {
          "data": [
            {
              "id": "9B3F1B3E-9E2C-4A9A-8A2B-5B6E1D9F2C11",
              "name": "Smart Casual Weekday",
              "reason": "A tailored top with straight trousers and clean leather shoes.",
              "compatibility_score": 82,
              "item_ids": [
                "11111111-1111-4111-8111-111111111111",
                "22222222-2222-4222-8222-222222222222",
                "33333333-3333-4333-8333-333333333333"
              ],
              "missing_product_ids": []
            }
          ],
          "error": null,
          "request_id": "req_abc123"
        }
        """

        let envelope = try decoder.decode(AstraResponseEnvelope<[OutfitRecommendation]>.self, from: Data(json.utf8))
        let recommendations = try #require(envelope.data)

        #expect(recommendations.count == 1)
        let recommendation = try #require(recommendations.first)
        #expect(recommendation.name == "Smart Casual Weekday")
        #expect(recommendation.compatibilityScore == 82)
        #expect(recommendation.itemIDs.count == 3)
        #expect(recommendation.missingProductIDs.isEmpty)
        #expect(envelope.error == nil)
    }

    @Test("AstraResponseEnvelope<[OutfitRecommendation]> decodes a structured server-side error")
    func outfitsGenerateErrorResponseDecodes() throws {
        let json = """
        {
          "data": null,
          "error": {
            "category": "validation",
            "message": "Add at least a top and a bottom before generating an outfit."
          },
          "request_id": "req_def456"
        }
        """

        let envelope = try decoder.decode(AstraResponseEnvelope<[OutfitRecommendation]>.self, from: Data(json.utf8))
        #expect(envelope.data == nil)

        let error = try #require(envelope.error)
        let astraError = error.asAstraError(statusCode: 422, requestID: "req_def456")
        #expect(astraError.category == .validation)
        #expect(astraError.message == "Add at least a top and a bottom before generating an outfit.")
    }

    // MARK: - "Mark Worn" (`outfit_wears` insert) shape

    @Test("OutfitWear encodes worn_at as ISO8601 and omits unset optional fields")
    func outfitWearEncodesCleanly() throws {
        let wear = OutfitWear(
            id: UUID(),
            outfitID: UUID(),
            userID: UUID(),
            wornAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let data = try encoder.encode(wear)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["occasion"] == nil)
        #expect(object["rating"] == nil)
        #expect(object["feedback"] == nil)
        #expect(object["weather_snapshot"] == nil)
        #expect(object["worn_at"] as? String != nil)
    }

    @Test("OutfitWear decodes a realistic outfit_wears row")
    func outfitWearDecodesRealisticRow() throws {
        let json = """
        {
          "id": "44444444-4444-4444-8444-444444444444",
          "outfit_id": "9B3F1B3E-9E2C-4A9A-8A2B-5B6E1D9F2C11",
          "user_id": "00000000-0000-4000-8000-000000000001",
          "worn_at": "2026-07-28T09:00:00Z",
          "occasion": null,
          "rating": null,
          "feedback": null
        }
        """

        let wear = try decoder.decode(OutfitWear.self, from: Data(json.utf8))
        #expect(wear.occasion == nil)
        #expect(wear.rating == nil)
    }

    // MARK: - `OutfitSource.kyraGenerated` regression (see header comment)

    @Test("OutfitSource.kyraGenerated encodes as the DB's ai_generated enum value, not kyra_generated")
    func outfitSourceKyraGeneratedEncodesAsAiGenerated() throws {
        let outfit = Outfit(
            id: UUID(),
            userID: UUID(),
            name: "Smart Casual Weekday",
            source: .kyraGenerated
        )

        let data = try encoder.encode(outfit)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["source"] as? String == "ai_generated")
        #expect(object["source"] as? String != "kyra_generated")
    }

    @Test(
        "OutfitSource decodes the two raw values that are actually load-bearing on the slice's save path",
        arguments: [
            ("ai_generated", OutfitSource.kyraGenerated),
            ("user_created", OutfitSource.userCreated)
        ]
    )
    func outfitSourceDecodesSliceRelevantValues(rawValue: String, expected: OutfitSource) throws {
        // Only `ai_generated` (saveOutfit's default) and `user_created` are
        // both real Postgres `outfit_source` values *and* exercised by this
        // slice today. `.kyraEdited` ("kyra_edited") and `.imported`
        // ("imported") are pre-existing mismatches against the DB's actual
        // remaining values (`kyra_suggested`, `studio_derived`) that predate
        // this change and aren't touched by any slice code path — see the
        // file-header comment and `Domain/Models/Enums.swift`'s doc comment
        // on `OutfitSource` for why those are left alone here.
        let json = "\"\(rawValue)\""
        let source = try decoder.decode(OutfitSource.self, from: Data(json.utf8))
        #expect(source == expected)
    }
}
