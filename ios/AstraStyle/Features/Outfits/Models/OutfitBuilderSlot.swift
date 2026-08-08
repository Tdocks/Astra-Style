//
//  OutfitBuilderSlot.swift
//  AstraStyle
//
//  One category rail slot in the Outfit builder canvas (spec §6.13). A
//  slot always exists for every rail category, whether or not it is
//  filled — the rail is the fixed set of places a garment CAN go, not a
//  list of garments that happen to be chosen.
//

import Foundation

public struct OutfitBuilderSlot: Identifiable, Equatable, Sendable {
    public let category: ClothingCategory
    public var item: ClosetItem?
    /// Long-press-to-lock (spec §6.13). A locked slot's `item` must survive
    /// `OutfitBuilderViewModel.regenerate()` unchanged — see that method's
    /// own header for why that is enforced as a client-side invariant.
    public var isLocked: Bool

    public var id: ClothingCategory { category }

    public init(category: ClothingCategory, item: ClosetItem? = nil, isLocked: Bool = false) {
        self.category = category
        self.item = item
        self.isLocked = isLocked
    }

    /// A locked slot with no item is a state nothing in this view model
    /// ever produces (`toggleLock` refuses to lock an empty slot), but is
    /// still representable — this reads it back honestly rather than
    /// asserting.
    public var isFilled: Bool { item != nil }
}

public extension ClothingCategory {
    /// The category rail's fixed left-to-right order, per spec §6.13:
    /// "Tops, Bottoms, Outerwear, Shoes, Watches, Accessories, Fragrance".
    ///
    /// Deliberately NOT `ClothingCategory.allCases`, whose declaration
    /// order (`Enums.swift`) puts Accessories before Watches — correct for
    /// the Closet category tiles (spec §6.14's own listed order), wrong
    /// for the builder rail, which names Watches first. Two screens, two
    /// orders, both taken verbatim from the spec sections that define them.
    static let outfitBuilderRailOrder: [ClothingCategory] = [
        .top, .bottom, .outerwear, .shoes, .watch, .accessory, .fragrance
    ]
}
