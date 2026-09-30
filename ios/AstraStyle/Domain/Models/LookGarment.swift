//
//  LookGarment.swift
//  AstraStyle
//
//  One garment in today's look, with everything the screen needs to draw it.
//
//  Home has always fetched the outfit's items — `primaryOutfitItems`, an
//  array of `OutfitItem`, loaded on every brief — and never shown them.
//  `HeroOutfitCardView` rendered `outfit.heroImageURL ?? generatedPreviewURL`
//  instead, and neither of those is ever written by anything: `hero_image_url`
//  appears exactly once in the whole codebase, as a `CodingKey`, and
//  `generatedPreviewURL` comes from Style Studio, which is not built. So the
//  largest element on the screen was a permanent placeholder, above a
//  garment list the app was holding and discarding.
//
//  IN `Domain/Models` RATHER THAN UNDER `Features/Home`, WHICH IS WHERE IT
//  STARTED. Home was the first screen to need a drawable garment, but it is
//  not the only one: the Closet's outfit carousel draws the same shape, and a
//  type owned by one feature and imported by another is how two nearly-equal
//  copies of it eventually appear.
//
//  `OutfitItem` alone cannot be drawn — it carries a `closetItemID` and a
//  role, not a name or a photograph. This is the joined shape.
//

import Foundation

/// The display-safe garment details an outfit tile needs. Deliberately smaller
/// than `ClosetItem`: a peer's public look must never hydrate purchase, size,
/// laundry, or wear-history fields just to draw a card.
public struct LookGarmentItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var brand: String?
    public var category: ClothingCategory
    public var formalityScore: Int?

    public init(
        id: UUID,
        name: String,
        brand: String? = nil,
        category: ClothingCategory,
        formalityScore: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.category = category
        self.formalityScore = formalityScore
    }

    public init(closetItem: ClosetItem) {
        self.init(
            id: closetItem.id,
            name: closetItem.name,
            brand: closetItem.brand,
            category: closetItem.category,
            formalityScore: closetItem.formalityScore
        )
    }
}

/// A single garment in a drawable outfit, with the signed photo URL when one
/// is available. The same shape works for a user's own closet and a sanitized
/// public look without carrying private closet fields into shared screens.
public struct LookGarment: Identifiable, Equatable, Sendable {
    public var id: UUID { item.id }
    public var item: LookGarmentItem
    public var role: OutfitItemRole
    /// Signed URL for the garment's display image. Nil while signing is in
    /// flight or if it failed; the tile falls back to a labelled placeholder.
    public var imageURL: URL?

    public init(item: ClosetItem, role: OutfitItemRole, imageURL: URL? = nil) {
        self.init(item: LookGarmentItem(closetItem: item), role: role, imageURL: imageURL)
    }

    public init(item: LookGarmentItem, role: OutfitItemRole, imageURL: URL? = nil) {
        self.item = item
        self.role = role
        self.imageURL = imageURL
    }
}

/// A public, display-only garment row returned by the guarded lookbook RPC.
/// It excludes owner ids, purchase/sizing details, laundry and wear state,
/// private image paths, and all private image metadata beyond an opaque id.
public struct PublicLookGarment: Codable, Equatable, Sendable {
    public let outfitID: UUID
    public let closetItemID: UUID
    public let name: String
    public let brand: String?
    public let category: ClothingCategory
    public let role: OutfitItemRole
    public let formalityScore: Int?
    public let sortOrder: Int
    public let displayImageID: UUID?

    enum CodingKeys: String, CodingKey {
        case outfitID = "outfit_id"
        case closetItemID = "closet_item_id"
        case name
        case brand
        case category
        case role
        case formalityScore = "formality_score"
        case sortOrder = "sort_order"
        case displayImageID = "display_image_id"
    }
}
