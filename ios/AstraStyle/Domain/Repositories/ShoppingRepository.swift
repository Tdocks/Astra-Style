//
//  ShoppingRepository.swift
//  AstraStyle
//
//  Owns `product_candidates` / `user_product_evaluations` (spec §9) and the
//  shopping-decision flow (spec §5.5, §6.18, §6.19, §14 `products/extract`
//  + `products/evaluate`). Also serves the curated catalog for Discover's
//  "Shop the look" surfaces (spec §17 "Product ingestion").
//

import Foundation

public protocol ShoppingRepository: Sendable {
    /// Analyzes a user-pasted retailer link into a `ProductCandidate`
    /// (spec §5.5 step 1, §14 `products/extract`).
    func extractProduct(from url: URL) async throws -> ProductCandidate

    /// Produces the compatibility/redundancy/verdict breakdown for the
    /// Product Decision Page (spec §6.19, §14 `products/evaluate`).
    func evaluateProduct(candidateID: UUID) async throws -> ProductEvaluation

    /// The candidate row itself — name, the URL he pasted, retailer.
    /// Needed so buy/consider can reopen *that* page, not a catalog.
    func fetchProductCandidate(id: UUID) async throws -> ProductCandidate

    func fetchCuratedProducts(category: ClothingCategory?) async throws -> [ProductCandidate]

    func fetchWishlist() async throws -> [ProductCandidate]
    func addToWishlist(candidateID: UUID) async throws
    func removeFromWishlist(candidateID: UUID) async throws

    /// Records a purchase for cost-per-wear tracking once the item is
    /// eventually scanned into the closet (spec §5.5 "mark purchased").
    func markPurchased(candidateID: UUID) async throws
}
