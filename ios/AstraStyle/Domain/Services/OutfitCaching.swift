//
//  OutfitCaching.swift
//  AstraStyle
//
//  Local read cache for authenticated outfits (spec §7 "Cached closet and
//  outfits remain viewable" offline). Mirrors `ClosetItemCaching`'s split
//  between production (`SwiftDataOutfitCache`) and in-memory
//  (`InMemoryOutfitCache`) conformances — see that file's header for the
//  general shape this follows.
//
//  Outfits and their items are cached separately in this protocol's surface
//  even though the underlying `PersistedOutfit` row stores both together
//  (see that type's header). `fetchOutfits()` (the list) and
//  `fetchOutfitItems(outfitID:)` (the detail) are two different network
//  calls that happen at different times — a list refresh has no items to
//  offer, and treating `replaceAll` as a full row replace would silently
//  empty every outfit's already-cached item list on every list load. So
//  `replaceAll` only ever touches outfit metadata and preserves whatever
//  items a given id already had cached.
//

import Foundation

public protocol OutfitCaching: Sendable {
    /// Every cached outfit for `userID`, newest first.
    func outfits(for userID: UUID) async -> [Outfit]

    /// Cached items for one outfit, or empty if its items were never
    /// fetched (or the outfit itself was never cached).
    func items(forOutfit outfitID: UUID) async -> [OutfitItem]

    /// Replaces cached outfit metadata for `userID` with `outfits`, to
    /// mirror a successful `fetchOutfits`. Item lists already cached per
    /// outfit id survive; an id no longer present in `outfits` is dropped
    /// entirely (metadata and items both), matching a real deletion.
    func replaceAll(_ outfits: [Outfit], for userID: UUID) async

    /// Inserts or overwrites one outfit's cached metadata. Pass `items`
    /// when the caller has a fresh item list to cache alongside it (e.g.
    /// `saveOutfit`); pass `nil` to leave whatever items are already
    /// cached for this id untouched (e.g. `updateOutfit`, which never
    /// touches `outfit_items`).
    func upsert(_ outfit: Outfit, items: [OutfitItem]?) async

    /// Caches `items` for an outfit id that has already been cached (by
    /// `replaceAll` or `upsert`). A no-op when the outfit itself is not
    /// cached yet: the cache row's other fields (name, source, …) are
    /// required and not available to `fetchOutfitItems`'s caller, and
    /// inventing placeholder values for them would be exactly the
    /// confounded-absence failure `OutfitRecommendation.unmeasured`'s
    /// doc warns about, just moved into the cache layer. In practice this
    /// is not a real limitation: every screen that reaches an outfit's
    /// items got there via `fetchOutfits`/`fetchOutfit(id:)` first, so the
    /// row already exists by the time this is called.
    func upsertItems(_ items: [OutfitItem], forOutfit outfitID: UUID) async

    /// Removes a cached outfit (and its items) after a successful delete.
    func remove(id: UUID) async
}
