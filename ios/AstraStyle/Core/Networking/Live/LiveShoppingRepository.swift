//
//  LiveShoppingRepository.swift
//  AstraStyle
//
//  `product_candidates` reads (curated catalog, wishlist) go through
//  Postgrest; link extraction and evaluation are orchestration calls
//  (spec §14 `products/extract`, `products/evaluate`) since they invoke
//  `ProductExtractionProvider` and the Wardrobe Graph compatibility scorer
//  server-side (spec §8, §10).
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

    public func fetchWishlist() async throws -> [ProductCandidate] {
        do {
            return try await supabase.from("wishlist_items")
                .select("*, product_candidates(*)")
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't load your wishlist.")
        }
    }

    public func addToWishlist(candidateID: UUID) async throws {
        do {
            let session = try await supabase.auth.session
            try await supabase.from("wishlist_items")
                .insert(["user_id": session.user.id.uuidString, "product_candidate_id": candidateID.uuidString])
                .execute()
        } catch {
            throw AstraError.network("Couldn't add that to your wishlist while offline.")
        }
    }

    public func removeFromWishlist(candidateID: UUID) async throws {
        do {
            try await supabase.from("wishlist_items")
                .delete()
                .eq("product_candidate_id", value: candidateID)
                .execute()
        } catch {
            throw AstraError.network("Couldn't remove that from your wishlist while offline.")
        }
    }

    public func markPurchased(candidateID: UUID) async throws {
        do {
            try await supabase.from("wishlist_items")
                .update(["purchased_at": Date.now])
                .eq("product_candidate_id", value: candidateID)
                .execute()
        } catch {
            throw AstraError.network("Couldn't update that purchase while offline.")
        }
    }
}
