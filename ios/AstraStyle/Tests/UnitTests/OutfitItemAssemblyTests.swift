//
//  OutfitItemAssemblyTests.swift
//  AstraStyleTests
//
//  P4-OUTFIT-15 — "Saving an outfit persists `outfit_items` rows with
//  correct `role`/`sort_order`/`is_required` values"
//  (`supabase/migrations/20260728100400_outfits.sql`). Exercises the pure
//  mapping `LiveOutfitRepository.saveOutfit` and `MockOutfitRepository
//  .saveOutfit` both delegate to, with no Supabase client involved.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("OutfitItemAssembly — outfit_items role/sort_order/is_required")
struct OutfitItemAssemblyTests {

    private func closetItem(id: UUID = UUID(), category: ClothingCategory) -> ClosetItem {
        ClosetItem(id: id, userID: UUID(), name: category.rawValue, category: category)
    }

    @Test("Each item's role mirrors its closet category, and every row is required")
    func roleMirrorsCategory() {
        let top = closetItem(category: .top)
        let bottom = closetItem(category: .bottom)
        let outfitID = UUID()

        let items = OutfitItemAssembly.ownedItems(
            itemIDs: [top.id, bottom.id],
            outfitID: outfitID,
            closetItems: [top, bottom]
        )

        #expect(items.count == 2)
        #expect(items[0].role == .top)
        #expect(items[1].role == .bottom)
        // A literal closure, not `allSatisfy(\.isRequired)`. The key-path form
        // makes `rethrows` unprovable inside `#expect`'s macro expansion, and
        // the build fails with "call can throw" pointing at generated code
        // rather than at this line. The closure form infers non-throwing.
        #expect(items.allSatisfy { $0.isRequired })
        #expect(items.allSatisfy { $0.outfitID == outfitID })
    }

    @Test("Every ClothingCategory case maps to the matching OutfitItemRole")
    func everyCategoryResolves() {
        // outfit_items.role reuses the clothing_category enum verbatim
        // (20260728100400_outfits.sql) — a category this drops silently
        // would be a garment that can never appear in a saved outfit.
        for category in ClothingCategory.allCases {
            let item = closetItem(category: category)
            let assembled = OutfitItemAssembly.ownedItems(
                itemIDs: [item.id],
                outfitID: UUID(),
                closetItems: [item]
            )
            #expect(assembled.count == 1, "\(category) produced no OutfitItem")
            #expect(assembled.first?.role.rawValue == category.rawValue)
        }
    }

    @Test("sort_order matches itemIDs order, not closetItems order")
    func sortOrderMatchesRequestedOrder() {
        let jacket = closetItem(category: .outerwear)
        let shoes = closetItem(category: .shoes)
        let watch = closetItem(category: .watch)

        let items = OutfitItemAssembly.ownedItems(
            // Deliberately not the order closetItems is passed in below.
            itemIDs: [watch.id, jacket.id, shoes.id],
            outfitID: UUID(),
            closetItems: [jacket, shoes, watch]
        )

        #expect(items.map(\.role) == [.watch, .outerwear, .shoes])
        #expect(items.map(\.sortOrder) == [0, 1, 2])
    }

    @Test("An itemID with no matching closet item is dropped, not inserted with a guessed role")
    func unresolvableIDIsDropped() {
        let known = closetItem(category: .top)
        let unknownID = UUID()

        let items = OutfitItemAssembly.ownedItems(
            itemIDs: [known.id, unknownID],
            outfitID: UUID(),
            closetItems: [known]
        )

        #expect(items.count == 1)
        #expect(items.first?.closetItemID == known.id)
        // sort_order still reflects the requested position of the item
        // that DID resolve — index 0 in itemIDs — not a post-drop
        // renumbering, which would misrepresent where it belongs.
        #expect(items.first?.sortOrder == 0)
    }

    @Test("An empty itemIDs list produces no rows")
    func emptyItemIDsProducesNoRows() {
        let items = OutfitItemAssembly.ownedItems(itemIDs: [], outfitID: UUID(), closetItems: [])
        #expect(items.isEmpty)
    }
}
