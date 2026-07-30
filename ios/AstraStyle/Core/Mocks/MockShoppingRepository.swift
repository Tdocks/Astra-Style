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
    private var wishlist: Set<UUID> = []
    private var purchased: Set<UUID> = []

    public init() {
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
    }

    public func extractProduct(from url: URL) async throws -> ProductCandidate {
        if let existing = catalog.first(where: { $0.canonicalURL == url }) {
            return existing
        }
        let candidate = ProductCandidate(id: UUID(), canonicalURL: url, retailer: url.host ?? "Retailer", name: "Imported Product", category: .top, lastCheckedAt: .now)
        catalog.append(candidate)
        return candidate
    }

    public func evaluateProduct(candidateID: UUID) async throws -> ProductEvaluation {
        ProductEvaluation(
            userID: SampleData.userID,
            productCandidateID: candidateID,
            compatibilityScore: 84,
            redundancyScore: 12,
            outfitsUnlocked: 9,
            expectedCostPerWear: 22.50,
            verdict: .consider,
            reasoning: "Strong color match to your existing palette, but you already own two similar outer layers — I'd wait for a sale unless this replaces one of them."
        )
    }

    public func fetchCuratedProducts(category: ClothingCategory?) async throws -> [ProductCandidate] {
        guard let category else { return catalog }
        return catalog.filter { $0.category == category }
    }

    public func fetchWishlist() async throws -> [ProductCandidate] {
        catalog.filter { wishlist.contains($0.id) }
    }

    public func addToWishlist(candidateID: UUID) async throws {
        wishlist.insert(candidateID)
    }

    public func removeFromWishlist(candidateID: UUID) async throws {
        wishlist.remove(candidateID)
    }

    public func markPurchased(candidateID: UUID) async throws {
        purchased.insert(candidateID)
    }
}
