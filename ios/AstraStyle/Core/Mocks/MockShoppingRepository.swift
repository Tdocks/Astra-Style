//
//  MockShoppingRepository.swift
//  AstraStyle
//
//  In-memory `ShoppingRepository` for previews/tests, seeded with a
//  believable curated catalog (spec §31).
//

import Foundation

public actor MockShoppingRepository: ShoppingRepository {
    private var catalog: [ProductCandidate]
    private var unlocks: [ProductUnlock]
    private var wishlist: Set<UUID> = []
    private var purchased: Set<UUID> = []
    private var purchaseDates: [UUID: Date] = [:]
    private var evaluationOverride: ProductEvaluation?
    private var evaluations: [ProductEvaluation] = []
    private var extractError: AstraError?
    private var extractionPause: CheckedContinuation<Void, Never>?
    private var shouldPauseExtraction = false
    public private(set) var extractionCalls = 0
    private var evaluateError: AstraError?
    public private(set) var evaluationCalls = 0
    private var purchaseHistoryError: AstraError?
    private var evaluationHistoryError: AstraError?
    private var wishlistError: AstraError?
    private var purchasedError: AstraError?

    public init(shopTheLookCandidateFixture: Bool = false) {
        catalog = [
            ProductCandidate(
                id: UUID(),
                canonicalURL: URL(string: "https://www.toddsnyder.com/products/italian-shearling-jacket") ?? URL(fileURLWithPath: "/"),
                retailer: "Todd Snyder",
                brand: "Todd Snyder",
                name: "Italian Shearling Jacket",
                category: .outerwear,
                price: 998,
                currency: "USD",
                affiliateURL: URL(string: "https://www.toddsnyder.com/products/italian-shearling-jacket?ref=astra") ?? URL(fileURLWithPath: "/"),
                lastCheckedAt: .now
            ),
            ProductCandidate(
                id: UUID(),
                canonicalURL: URL(string: "https://www.drakes.com/products/handrolled-silk-tie") ?? URL(fileURLWithPath: "/"),
                retailer: "Drake's",
                brand: "Drake's",
                name: "Handrolled Silk Grenadine Tie",
                category: .accessory,
                price: 195,
                currency: "USD",
                lastCheckedAt: .now
            ),
            ProductCandidate(
                id: UUID(),
                canonicalURL: URL(string: "https://www.alden-madison.com/products/indy-boot") ?? URL(fileURLWithPath: "/"),
                retailer: "Alden",
                brand: "Alden",
                name: "Indy Boot, Brown Chromexcel",
                category: .shoes,
                price: 668,
                currency: "USD",
                lastCheckedAt: .now
            )
        ]
        if shopTheLookCandidateFixture {
            catalog.append(ShopTheLookUITestFixture.candidate)
        }
        unlocks = zip(catalog, [9, 4, 1]).map { candidate, count in
            ProductUnlock(candidate: candidate, outfitsUnlocked: count)
        }
    }

    public func seedUnlocks(_ items: [ProductUnlock]) {
        unlocks = items
    }

    public func setEvaluationOverride(_ evaluation: ProductEvaluation?) {
        evaluationOverride = evaluation
    }

    public func pauseExtraction() {
        shouldPauseExtraction = true
    }

    public func resumeExtraction() {
        shouldPauseExtraction = false
        extractionPause?.resume()
        extractionPause = nil
    }

    public func setExtractError(_ error: AstraError?) {
        extractError = error
    }

    public func setEvaluateError(_ error: AstraError?) {
        evaluateError = error
    }

    public func setPurchaseHistoryError(_ error: AstraError?) {
        purchaseHistoryError = error
    }

    public func setEvaluationHistoryError(_ error: AstraError?) {
        evaluationHistoryError = error
    }

    public func setWishlistError(_ error: AstraError?) {
        wishlistError = error
    }

    public func setPurchasedError(_ error: AstraError?) {
        purchasedError = error
    }

    public func seedCandidate(_ candidate: ProductCandidate) {
        if !catalog.contains(where: { $0.id == candidate.id }) { catalog.append(candidate) }
    }

    public func seedPurchase(candidateID: UUID, purchasedAt: Date) {
        purchased.insert(candidateID)
        wishlist.remove(candidateID)
        purchaseDates[candidateID] = purchasedAt
    }

    public func seedEvaluation(_ evaluation: ProductEvaluation) {
        evaluations.append(evaluation)
    }

    public func extractProduct(from url: URL) async throws -> ProductCandidate {
        extractionCalls += 1
        if shouldPauseExtraction {
            await withCheckedContinuation { extractionPause = $0 }
        }
        if let extractError { throw extractError }
        if let existing = catalog.first(where: { $0.canonicalURL == url }) {
            return existing
        }
        let candidate = ProductCandidate(id: UUID(), canonicalURL: url, retailer: url.host ?? "Retailer", name: "Imported Product", category: .top, lastCheckedAt: .now)
        catalog.append(candidate)
        return candidate
    }

    public func evaluateProduct(candidateID: UUID) async throws -> ProductEvaluation {
        evaluationCalls += 1
        if let evaluateError { throw evaluateError }
        if let evaluationOverride {
            let result = ProductEvaluation(
                userID: evaluationOverride.userID,
                productCandidateID: candidateID,
                compatibilityScore: evaluationOverride.compatibilityScore,
                redundancyScore: evaluationOverride.redundancyScore,
                outfitsUnlocked: evaluationOverride.outfitsUnlocked,
                expectedCostPerWear: evaluationOverride.expectedCostPerWear,
                verdict: evaluationOverride.verdict,
                reasoning: evaluationOverride.reasoning,
                createdAt: evaluationOverride.createdAt,
                alternatives: evaluationOverride.alternatives
            )
            evaluations.append(result)
            return result
        }
        let result = ProductEvaluation(
            userID: SampleData.userID,
            productCandidateID: candidateID,
            compatibilityScore: 84,
            redundancyScore: 12,
            outfitsUnlocked: 9,
            expectedCostPerWear: 22.50,
            verdict: .consider,
            reasoning: "Strong color match to your existing palette, but you already own two similar outer layers — I'd wait for a sale unless this replaces one of them."
        )
        evaluations.append(result)
        return result
    }

    public func fetchEvaluations(from: Date, to: Date) async throws -> [ProductEvaluation] {
        evaluations.filter { $0.createdAt >= from && $0.createdAt <= to }
    }

    public func fetchRecentDecisions(limit: Int) async throws -> [ProductDecisionSnapshot] {
        guard limit > 0 else { return [] }
        var seen: Set<UUID> = []
        return evaluations.sorted { $0.createdAt > $1.createdAt }.compactMap { evaluation in
            guard seen.insert(evaluation.productCandidateID).inserted,
                  let candidate = catalog.first(where: { $0.id == evaluation.productCandidateID }) else { return nil }
            return ProductDecisionSnapshot(candidate: candidate, evaluation: evaluation)
        }.prefix(limit).map { $0 }
    }

    public func fetchCachedDecision(candidateID: UUID) async throws -> ProductDecisionSnapshot? {
        guard let evaluation = evaluations.last(where: { $0.productCandidateID == candidateID }) else { return nil }
        return ProductDecisionSnapshot(
            candidate: catalog.first(where: { $0.id == candidateID }),
            evaluation: evaluation
        )
    }

    public func fetchPurchases(from: Date, to: Date) async throws -> [ProductPurchase] {
        if let purchaseHistoryError { throw purchaseHistoryError }
        guard from < to else { throw AstraError.validation("That purchase period is invalid.") }
        return purchaseDates.compactMap { candidateID, purchasedAt in
            guard purchasedAt >= from, purchasedAt < to else { return nil }
            return ProductPurchase(productCandidateID: candidateID, purchasedAt: purchasedAt)
        }.sorted {
            $0.purchasedAt == $1.purchasedAt
                ? $0.productCandidateID.uuidString < $1.productCandidateID.uuidString
                : $0.purchasedAt > $1.purchasedAt
        }
    }

    public func fetchLatestEvaluations(candidateIDs: Set<UUID>) async throws -> [ProductEvaluation] {
        try latestEvaluations(candidateIDs: candidateIDs, before: nil)
    }

    public func fetchLatestEvaluations(candidateIDs: Set<UUID>, before: Date) async throws -> [ProductEvaluation] {
        try latestEvaluations(candidateIDs: candidateIDs, before: before)
    }

    private func latestEvaluations(candidateIDs: Set<UUID>, before: Date?) throws -> [ProductEvaluation] {
        if let evaluationHistoryError { throw evaluationHistoryError }
        let matching = evaluations.enumerated()
            .filter { entry in
                candidateIDs.contains(entry.element.productCandidateID)
                    && (before.map { cutoff in entry.element.createdAt < cutoff } ?? true)
            }
            .sorted {
                if $0.element.createdAt != $1.element.createdAt { return $0.element.createdAt > $1.element.createdAt }
                return $0.offset > $1.offset
            }
        var seen: Set<UUID> = []
        return matching.compactMap { _, evaluation in
            guard seen.insert(evaluation.productCandidateID).inserted else { return nil }
            return evaluation
        }
    }

    public func fetchProductCandidate(id: UUID) async throws -> ProductCandidate {
        guard let candidate = catalog.first(where: { $0.id == id }) else {
            throw AstraError.server("Couldn't load that product.")
        }
        return candidate
    }

    public func fetchCuratedProducts(category: ClothingCategory?) async throws -> [ProductCandidate] {
        guard let category else { return catalog }
        return catalog.filter { $0.category == category }
    }

    public func fetchUnlocks() async throws -> [ProductUnlock] {
        unlocks
    }

    public func fetchWishlist() async throws -> [ProductCandidate] {
        if let wishlistError { throw wishlistError }
        return catalog.filter { wishlist.contains($0.id) && !purchased.contains($0.id) }
    }

    public func fetchPurchased() async throws -> [ProductCandidate] {
        if let purchasedError { throw purchasedError }
        return catalog.filter { purchased.contains($0.id) }
    }

    public func addToWishlist(candidateID: UUID) async throws {
        wishlist.insert(candidateID)
    }

    public func removeFromWishlist(candidateID: UUID) async throws {
        wishlist.remove(candidateID)
    }

    public func markPurchased(candidateID: UUID) async throws {
        purchased.insert(candidateID)
        wishlist.remove(candidateID)
        purchaseDates[candidateID] = .now
    }
}
