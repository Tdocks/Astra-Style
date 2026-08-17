//
//  KyraStructuredResponseDecodingTests.swift
//  AstraStyleTests
//
//  P5-TEST-01: unit tests for the defensive decoding P5-CORE-01 added to
//  `KyraStructuredResponse.init(from:)`. `ModelCodableRoundTripTests`
//  already carries one happy-path decode (`daily_outfit`, spec §22's
//  baseline mapping check); this file is specifically the malformed- and
//  partially-invalid-payload fixture set P5-TEST-01 asks for, split into
//  its own suite rather than appended to that one because the combined
//  cases pushed `ModelCodableRoundTripTests` past `type_body_length`
//  (280 lines) — the same reason `DailyBriefDecodingTests` exists
//  separately from `ModelCodableRoundTripTests` rather than folded into it.
//
//  Each test name states the degradation path it proves, matching
//  `DailyBriefDecodingTests`'s convention of one behavior per test.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("KyraStructuredResponse defensive decoding")
struct KyraStructuredResponseDecodingTests {

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Minimal but schema-complete payload for a given `intent` string, with
    /// no cards/actions/proposals — isolates what each test is actually
    /// about instead of re-stating the full schema every time.
    private func minimalResponseJSON(intent: String, confidence: Double = 0.7) -> String {
        """
        {
          "message": "Kyra's reply.",
          "intent": "\(intent)",
          "cards": [],
          "suggested_actions": [],
          "memory_proposals": [],
          "confidence": \(confidence)
        }
        """
    }

    private func decodeResponse(_ json: String) throws -> KyraStructuredResponse {
        try decoder.decode(KyraStructuredResponse.self, from: Data(json.utf8))
    }

    @Test("Decodes every documented intent value (spec §11)")
    func decodesEveryDocumentedIntent() throws {
        let expected: [String: KyraIntent] = [
            "daily_outfit": .dailyOutfit,
            "product_advice": .productAdvice,
            "outfit_review": .outfitReview,
            "packing": .packing,
            "education": .education,
            "general": .general
        ]
        for (raw, intent) in expected {
            let response = try decodeResponse(minimalResponseJSON(intent: raw))
            #expect(response.intent == intent, "expected \(raw) to decode to \(intent)")
        }
    }

    @Test("An unrecognized intent degrades to .general instead of failing the decode")
    func degradesUnknownIntentToGeneral() throws {
        let response = try decodeResponse(minimalResponseJSON(intent: "shopping_spree"))
        #expect(response.intent == .general)
    }

    @Test("An unrecognized card type is dropped from cards, not fatal to the response")
    func dropsUnknownCardType() throws {
        let response = try decodeResponse("""
        {
          "message": "Here's what I'd wear, plus something new.",
          "intent": "daily_outfit",
          "cards": [
            {"type": "outfit", "outfit_id": "33333333-3333-4333-8333-333333333333"},
            {"type": "weather_widget", "temperature": 61}
          ],
          "suggested_actions": [],
          "memory_proposals": [],
          "confidence": 0.7
        }
        """)
        let expectedOutfitID = try #require(UUID(uuidString: "33333333-3333-4333-8333-333333333333"))
        #expect(response.cards.count == 1)
        #expect(response.cards.first == .outfit(outfitID: expectedOutfitID))
        #expect(response.message == "Here's what I'd wear, plus something new.")
    }

    @Test("A malformed card (recognized type, missing required field) is dropped without failing its siblings")
    func dropsMalformedCardWithoutFailingSiblings() throws {
        let response = try decodeResponse("""
        {
          "message": "Two options for you.",
          "intent": "product_advice",
          "cards": [
            {"type": "outfit"},
            {"type": "product", "product_candidate_id": "44444444-4444-4444-8444-444444444444"}
          ],
          "suggested_actions": [],
          "memory_proposals": [],
          "confidence": 0.7
        }
        """)
        #expect(response.cards.count == 1)
        guard case .product(let productCandidateID) = response.cards.first else {
            Issue.record("expected the surviving card to be the .product card")
            return
        }
        #expect(productCandidateID == UUID(uuidString: "44444444-4444-4444-8444-444444444444"))
    }

