//
//  OutfitItemAssembly.swift
//  AstraStyle
//
//  Turns a flat `OutfitRecommendation.itemIDs` array plus the caller's
//  already-loaded closet into the `outfit_items` rows `saveOutfit` must
//  insert — correct `role` / `sort_order` / `is_required`
//  (`supabase/migrations/20260728100400_outfits.sql`, P4-OUTFIT-15).
//
//  Pulled out of `LiveOutfitRepository`/`MockOutfitRepository`, which had
//  each grown an identical copy of this mapping, so there is exactly one
//  implementation and it is unit-testable without a live Supabase project
//  or a `SupabaseClient` at all.
//

import Foundation

public enum OutfitItemAssembly {
    /// One `OutfitItem` per resolvable entry in `itemIDs`, in `itemIDs`
    /// order (`sort_order` is that index).
    ///
    /// An id with no matching `ClosetItem`, or whose category has no
    /// `OutfitItemRole` counterpart, is dropped rather than inserted with a
    /// guessed role — an absent slot is honest, a wrong one is not
    /// (`OutfitRecommendation.unmeasured`'s doc states the same rule for
    /// the score; this is the same rule at the write path).
    ///
    /// Every row here is `isRequired: true`: this only ever assembles
    /// slots for items the recommendation says the outfit contains, never
    /// `recommendation.missingProductIDs` — those are unowned
    /// `product_candidate_id` "Complete this look" slots (spec §6.18) this
    /// method has no way to resolve a `role` for, since a missing product
    /// carries no `ClosetItem`/category to look up here.
    public static func ownedItems(
        itemIDs: [UUID],
        outfitID: UUID,
        closetItems: [ClosetItem]
    ) -> [OutfitItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: closetItems.map { ($0.id, $0) })
        return itemIDs.enumerated().compactMap { index, closetItemID in
            guard
                let category = itemsByID[closetItemID]?.category,
                let role = OutfitItemRole(rawValue: category.rawValue)
            else { return nil }
            return OutfitItem(
                outfitID: outfitID,
                closetItemID: closetItemID,
                role: role,
                sortOrder: index,
                isRequired: true
            )
        }
    }
}
