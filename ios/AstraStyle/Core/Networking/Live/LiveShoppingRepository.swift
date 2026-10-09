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
    struct WishlistRow: Decodable, Sendable, Equatable {
        let id: UUID
        let productCandidateID: UUID
        let purchasedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case productCandidateID = "product_candidate_id"
            case purchasedAt = "purchased_at"
        }
    }

    private static let wishlistPageSize = 500
    private static let productCandidatePageSize = 100

    private let apiClient: AstraAPIClient
    private let supabase: SupabaseClient
    private let evaluationCache: ShoppingEvaluationCaching?

    public init(
        apiClient: AstraAPIClient,
        evaluationCache: ShoppingEvaluationCaching? = nil,
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)
    ) {
        self.apiClient = apiClient
        self.evaluationCache = evaluationCache
        self.supabase = supabase
    }

    public func extractProduct(from url: URL) async throws -> ProductCandidate {
        struct Body: Encodable, Sendable {
            let url: URL
        }
        let ownerID = try await shoppingUserID()
        let candidate = try await apiClient.send(.extractProduct, body: Body(url: url), as: ProductCandidate.self)
        try await verifyActiveShoppingOwner(ownerID)
        try? await evaluationCache?.store(candidate: candidate, ownerID: ownerID)
        try await verifyActiveShoppingOwner(ownerID)
        return candidate
    }

    public func evaluateProduct(candidateID: UUID) async throws -> ProductEvaluation {
        struct Body: Encodable, Sendable {
            let productCandidateID: UUID
            enum CodingKeys: String, CodingKey { case productCandidateID = "product_candidate_id" }
        }
        let ownerID = try await shoppingUserID()
        let evaluation = try await apiClient.send(.evaluateProduct, body: Body(productCandidateID: candidateID), as: ProductEvaluation.self)
        guard evaluation.userID == ownerID else {
            throw AstraError.auth("That evaluation belongs to another account.")
        }
        try await verifyActiveShoppingOwner(ownerID)
        let candidate = try await cachedCandidate(candidateID: candidateID, ownerID: ownerID)
        try? await evaluationCache?.store(evaluation: evaluation, candidate: candidate, ownerID: ownerID)
        try await verifyActiveShoppingOwner(ownerID)
        return evaluation
    }

    public func fetchProductCandidate(id: UUID) async throws -> ProductCandidate {
        let ownerID = try await shoppingUserID()
        do {
            let candidate: ProductCandidate = try await supabase.from("product_candidates")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
            try? await evaluationCache?.store(candidate: candidate, ownerID: ownerID)
            try await verifyActiveShoppingOwner(ownerID)
            return candidate
        } catch {
            if Self.isConnectivityFailure(error),
               let candidate = try await cachedCandidate(candidateID: id, ownerID: ownerID) {
                try await verifyActiveShoppingOwner(ownerID)
                return candidate
            }
            if let error = error as? AstraError { throw error }
            throw Self.isConnectivityFailure(error)
                ? AstraError.network("Couldn't load that product.")
                : AstraError.server("Couldn't load that product.")
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
        let ownerID = try await shoppingUserID()
        do {
            let list = try await apiClient.send(.listProductUnlocks, as: ProductUnlockList.self)
            try await verifyActiveShoppingOwner(ownerID)
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
        guard from <= to else { throw AstraError.validation("That evaluation period is invalid.") }
        let ownerID = try await shoppingUserID()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        do {
            let rows: [ProductEvaluation] = try await supabase.from("user_product_evaluations")
                .select()
                .eq("user_id", value: ownerID)
                .gte("created_at", value: formatter.string(from: from))
                .lte("created_at", value: formatter.string(from: to))
                .order("created_at", ascending: false)
                .order("product_candidate_id", ascending: true)
                .range(from: 0, to: 999)
                .execute()
                .value
            guard rows.allSatisfy({ $0.userID == ownerID }) else {
                throw AstraError.auth("A shopping evaluation belongs to another account.")
            }
            for evaluation in rows {
                try? await evaluationCache?.store(evaluation: evaluation, candidate: nil, ownerID: ownerID)
            }
            try await verifyActiveShoppingOwner(ownerID)
            return rows
        } catch {
            if Self.isConnectivityFailure(error), let evaluationCache,
               let cached = try? await evaluationCache.cachedEvaluations(from: from, to: to, ownerID: ownerID) {
                try await verifyActiveShoppingOwner(ownerID)
                return cached
            }
            if let error = error as? AstraError { throw error }
            throw Self.isConnectivityFailure(error)
                ? AstraError.network("Couldn't load your shopping evaluations.")
                : AstraError.server("Couldn't load your shopping evaluations.")
        }
    }

    static func isConnectivityFailure(_ error: Error) -> Bool {
        if let error = error as? AstraError { return error.category == .network }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code != URLError.cancelled.rawValue
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
            try await verifyActiveShoppingOwner(userID)
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.server("Couldn't save that item.")
        }
    }

    public func removeFromWishlist(candidateID: UUID) async throws {
        let ownerID = try await shoppingUserID()
        do {
            try await supabase.from("wishlist_items")
                .delete()
                .eq("user_id", value: ownerID)
                .eq("product_candidate_id", value: candidateID)
                .is("purchased_at", value: nil)
                .execute()
            try await verifyActiveShoppingOwner(ownerID)
        } catch let error as AstraError {
            throw error
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
            try await verifyActiveShoppingOwner(userID)
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.server("Couldn't mark that as purchased.")
        }
    }

    private func shoppingUserID() async throws -> UUID {
        do { return try await supabase.auth.session.user.id } catch {
            throw AstraError.auth("Sign in again to load your shopping history.")
        }
    }

    private func verifyActiveShoppingOwner(_ expectedOwnerID: UUID) async throws {
        try Self.validateActiveOwner(expected: expectedOwnerID, actual: await shoppingUserID())
    }

    static func validateActiveOwner(expected: UUID, actual: UUID) throws {
        guard actual == expected else {
            throw AstraError.auth("Your account changed while loading shopping history.")
        }
    }
}

