import Foundation
import Testing
@testable import AstraStyle

@Suite("Product alternatives")
struct ProductAlternativeTests {
    @Test("decodes the server's evaluation alternatives contract")
    func decodesAlternatives() throws {
        let ownerID = UUID()
        let primaryID = UUID()
        let alternativeID = UUID()
        let json = """
        {
          "user_id": "\(ownerID.uuidString)",
          "product_candidate_id": "\(primaryID.uuidString)",
          "compatibility_score": 72,
          "redundancy_score": 18,
          "outfits_unlocked": 2,
          "expected_cost_per_wear": null,
          "verdict": "consider",
          "reasoning": "Fits some of your wardrobe.",
          "created_at": "2026-10-08T12:00:00.000Z",
          "alternatives": [
            {
              "product_candidate_id": "\(alternativeID.uuidString)",
              "name": "Alternative overshirt",
              "price": 85.5,
              "currency": "USD",
              "compatibility_score": 81,
              "sponsored": true
            }
          ]
        }
        """

        let evaluation = try JSONDecoder.astraDefault.decode(ProductEvaluation.self, from: Data(json.utf8))
        let alternative = try #require(evaluation.alternatives.first)
        #expect(alternative.productCandidateID == alternativeID)
        #expect(alternative.name == "Alternative overshirt")
        #expect(alternative.price == Decimal(string: "85.5"))
        #expect(alternative.currency == "USD")
        #expect(alternative.compatibilityScore == 81)
        #expect(alternative.sponsored)
    }

    @Test("legacy evaluation snapshots without alternatives remain readable")
    func decodesLegacyEvaluation() throws {
        let json = """
        {
          "user_id": "00000000-0000-4000-8000-000000000001",
          "product_candidate_id": "00000000-0000-4000-8000-000000000002",
          "compatibility_score": 72,
          "redundancy_score": 18,
          "outfits_unlocked": 2,
          "expected_cost_per_wear": null,
          "verdict": "consider",
          "reasoning": "Fits some of your wardrobe.",
          "created_at": "2026-10-08T12:00:00.000Z"
        }
        """

        let evaluation = try JSONDecoder.astraDefault.decode(ProductEvaluation.self, from: Data(json.utf8))
        #expect(evaluation.alternatives.isEmpty)
    }

    @Test("price comparison requires known matching currencies")
    func comparesPriceOnlyWithSameCurrency() {
        let alternative = ProductAlternative(
            productCandidateID: UUID(),
            name: "Alternative",
            price: Decimal(80),
            currency: "USD",
            compatibilityScore: 84,
            sponsored: false
        )

        #expect(ProductAlternativeComparison.isLowerPriced(
            alternative,
            primaryPrice: Decimal(100),
            primaryCurrency: "USD"
        ))
        #expect(!ProductAlternativeComparison.isLowerPriced(
            alternative,
            primaryPrice: Decimal(100),
            primaryCurrency: "CAD"
        ))
        #expect(!ProductAlternativeComparison.isLowerPriced(
            alternative,
            primaryPrice: nil,
            primaryCurrency: "USD"
        ))
        #expect(ProductAlternativeComparison.isStrongerWardrobeMatch(alternative, primaryScore: 72))
        #expect(!ProductAlternativeComparison.isStrongerWardrobeMatch(alternative, primaryScore: 84))
    }

    @Test("Product Decision retains server alternatives for the review route")
    @MainActor
    func decisionLoadsAlternatives() async throws {
        let shopping = MockShoppingRepository()
        let primary = try await shopping.extractProduct(
            from: try #require(URL(string: "https://example.com/primary-overshirt"))
        )
        let alternative = ProductAlternative(
            productCandidateID: UUID(),
            name: "Lower price overshirt",
            price: Decimal(80),
            currency: "USD",
            compatibilityScore: 90,
            sponsored: false
        )
        await shopping.setEvaluationOverride(ProductEvaluation(
            userID: SampleData.userID,
            productCandidateID: primary.id,
            compatibilityScore: 72,
            redundancyScore: 18,
            outfitsUnlocked: 2,
            verdict: .consider,
            reasoning: "Fits some of your wardrobe.",
            alternatives: [alternative]
        ))

        let model = ProductDecisionViewModel(candidateID: primary.id, shoppingRepository: shopping)
        await model.onAppear()

        guard case .loaded(let loaded) = model.state else {
            Issue.record("Expected a loaded decision")
            return
        }
        #expect(loaded.evaluation.alternatives == [alternative])
    }
}
