//
//  LiveShoppingRepository.swift
//  AstraStyle
//
//  `product_candidates` reads (curated catalog) go through Postgrest; link
//  extraction, evaluation, and Discover Unlocks are orchestration calls
//  (spec §14 `products/extract`, `products/evaluate`, `products/unlocks`)
//  since they invoke `ProductExtractionProvider` and the Wardrobe Graph
//  scorer server-side (spec §8, §10). Discover must not call
//  `fetchCuratedProducts`.
//
//  Wishlist / purchased live on `wishlist_items` (`purchased_at` null
//  means saved). Discover still must not call `fetchCuratedProducts`.
//

import Foundation
import Supabase

public final class LiveShoppingRepository: ShoppingRepository, @unchecked Sendable {
    private let apiClient: AstraAPIClient
    private let supabase: SupabaseClient

    public init(apiClient: AstraAPIClient, supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)) {
        self.apiClient = apiClient
        self.supabase = supabase
    }

    public func extractProduct(from url: URL) async throws -> ProductCandidate {
        struct Body: Encodable, Sendable {
            let url: URL
        }
        return try await apiClient.send(.extractProduct, body: Body(url: url), as: ProductCandidate.self)
    }

    public func evaluateProduct(candidateID: UUID) async throws -> ProductEvaluation {
        struct Body: Encodable, Sendable {
            let productCandidateID: UUID
            enum CodingKeys: String, CodingKey { case productCandidateID = "product_candidate_id" }
        }
        return try await apiClient.send(.evaluateProduct, body: Body(productCandidateID: candidateID), as: ProductEvaluation.self)
    }

    public func fetchProductCandidate(id: UUID) async throws -> ProductCandidate {
        do {
            return try await supabase.from("product_candidates")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't load that product.")
        }
    }

    public func fetchCuratedProducts(category: ClothingCategory?) async throws -> [ProductCandidate] {
        do {
            var query = supabase.from("product_candidates").select()
            if let category {
                query = query.eq("category", value: category.rawValue)
            }
            return try await query.order("last_checked_at", ascending: false).execute().value
        } catch {
            throw AstraError.network("Couldn't load recommendations right now.")
        }
    }

    public func fetchUnlocks() async throws -> [ProductUnlock] {
        do {
            let list = try await apiClient.send(.listProductUnlocks, as: ProductUnlockList.self)
            return list.items
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.network("Couldn't load what you've already asked about.")
        }
    }

    public func fetchWishlist() async throws -> [ProductCandidate] {
        try await fetchWishlistRows(purchased: false)
    }

    public func fetchPurchased() async throws -> [ProductCandidate] {
        try await fetchWishlistRows(purchased: true)
    }

    public func fetchEvaluations(from: Date, to: Date) async throws -> [ProductEvaluation] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        do {
            return try await supabase.from("user_product_evaluations")
                .select()
                .gte("created_at", value: formatter.string(from: from))
                .lte("created_at", value: formatter.string(from: to))
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            throw AstraError.network("Couldn't load your shopping evaluations.")
        }
    }

    public func fetchPurchases(from: Date, to: Date) async throws -> [ProductPurchase] {
        guard from < to else { throw AstraError.validation("That purchase period is invalid.") }
        struct Row: Decodable, Sendable {
            let productCandidateID: UUID
            let purchasedAt: Date
            enum CodingKeys: String, CodingKey {
                case productCandidateID = "product_candidate_id"
                case purchasedAt = "purchased_at"
            }
        }
        let owner = try await shoppingUserID()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lowerBound = formatter.string(from: from)
        let upperBound = formatter.string(from: to)
        do {
            let purchases = try await Self.collectPurchasePages { offset, limit in
                let rows: [Row] = try await supabase.from("wishlist_items")
                    .select("product_candidate_id, purchased_at")
                    .eq("user_id", value: owner)
                    .gte("purchased_at", value: lowerBound)
                    .lt("purchased_at", value: upperBound)
                    // Candidate ID breaks timestamp ties, giving offset
                    // pagination a deterministic order across pages.
                    .order("purchased_at", ascending: false)
                    .order("product_candidate_id", ascending: true)
                    .range(from: offset, to: offset + limit - 1)
                    .execute()
                    .value
                return rows.map { ProductPurchase(productCandidateID: $0.productCandidateID, purchasedAt: $0.purchasedAt) }
            }
            try await verifyActiveShoppingOwner(owner)
            return purchases
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.network("Couldn't load purchases for this month.")
        }
    }

    /// Collects every stable page. Exposed internally so pagination can be
    /// tested without a live Supabase session or database.
    static func collectPurchasePages(
        pageSize: Int = 500,
        fetchPage: @Sendable (Int, Int) async throws -> [ProductPurchase]
    ) async throws -> [ProductPurchase] {
        guard pageSize > 0 else { throw AstraError.validation("That purchase page is invalid.") }
        var purchases: [ProductPurchase] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try await fetchPage(offset, pageSize)
            purchases.append(contentsOf: page)
            if page.count < pageSize { return purchases }
            offset += page.count
        }
    }

    public func fetchLatestEvaluations(candidateIDs: Set<UUID>) async throws -> [ProductEvaluation] {
        guard !candidateIDs.isEmpty else { return [] }
        let owner = try await shoppingUserID()
        let candidateChunks = candidateIDs.sorted { $0.uuidString < $1.uuidString }.chunked(into: 100)
        var latestByCandidate: [UUID: ProductEvaluation] = [:]
        do {
            for candidateChunk in candidateChunks {
                var offset = 0
                while true {
                    try Task.checkCancellation()
                    let rows: [ProductEvaluation] = try await supabase.from("user_product_evaluations")
                        .select()
                        .eq("user_id", value: owner)
                        .in("product_candidate_id", values: candidateChunk)
                        .order("created_at", ascending: false)
                        .order("id", ascending: false)
                        .range(from: offset, to: offset + 499)
                        .execute()
                        .value
                    for evaluation in rows where latestByCandidate[evaluation.productCandidateID] == nil {
                        latestByCandidate[evaluation.productCandidateID] = evaluation
                    }
                    if rows.count < 500 { break }
                    offset += rows.count
                }
            }
            try await verifyActiveShoppingOwner(owner)
            return latestByCandidate.values.sorted { $0.productCandidateID.uuidString < $1.productCandidateID.uuidString }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.network("Couldn't load the latest shopping evaluations.")
        }
    }

    public func addToWishlist(candidateID: UUID) async throws {
        guard let userID = try? await supabase.auth.session.user.id else {
            throw AstraError.auth("Sign in to save items.")
        }
        do {
            try await supabase.from("wishlist_items")
                .upsert(
                    WishlistWrite(
                        userID: userID,
                        productCandidateID: candidateID,
                        purchasedAt: nil
                    ),
                    onConflict: "user_id,product_candidate_id"
                )
                .execute()
        } catch {
            throw AstraError.server("Couldn't save that item.")
        }
    }

    public func removeFromWishlist(candidateID: UUID) async throws {
        do {
            try await supabase.from("wishlist_items")
                .delete()
                .eq("product_candidate_id", value: candidateID)
                .is("purchased_at", value: nil)
                .execute()
        } catch {
            throw AstraError.server("Couldn't remove that save.")
        }
    }

    public func markPurchased(candidateID: UUID) async throws {
        guard let userID = try? await supabase.auth.session.user.id else {
            throw AstraError.auth("Sign in to mark an item purchased.")
        }
        do {
            try await supabase.from("wishlist_items")
                .upsert(
                    WishlistWrite(
                        userID: userID,
                        productCandidateID: candidateID,
                        purchasedAt: Date()
                    ),
                    onConflict: "user_id,product_candidate_id"
                )
                .execute()
        } catch {
            throw AstraError.server("Couldn't mark that as purchased.")
        }
    }

    private func fetchWishlistRows(purchased: Bool) async throws -> [ProductCandidate] {
        struct Row: Decodable, Sendable {
            let productCandidateID: UUID
            let purchasedAt: Date?
            enum CodingKeys: String, CodingKey {
                case productCandidateID = "product_candidate_id"
                case purchasedAt = "purchased_at"
            }
        }
        do {
            let rows: [Row] = try await supabase.from("wishlist_items")
                .select("product_candidate_id, purchased_at")
                .execute()
                .value
            let ids = rows
                .filter { purchased ? $0.purchasedAt != nil : $0.purchasedAt == nil }
                .map(\.productCandidateID)
            guard !ids.isEmpty else { return [] }
            return try await supabase.from("product_candidates")
                .select()
                .in("id", values: ids)
                .execute()
                .value
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.network(
                purchased
                    ? "Couldn't load purchased items."
                    : "Couldn't load your saved items."
            )
        }
    }

    private func shoppingUserID() async throws -> UUID {
        do { return try await supabase.auth.session.user.id } catch {
            throw AstraError.auth("Sign in again to load your shopping history.")
        }
    }

    private func verifyActiveShoppingOwner(_ expectedOwnerID: UUID) async throws {
        guard try await shoppingUserID() == expectedOwnerID else {
            throw AstraError.auth("Your account changed while loading shopping history.")
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}

private struct WishlistWrite: Encodable, Sendable {
    let userID: UUID
    let productCandidateID: UUID
    let purchasedAt: Date?
    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case productCandidateID = "product_candidate_id"
        case purchasedAt = "purchased_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(productCandidateID, forKey: .productCandidateID)
        try container.encode(purchasedAt, forKey: .purchasedAt)
    }
}
