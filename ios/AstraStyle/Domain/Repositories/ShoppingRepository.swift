//
//  ShoppingRepository.swift
//  AstraStyle
//
//  Owns `product_candidates` / `user_product_evaluations` (spec §9) and the
//  shopping-decision flow (spec §5.5, §6.18, §6.19, §14 `products/extract`
//  + `products/evaluate` + `products/unlocks`). `fetchUnlocks` is Discover's
//  gap rail. `fetchCuratedProducts` remains a raw catalog read for anything
//  that still needs one — Discover must not use it.
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

    /// Products scored against this closet with `outfitsUnlocked > 0`,
    /// ranked by that count. Discover Unlocks. Includes Shop catalog rows
    /// that fill a gap, not a `last_checked_at` dump.
    func fetchUnlocks() async throws -> [ProductUnlock]

    func fetchWishlist() async throws -> [ProductCandidate]
    func fetchPurchased() async throws -> [ProductCandidate]

    /// Product evaluations made during an inclusive date range.
    func fetchEvaluations(from: Date, to: Date) async throws -> [ProductEvaluation]

    /// Recent user-visible product decisions; the live repository is
    /// network-first and may return owner-scoped local snapshots offline.
    func fetchRecentDecisions(limit: Int) async throws -> [ProductDecisionSnapshot]

    /// Reads local history only. It is used to display a last-evaluated
    /// snapshot after a fresh evaluation fails for connectivity reasons.
    func fetchCachedDecision(candidateID: UUID) async throws -> ProductDecisionSnapshot?

    /// Tracked purchase events in the half-open interval `[from, to)`.
    func fetchPurchases(from: Date, to: Date) async throws -> [ProductPurchase]

    /// The most recent evaluation for each requested candidate, regardless
    /// of evaluation date. Used to attribute current decisions to purchases.
    func fetchLatestEvaluations(candidateIDs: Set<UUID>) async throws -> [ProductEvaluation]
    func addToWishlist(candidateID: UUID) async throws
    func removeFromWishlist(candidateID: UUID) async throws

    /// Records a purchase for cost-per-wear tracking once the item is
    /// eventually scanned into the closet (spec §5.5 "mark purchased").
    func markPurchased(candidateID: UUID) async throws
}

public extension ShoppingRepository {
    func fetchEvaluations(from: Date, to: Date) async throws -> [ProductEvaluation] { [] }
    func fetchRecentDecisions(limit: Int) async throws -> [ProductDecisionSnapshot] { [] }
    func fetchCachedDecision(candidateID: UUID) async throws -> ProductDecisionSnapshot? { nil }
    func fetchPurchases(from: Date, to: Date) async throws -> [ProductPurchase] { [] }
    func fetchLatestEvaluations(candidateIDs: Set<UUID>) async throws -> [ProductEvaluation] { [] }
}
