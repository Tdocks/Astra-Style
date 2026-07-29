//
//  GuestClosetStore.swift
//  AstraStyle
//
//  Pure local storage for guest-mode closet items (ADR 0011 "Guest data ...
//  lives only in SwiftData and local file storage on-device — never
//  uploaded to Supabase Storage or written to any Supabase table"). This
//  protocol has no network-capable dependency in its signature — that is
//  what makes "guest mode never touches the network" a structural property
//  of `GuestClosetRepository` (Core/Persistence) rather than a promise kept
//  by convention.
//
//  Two conformances exist, mirroring `OfflineMutationQueue`'s split:
//  `SwiftDataGuestClosetStore` (Core/Persistence, production) and
//  `InMemoryGuestClosetStore` (Core/Mocks, previews + unit tests).
//

import Foundation

public protocol GuestClosetStore: Sendable {
    /// Every item currently stored for `guestUserID`, newest first.
    /// Includes archived items — callers that only want "active" items
    /// (e.g. cap enforcement) filter on `ClosetItem.isArchived` themselves.
    func items(for guestUserID: UUID) async -> [ClosetItem]

    /// A single item, scoped to `guestUserID` so one guest identity can
    /// never read or mutate another's local rows even if ids were somehow
    /// guessed (spec §6.2's guest data is single-device, but still
    /// per-identity within that device — see ADR 0011's "shared device"
    /// caveat).
    func item(id: UUID, for guestUserID: UUID) async -> ClosetItem?

    /// Inserts a new item. Callers are responsible for having already
    /// stamped `item.userID` with the current guest identity — this
    /// protocol does not second-guess ownership, only persists it.
    func insert(_ item: ClosetItem) async

    /// Overwrites an existing item's fields in place. A no-op if no row
    /// with `item.id` exists.
    func update(_ item: ClosetItem) async

    /// Soft-deletes (spec §9 "soft deletion where appropriate") the item
    /// scoped to `guestUserID`.
    func archive(id: UUID, for guestUserID: UUID, archivedAt: Date) async

    /// Permanently removes the item scoped to `guestUserID` — used once a
    /// single item has been confirmed uploaded during guest -> account
    /// migration (ADR 0011: migrate per-item so a retry after a partial
    /// failure never re-uploads an item that already succeeded).
    func remove(id: UUID, for guestUserID: UUID) async
}