    @Test("An unrecognized suggested-action kind is dropped rather than crashing the decode")
    func dropsUnknownSuggestedActionKind() throws {
        let response = try decodeResponse("""
        {
          "message": "Want to see more?",
          "intent": "general",
          "cards": [],
          "suggested_actions": [
            {"id": "wear", "label": "Wear This", "kind": "wear_outfit"},
            {"id": "teleport", "label": "Teleport There", "kind": "teleport_to_store"}
          ],
          "memory_proposals": [],
          "confidence": 0.7
        }
        """)
        #expect(response.suggestedActions.count == 1)
        #expect(response.suggestedActions.first?.id == "wear")
    }

    @Test("Missing optional collections (cards, suggested_actions, memory_proposals) default to empty arrays")
    func defaultsMissingCollectionsToEmpty() throws {
        let response = try decodeResponse("""
        {
          "message": "Just chatting.",
          "intent": "general",
          "confidence": 0.5
        }
        """)
        #expect(response.cards.isEmpty)
        #expect(response.suggestedActions.isEmpty)
        #expect(response.memoryProposals.isEmpty)
    }

    @Test("An out-of-range top-level confidence is clamped to 0...1, not trusted verbatim")
    func clampsOutOfRangeConfidence() throws {
        let tooHigh = try decodeResponse(minimalResponseJSON(intent: "general", confidence: 42))
        #expect(tooHigh.confidence == 1.0)

        let tooLow = try decodeResponse(minimalResponseJSON(intent: "general", confidence: -3))
        #expect(tooLow.confidence == 0.0)
    }

    @Test("A memory proposal with an unrecognized memory_type is dropped, not guessed")
    func dropsUnrecognizedMemoryType() throws {
        let response = try decodeResponse("""
        {
          "message": "Noted a couple of things.",
          "intent": "general",
          "cards": [],
          "suggested_actions": [],
          "memory_proposals": [
            {"memory_type": "astrology_sign", "content": "Is a Scorpio.", "confidence": 0.9},
            {"memory_type": "dislike", "content": "Dislikes skinny jeans.", "confidence": 0.9}
          ],
          "confidence": 0.7
        }
        """)
        #expect(response.memoryProposals.count == 1)
        #expect(response.memoryProposals.first?.memoryType == .dislike)
    }

    @Test("A memory proposal with an out-of-range confidence is dropped rather than clamped")
    func dropsMemoryProposalWithOutOfRangeConfidence() throws {
        let response = try decodeResponse("""
        {
          "message": "Noted a preference.",
          "intent": "general",
          "cards": [],
          "suggested_actions": [],
          "memory_proposals": [
            {"memory_type": "preference", "content": "Likes navy.", "confidence": 4.2}
          ],
          "confidence": 0.7
        }
        """)
        #expect(response.memoryProposals.isEmpty)
    }

    /// The deliberately malformed payload P5-TEST-01 asks for: a required
    /// top-level field (`message`) missing entirely. Per `schema.ts`'s
    /// two-tier policy this is NOT a per-entry defect to drop — it's the
    /// response shape itself failing the contract — so it fails the decode
    /// outright rather than degrading, same as the server would refuse it.
    @Test("A malformed top-level payload (missing required message) fails the decode outright")
    func throwsOnMalformedTopLevelPayload() throws {
        let json = """
        {
          "intent": "general",
          "cards": [],
          "suggested_actions": [],
          "memory_proposals": [],
          "confidence": 0.5
        }
        """
        #expect(throws: (any Error).self) {
            _ = try decoder.decode(KyraStructuredResponse.self, from: Data(json.utf8))
        }
    }

    @Test("A cards field of the wrong top-level shape (not an array) fails the decode outright")
    func throwsWhenCardsIsNotAnArray() throws {
        let json = """
        {
          "message": "Broken payload.",
          "intent": "general",
          "cards": "not-an-array",
          "suggested_actions": [],
          "memory_proposals": [],
          "confidence": 0.5
        }
        """
        #expect(throws: (any Error).self) {
            _ = try decoder.decode(KyraStructuredResponse.self, from: Data(json.utf8))
        }
    }

    @Test("Round-trips through encode -> decode with identical semantic content")
    func roundTrips() throws {
        let original = KyraStructuredResponse(
            message: "Try the navy blazer.",
            intent: .outfitReview,
            cards: [.outfit(outfitID: UUID())],
            suggestedActions: [KyraSuggestedAction(id: "wear", label: "Wear This", kind: .wearOutfit)],
            memoryProposals: [KyraMemoryProposal(memoryType: .preference, content: "Likes navy.", confidence: 0.6)],
            confidence: 0.83
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(KyraStructuredResponse.self, from: data)
        #expect(decoded == original)
    }
}
