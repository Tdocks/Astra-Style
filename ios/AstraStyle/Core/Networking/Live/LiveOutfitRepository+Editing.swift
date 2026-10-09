//
//  LiveOutfitRepository+Editing.swift
//  Draft: identity-preserving atomic outfit edit RPC.
//

import Foundation
import Supabase

struct OutfitItemsReplaceItem: Encodable, Sendable {
    let closetItemID: UUID
    let role: String
    let sortOrder: Int
    enum CodingKeys: String, CodingKey {
        case closetItemID = "closet_item_id"
        case role
        case sortOrder = "sort_order"
    }
}

struct OutfitItemsReplaceParameters: Encodable, Sendable {
    let outfitID: UUID
    let expectedUpdatedAt: Date
    let name: String
    let description: String?
    let compatibilityScore: Int16?
    let items: [OutfitItemsReplaceItem]
    enum CodingKeys: String, CodingKey {
        case outfitID = "p_outfit_id"
        case expectedUpdatedAt = "p_expected_updated_at"
        case name = "p_name"
        case description = "p_description"
        case compatibilityScore = "p_compatibility_score"
        case items = "p_items"
    }
}

public extension LiveOutfitRepository {
    func replaceOutfitItemsAndMetadata(_ outfit: Outfit, items: [ClosetItem]) async throws -> Outfit {
        guard let ownerID = await currentUserID(), ownerID == outfit.userID else {
            throw AstraError(category: .auth, message: "Your account changed. Sign in again before saving this outfit.")
        }
        guard (1...12).contains(items.count), Set(items.map(\.id)).count == items.count else {
            throw AstraError(category: .validation, message: "Choose between one and twelve different closet items.")
        }
        let parameters = OutfitItemsReplaceParameters(
            outfitID: outfit.id,
            expectedUpdatedAt: outfit.updatedAt,
            name: outfit.name,
            description: outfit.description,
            compatibilityScore: outfit.compatibilityScore.map(Int16.init),
            items: items.enumerated().map { index, item in
                OutfitItemsReplaceItem(closetItemID: item.id, role: item.category.rawValue, sortOrder: index)
            }
        )
        do {
            try Task.checkCancellation()
            let updated: Outfit = try await supabase
                .rpc("replace_outfit_items", params: parameters)
                .single()
                .execute()
                .value
            guard await currentUserID() == ownerID else {
                throw AstraError(category: .auth, message: "Your account changed while saving this outfit.")
            }
            let rows = OutfitItemAssembly.ownedItems(itemIDs: items.map(\.id), outfitID: updated.id, closetItems: items)
            await cache.upsert(updated, items: rows)
            await drainPendingMutations()
            return updated
        } catch let error as AstraError {
            throw error
        } catch is CancellationError {
            throw AstraError(category: .cancelled, message: "Saving the outfit was cancelled.")
        } catch {
            throw AstraError(category: .server, message: "Couldn't save your outfit changes. Reload and try again.")
        }
    }
}
