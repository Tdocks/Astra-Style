//
//  GuestClosetRepository.swift
//  AstraStyle
//
//  The `ClosetRepository` conformance used for guest sessions (spec §6.2
//  "Explore demo"; ADR 0011). This is the actual enforcement boundary for
//  the 10-item guest cap: `createItem` is the single place in the app that
//  can add a guest closet item, so the cap check here applies "regardless
//  of which screen calls it" — there is no other path to a guest closet
//  write.
//
//  Structurally network-free by construction, not just by convention: this
//  type's only dependencies are `GuestClosetStore` (local storage) and a
//  closure returning the current guest identity. It does not hold an
//  `AstraAPIClient` or a `SupabaseClient` — there is no HTTP-capable
//  property for a future change to accidentally wire up, unlike a runtime
//  check that could be bypassed by a new call site forgetting it.
//

import Foundation

public struct GuestClosetRepository: ClosetRepository {
    private let store: GuestClosetStore
    private let currentGuestUserID: @Sendable () async -> UUID?

    /// - Parameters:
    ///   - store: Local-only storage for guest items.
    ///   - currentGuestUserID: Resolves the *current* guest session's id at
    ///     call time (guest sessions are minted fresh per `continueAsGuest()`
    ///     call, so this cannot be captured once at construction). Typically
    ///     `{ await sessionStore.currentGuestUserID() }`.
    public init(store: GuestClosetStore, currentGuestUserID: @escaping @Sendable () async -> UUID?) {
        self.store = store
        self.currentGuestUserID = currentGuestUserID
    }

    private func requireGuestID() async throws -> UUID {
        guard let id = await currentGuestUserID() else {
            throw AstraError.auth("You're not in guest mode right now. Please sign in.")
        }
        return id
    }

    public func fetchItems() async throws -> [ClosetItem] {
        let guestID = try await requireGuestID()
        return await store.items(for: guestID).filter { !$0.isArchived }
    }

    public func fetchItem(id: UUID) async throws -> ClosetItem {
        let guestID = try await requireGuestID()
        guard let item = await store.item(id: id, for: guestID) else {
            throw AstraError.server("Couldn't find that item.")
        }
        return item
    }

    public func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] {
        // Guest mode has no separate image record yet — a guest item's
        // photo, once Scanner (Phase 3) lands, will be addressed by local
        // file URL rather than a Supabase Storage path (ADR 0011: guest
        // bytes never reach Supabase Storage). Returning an empty result is
        // honest about "nothing to show" today rather than fabricating a
        // storage path that doesn't resolve to anything.
        []
    }

    public func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        // Analysis requires uploading the image to a Vision Edge Function,
        // which would put guest photo bytes on Supabase — exactly what
        // ADR 0011 rules out for guest mode ("no cloud sync"). Refuse
        // locally, with zero network I/O, rather than attempting (and
        // failing) a call the guest was never allowed to make.
        throw AstraError.validation("Scanning isn't available in guest mode yet. Create an account to scan items.")
    }

    public func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        // Throws rather than returning a batch of per-item failures: this is
        // not "these five photos failed", it is "this capability does not
        // exist for this session", and rendering it as five retryable item
        // failures would offer the guest a retry that can never succeed.
        throw AstraError.validation("Scanning isn't available in guest mode yet. Create an account to scan items.")
    }

    /// Structural cap enforcement (spec §6.2 "Local closet capped at 10
    /// items"): counts the guest's current *active* (non-archived) items
    /// and rejects the write with `GuestClosetError.capReached` before
    /// touching storage if adding one more would exceed
    /// `GuestLimits.maxClosetItems`. `item.userID` is always overwritten
    /// with the resolved guest id — a caller cannot make a guest item
    /// "belong" to an arbitrary id by constructing `ClosetItem` a certain
    /// way.
    public func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        let guestID = try await requireGuestID()
        let activeCount = await store.items(for: guestID).filter { !$0.isArchived }.count
        guard activeCount < GuestLimits.maxClosetItems else {
            throw GuestClosetError.capReached(limit: GuestLimits.maxClosetItems)
        }
        var owned = item
        owned.userID = guestID
        await store.insert(owned)
        return owned
    }

    public func updateItem(_ item: ClosetItem) async throws -> ClosetItem {
        let guestID = try await requireGuestID()
        guard await store.item(id: item.id, for: guestID) != nil else {
            throw AstraError.server("Couldn't find that item.")
        }
        var owned = item
        owned.userID = guestID
        await store.update(owned)
        return owned
    }

    public func archiveItem(id: UUID) async throws {
        let guestID = try await requireGuestID()
        await store.archive(id: id, for: guestID, archivedAt: .now)
    }

    public func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem {
        let guestID = try await requireGuestID()
        guard var item = await store.item(id: id, for: guestID) else {
            throw AstraError.server("Couldn't find that item.")
        }
        item.wearCount += 1
        item.lastWornAt = wornAt
        item.laundryState = .wornOnce
        await store.update(item)
        return item
    }

    public func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        let guestID = try await requireGuestID()
        guard var item = await store.item(id: id, for: guestID) else {
            throw AstraError.server("Couldn't find that item.")
        }
        item.laundryState = state
        await store.update(item)
        return item
    }

    public func fetchWardrobeScore() async throws -> WardrobeScore {
        // Wardrobe Score (spec §10) is computed server-side from RLS-owned
        // rows; there is no local equivalent to fall back to for a guest.
        throw AstraError.validation("Wardrobe Score isn't available in guest mode. Create an account to unlock it.")
    }
}