extension LiveShoppingRepository {
    public func fetchRecentDecisions(limit: Int) async throws -> [ProductDecisionSnapshot] {
        guard limit > 0 else { return [] }
        let ownerID = try await shoppingUserID()
        do {
            let selected = try await fetchRecentEvaluationRows(ownerID: ownerID, limit: limit)
            let candidates = try await fetchCandidates(ids: selected.map(\.productCandidateID), ownerID: ownerID)
            let decisions = selected.map { evaluation in
                ProductDecisionSnapshot(candidate: candidates[evaluation.productCandidateID], evaluation: evaluation)
            }
            for decision in decisions {
                try? await evaluationCache?.store(
                    evaluation: decision.evaluation,
                    candidate: decision.candidate,
                    ownerID: ownerID
                )
            }
            try await verifyActiveShoppingOwner(ownerID)
            return decisions
        } catch {
            if Self.isConnectivityFailure(error), let evaluationCache,
               let cached = try? await evaluationCache.cachedRecentDecisions(ownerID: ownerID, limit: min(limit, 50)) {
                try await verifyActiveShoppingOwner(ownerID)
                return cached
            }
            if let error = error as? AstraError { throw error }
            throw Self.isConnectivityFailure(error)
                ? AstraError.network("Couldn't load your recent product decisions.")
                : AstraError.server("Couldn't load your recent product decisions.")
        }
    }

