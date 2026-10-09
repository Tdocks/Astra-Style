//
//  ProductEvaluation.swift
//  AstraStyle
//
//  Maps `user_product_evaluations` (spec §9). The output of
//  `POST /products/evaluate` (spec §14) and the data source for the Product
//  Decision Page (spec §6.19).
//

import Foundation

public struct ProductEvaluation: Codable, Hashable, Sendable {
    public var userID: UUID
    public var productCandidateID: UUID
    public var compatibilityScore: Int
    public var redundancyScore: Int
    public var outfitsUnlocked: Int
    public var expectedCostPerWear: Decimal?
    public var verdict: KyraVerdict
    public var reasoning: String
    public var createdAt: Date
    /// Same-category alternatives scored by the server in the same request.
    /// Missing on historical database rows predating this API payload.
    public var alternatives: [ProductAlternative]

    public init(
        userID: UUID,
        productCandidateID: UUID,
        compatibilityScore: Int,
        redundancyScore: Int,
        outfitsUnlocked: Int,
        expectedCostPerWear: Decimal? = nil,
        verdict: KyraVerdict,
        reasoning: String,
        createdAt: Date = .now,
        alternatives: [ProductAlternative] = []
    ) {
        self.userID = userID
        self.productCandidateID = productCandidateID
        self.compatibilityScore = compatibilityScore
        self.redundancyScore = redundancyScore
        self.outfitsUnlocked = outfitsUnlocked
        self.expectedCostPerWear = expectedCostPerWear
        self.verdict = verdict
        self.reasoning = reasoning
        self.createdAt = createdAt
        self.alternatives = alternatives
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        productCandidateID = try container.decode(UUID.self, forKey: .productCandidateID)
        compatibilityScore = try container.decode(Int.self, forKey: .compatibilityScore)
        redundancyScore = try container.decode(Int.self, forKey: .redundancyScore)
        outfitsUnlocked = try container.decode(Int.self, forKey: .outfitsUnlocked)
        expectedCostPerWear = try container.decodeIfPresent(Decimal.self, forKey: .expectedCostPerWear)
        verdict = try container.decode(KyraVerdict.self, forKey: .verdict)
        reasoning = try container.decode(String.self, forKey: .reasoning)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        alternatives = try container.decodeIfPresent([ProductAlternative].self, forKey: .alternatives) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case productCandidateID = "product_candidate_id"
        case compatibilityScore = "compatibility_score"
        case redundancyScore = "redundancy_score"
        case outfitsUnlocked = "outfits_unlocked"
        case expectedCostPerWear = "expected_cost_per_wear"
        case verdict
        case reasoning
        case createdAt = "created_at"
        case alternatives
    }
}

/// The intentionally compact alternatives contract returned by
/// `POST /products/evaluate`. Full retailer/affiliate/availability detail is
/// loaded only after the user opens this candidate's Product Decision page.
public struct ProductAlternative: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID { productCandidateID }
    public let productCandidateID: UUID
    public let name: String
    public let price: Decimal?
    public let currency: String?
    public let compatibilityScore: Int
    public let sponsored: Bool

    public init(
        productCandidateID: UUID,
        name: String,
        price: Decimal? = nil,
        currency: String? = nil,
        compatibilityScore: Int,
        sponsored: Bool
    ) {
        self.productCandidateID = productCandidateID
        self.name = name
        self.price = price
        self.currency = currency
        self.compatibilityScore = compatibilityScore
        self.sponsored = sponsored
    }

    enum CodingKeys: String, CodingKey {
        case productCandidateID = "product_candidate_id"
        case name
        case price
        case currency
        case compatibilityScore = "compatibility_score"
        case sponsored
    }
}

enum ProductAlternativeComparison {
    static func isLowerPriced(
        _ alternative: ProductAlternative,
        primaryPrice: Decimal?,
        primaryCurrency: String?
    ) -> Bool {
        guard let price = alternative.price,
              let primaryPrice,
              let currency = alternative.currency,
              currency == primaryCurrency else { return false }
        return price < primaryPrice
    }

    static func isStrongerWardrobeMatch(_ alternative: ProductAlternative, primaryScore: Int) -> Bool {
        alternative.compatibilityScore > primaryScore
    }
}
