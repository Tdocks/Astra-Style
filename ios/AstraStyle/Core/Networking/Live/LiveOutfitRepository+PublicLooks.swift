//
//  LiveOutfitRepository+PublicLooks.swift
//  AstraStyle
//
//  Batched outfit-item reads and the sanitized peer-look Data API call.
//

import Foundation
import Supabase

extension LiveOutfitRepository {
    public func fetchPublicWornLooks() async throws -> [PublicWornLook] {
        try await fetchPublicWornLooks(outfitIDs: [])
    }

    public func fetchPublicWornLook(id: UUID) async throws -> PublicWornLook {
        let looks = try await fetchPublicWornLooks(outfitIDs: [id])
        guard let look = looks.first else {
            throw AstraError.server("That public look is no longer available.")
        }
        return look
    }

    private func fetchPublicWornLooks(outfitIDs: [UUID]) async throws -> [PublicWornLook] {
        struct Params: Encodable, Sendable {
            let outfitIDs: [UUID]
            enum CodingKeys: String, CodingKey {
                case outfitIDs = "p_outfit_ids"
            }
        }
        do {
            return try await supabase
                .rpc("fetch_public_worn_looks", params: Params(outfitIDs: outfitIDs))
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't load those public looks.")
        }
    }

    public func fetchOutfitItems(outfitIDs: [UUID]) async throws -> [OutfitItem] {
        guard !outfitIDs.isEmpty else { return [] }
        do {
            let items: [OutfitItem]
            if let activeOutfitItemsFetcher {
                var collected: [OutfitItem] = []
                for outfitID in outfitIDs {
                    collected.append(contentsOf: try await activeOutfitItemsFetcher(outfitID))
                }
                items = collected
            } else {
                items = try await supabase.from("outfit_items")
                    .select()
                    .in("outfit_id", values: outfitIDs)
                    .order("sort_order", ascending: true)
                    .execute()
                    .value
            }
            let grouped = Dictionary(grouping: items, by: \.outfitID)
            for outfitID in outfitIDs {
                await cache.upsertItems(grouped[outfitID] ?? [], forOutfit: outfitID)
            }
            return items
        } catch {
            var cachedItems: [OutfitItem] = []
            for outfitID in outfitIDs {
                cachedItems.append(contentsOf: await cache.items(forOutfit: outfitID))
            }
            if !cachedItems.isEmpty { return cachedItems }
            throw AstraError.server("Couldn't load those outfits' items.")
        }
    }

    public func fetchPublicLookGarments(outfitIDs: [UUID]) async throws -> [PublicLookGarment] {
        guard !outfitIDs.isEmpty else { return [] }
        struct Params: Encodable, Sendable {
            let outfitIDs: [UUID]
            enum CodingKeys: String, CodingKey {
                case outfitIDs = "p_outfit_ids"
            }
        }
        do {
            return try await supabase
                .rpc("fetch_public_look_garments", params: Params(outfitIDs: outfitIDs))
                .execute()
                .value
        } catch {
            throw AstraError.server("Couldn't load the garments for those public looks.")
        }
    }
}