    private func fetchRecentEvaluationRows(ownerID: UUID, limit: Int) async throws -> [ProductEvaluation] {
        let now = Date()
        let from = now.addingTimeInterval(-180 * 24 * 60 * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let evaluations: [ProductEvaluation] = try await supabase.from("user_product_evaluations")
            .select()
            .eq("user_id", value: ownerID)
            .gte("created_at", value: formatter.string(from: from))
            .lte("created_at", value: formatter.string(from: now))
            .order("created_at", ascending: false)
            .order("product_candidate_id", ascending: true)
            .range(from: 0, to: min(min(limit, 25) * 8, 200) - 1)
            .execute()
            .value
        guard evaluations.allSatisfy({ $0.userID == ownerID }) else {
            throw AstraError.auth("A shopping evaluation belongs to another account.")
        }
        var latestByCandidate: [UUID: ProductEvaluation] = [:]
        for evaluation in evaluations where latestByCandidate[evaluation.productCandidateID] == nil {
            latestByCandidate[evaluation.productCandidateID] = evaluation
        }
        return latestByCandidate.values.sorted { $0.createdAt > $1.createdAt }.prefix(min(limit, 50)).map { $0 }
    }

    private func fetchCandidates(ids: [UUID], ownerID: UUID) async throws -> [UUID: ProductCandidate] {
        var candidatesByID: [UUID: ProductCandidate] = [:]
        for chunk in Self.candidateIDChunks(ids) {
            try Task.checkCancellation()
            let candidates: [ProductCandidate] = try await supabase.from("product_candidates")
                .select()
                .in("id", values: chunk)
                .execute()
                .value
            try Task.checkCancellation()
            try await verifyActiveShoppingOwner(ownerID)
            candidatesByID.merge(candidates.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        }
        return candidatesByID
    }

    /// The same bounded chunks used by wishlist and decision candidate reads.
    /// Kept testable so a large saved list cannot regress to one long `.in` URL.
    static func candidateIDChunks(_ ids: [UUID]) -> [[UUID]] {
        ids.chunked(into: productCandidatePageSize)
    }

    public func fetchCachedDecision(candidateID: UUID) async throws -> ProductDecisionSnapshot? {
        let ownerID = try await shoppingUserID()
        guard let evaluationCache else { return nil }
        do {
            let snapshot = try await evaluationCache.cachedDecision(candidateID: candidateID, ownerID: ownerID)
            try await verifyActiveShoppingOwner(ownerID)
            return snapshot
        } catch {
            throw AstraError.server("Couldn't open that saved product decision.")
        }
    }

    public func fetchLatestEvaluations(candidateIDs: Set<UUID>) async throws -> [ProductEvaluation] {
        try await fetchLatestEvaluations(candidateIDs: candidateIDs, before: nil)
    }

    public func fetchLatestEvaluations(candidateIDs: Set<UUID>, before: Date) async throws -> [ProductEvaluation] {
        try await fetchLatestEvaluations(candidateIDs: candidateIDs, before: Optional(before))
    }

    private func fetchLatestEvaluations(candidateIDs: Set<UUID>, before: Date?) async throws -> [ProductEvaluation] {
        guard !candidateIDs.isEmpty else { return [] }
        let owner = try await shoppingUserID()
        let candidateChunks = candidateIDs.sorted { $0.uuidString < $1.uuidString }.chunked(into: 100)
        var latestByCandidate: [UUID: ProductEvaluation] = [:]
        do {
            for candidateChunk in candidateChunks {
                var offset = 0
                while true {
                    try Task.checkCancellation()
                    var query = supabase.from("user_product_evaluations")
                        .select()
                        .eq("user_id", value: owner)
                        .in("product_candidate_id", values: candidateChunk)
                    if let before { query = query.lt("created_at", value: before) }
                    let rows: [ProductEvaluation] = try await query
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
            let latest = latestByCandidate.values.sorted { $0.productCandidateID.uuidString < $1.productCandidateID.uuidString }
            return latest
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let error = error as? AstraError { throw error }
            throw Self.isConnectivityFailure(error)
                ? AstraError.network("Couldn't load the latest shopping evaluations.")
                : AstraError.server("Couldn't load the latest shopping evaluations.")
        }
    }

    private func fetchWishlistRows(purchased: Bool) async throws -> [ProductCandidate] {
        do {
            let ownerID = try await shoppingUserID()
            let rows = try await Self.collectWishlistPages { offset, limit in
                var query = supabase.from("wishlist_items")
                    .select("id, product_candidate_id, purchased_at")
                    .eq("user_id", value: ownerID)
                if purchased {
                    query = query.not("purchased_at", operator: .is, value: "null")
                } else {
                    query = query.is("purchased_at", value: nil)
                }
                let page: [WishlistRow] = try await query
                    .order("created_at", ascending: false)
                    .order("id", ascending: true)
                    .range(from: offset, to: offset + limit - 1)
                    .execute()
                    .value
                try await verifyActiveShoppingOwner(ownerID)
                return page
            }
            let ids = rows.map(\.productCandidateID)
            guard !ids.isEmpty else {
                try await verifyActiveShoppingOwner(ownerID)
                return []
            }
            let candidatesByID = try await fetchCandidates(ids: ids, ownerID: ownerID)
            try await verifyActiveShoppingOwner(ownerID)
            return ids.compactMap { candidatesByID[$0] }
        } catch is CancellationError {
            throw CancellationError()
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

    /// Collects stable pages from the caller's owner-scoped wishlist query.
    /// Kept separate from PostgREST so row-cap behavior is covered offline.
    static func collectWishlistPages(
        pageSize: Int = wishlistPageSize,
        fetchPage: @Sendable (Int, Int) async throws -> [WishlistRow]
    ) async throws -> [WishlistRow] {
        guard pageSize > 0 else {
            throw AstraError.validation("That saved-item page is invalid.")
        }
        var rows: [WishlistRow] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try await fetchPage(offset, pageSize)
            try Task.checkCancellation()
            rows.append(contentsOf: page)
            if page.count < pageSize { return rows }
            offset += page.count
        }
    }

    private func cachedCandidate(candidateID: UUID, ownerID: UUID) async throws -> ProductCandidate? {
        guard let evaluationCache,
              let snapshot = try? await evaluationCache.cachedDecision(candidateID: candidateID, ownerID: ownerID)
        else { return nil }
        try await verifyActiveShoppingOwner(ownerID)
        return snapshot.candidate
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

extension LiveShoppingRepository: ShoppingEvaluationCachePurging {
    public func purgeCachedShoppingEvaluations(ownerID: UUID) async throws {
        try await evaluationCache?.removeAll(ownerID: ownerID)
    }
}
