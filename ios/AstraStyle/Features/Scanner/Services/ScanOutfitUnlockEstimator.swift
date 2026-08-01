//
//  ScanOutfitUnlockEstimator.swift
//  AstraStyle
//
//  Phase-3-era simplified unlock count for P3-SCAN-11 (spec §5.3 step 9).
//  Counts complementary-category partners already in the closet — not the
//  real purchase-unlock algorithm in `P4-OUTFIT-09`. Revisit when that
//  scorer ships; until then this is honest combinatorial scaffolding,
//  never a hardcoded placeholder.
//

import Foundation

public enum ScanOutfitUnlockEstimator: Sendable {
    /// How many new outfit pairings the added item enables against the
    /// current active closet (excluding the item itself and archives).
    public static func newlyUnlockedCount(adding item: ClosetItem, to closet: [ClosetItem]) -> Int {
        let partners = closet.filter { existing in
            existing.id != item.id
                && existing.archivedAt == nil
                && complementaryCategories(for: item.category).contains(existing.category)
        }
        return partners.count
    }

    /// Categories that can form a useful pairing with `category` in the
    /// Phase-3 heuristic. Watches/fragrance/accessories count against
    /// tops/outerwear (accent pieces); footwear pairs with bottoms and
    /// tops for a minimal complete look.
    public static func complementaryCategories(for category: ClothingCategory) -> Set<ClothingCategory> {
        switch category {
        case .top:
            [.bottom, .shoes, .outerwear]
        case .bottom:
            [.top, .shoes, .outerwear]
        case .outerwear:
            [.top, .bottom, .shoes]
        case .shoes:
            [.top, .bottom, .outerwear]
        case .accessory, .watch, .fragrance:
            [.top, .outerwear, .bottom]
        }
    }
}
