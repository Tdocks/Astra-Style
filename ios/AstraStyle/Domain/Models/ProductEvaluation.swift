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

    public init(
        userID: UUID,
        productCandidateID: UUID,
        compatibilityScore: Int,
        redundancyScore: Int,
        outfitsUnlocked: Int,
        expectedCostPerWear: Decimal? = nil,
        verdict: KyraVerdict,
        reasoning: String,
        createdAt: Date = .now
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
    }
}
