//
//  LiveShoppingRepository.swift
//  AstraStyle
//
//  `product_candidates` reads (curated catalog) go through Postgrest; link
//  extraction and evaluation are orchestration calls (spec §14
//  `products/extract`, `products/evaluate`) since they invoke
//  `ProductExtractionProvider` and the Wardrobe Graph compatibility scorer
//  server-side (spec §8, §10).
//
//  THE FOUR WISHLIST METHODS ARE NOT IMPLEMENTED. They previously issued
//  Postgrest calls against a `wishlist_items` table that no migration in
//  supabase/migrations creates, so every one of them failed at runtime with a
//  PGREST relation-does-not-exist error dressed up as "Couldn't load your
//  wishlist." — a network-shaped message for a schema-shaped fact.
//
//  Why not just write the migration? Because the table is not the missing
//  piece. Wishlist is Phase 6 (P6-SHOP-05/07/10); there is no wishlist UI, no
//  decision page, and no `SFSafariViewController` anywhere, so a table added
//  now would ship untested and unused, and would freeze a schema shape ahead
//  of the feature that has to live with it — while the repository kept
//  claiming, to any reader of the protocol, that wishlist already worked.
//  Throwing `.unimplemented` is the smaller lie to unwind later: it costs one
//  migration plus these four bodies when Phase 6 starts, and until then the
//  code says exactly what is true.
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

    // MARK: - Wishlist (not implemented — see this file's header)

    /// - Note: Requires a `wishlist_items` table. No migration creates one.
    ///   Implement alongside P6-SHOP-05/07/10, not before.
    public func fetchWishlist() async throws -> [ProductCandidate] {
        throw AstraError.unimplemented(Self.wishlistUnavailableMessage)
    }

    /// - Note: See `fetchWishlist()`.
    public func addToWishlist(candidateID: UUID) async throws {
        throw AstraError.unimplemented(Self.wishlistUnavailableMessage)
    }

    /// - Note: See `fetchWishlist()`.
    public func removeFromWishlist(candidateID: UUID) async throws {
        throw AstraError.unimplemented(Self.wishlistUnavailableMessage)
    }

    /// - Note: See `fetchWishlist()`. Marking a purchase is part of the same
    ///   unbuilt table, not a separate gap.
    public func markPurchased(candidateID: UUID) async throws {
        throw AstraError.unimplemented(Self.wishlistUnavailableMessage)
    }

    /// One message for all four, so the wishlist never explains itself two
    /// different ways depending on which control the user touched.
    private static let wishlistUnavailableMessage = String(
        localized: "Saving items to a wishlist isn't available yet."
    )
}
