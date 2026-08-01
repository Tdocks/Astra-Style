//
//  ClosetItemCaching.swift
//  AstraStyle
//
//  Local read cache for authenticated closet items (spec §7 "Cached
//  closet and outfits remain viewable" offline). Guest mode has its own
//  store (`GuestClosetStore`); this protocol is the authenticated half —
//  what `LiveClosetRepository` writes after a successful network read and
//  serves when the network is unavailable.
//
//  Two conformances: `SwiftDataClosetItemCache` (production, same
//  `PersistedClosetItem` rows the guest store uses, scoped by the real
//  account's `userID`) and `InMemoryClosetItemCache` (tests / previews).
//

import Foundation

public protocol ClosetItemCaching: Sendable {
    /// Every cached item for `userID`, newest first. Includes archived
    /// rows — callers that want the default closet view filter on
    /// `ClosetItem.isArchived` themselves.
    func items(for userID: UUID) async -> [ClosetItem]

    /// Replaces the entire cached closet for `userID` with `items`.
    /// Used after a successful network fetch so the cache mirrors the
    /// server rather than accumulating stale rows.
    func replaceAll(_ items: [ClosetItem], for userID: UUID) async

    /// Inserts or overwrites a single cached row (create / update /
    /// offline-queued write).
    func upsert(_ item: ClosetItem) async

    /// Soft-deletes a cached row scoped to `userID`.
    func archive(id: UUID, for userID: UUID, archivedAt: Date) async
}
