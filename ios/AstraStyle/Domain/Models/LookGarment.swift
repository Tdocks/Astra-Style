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

public struct LookGarment: Identifiable, Sendable {
    public var id: UUID { item.id }
    public var item: ClosetItem
    public var role: OutfitItemRole
    /// Signed URL for the garment's display image — the background-removed
    /// cutout when one exists, which since `BackgroundRemoval` shipped is
    /// every garment scanned after it. Nil while signing is in flight or if
    /// it failed; the tile falls back to a labelled placeholder rather than
    /// an empty hole.
    public var imageURL: URL?

    public init(item: ClosetItem, role: OutfitItemRole, imageURL: URL? = nil) {
        self.item = item
        self.role = role
        self.imageURL = imageURL
    }
}
