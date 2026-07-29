//
//  LiveGuestMigrationService.swift
//  AstraStyle
//
//  Production `GuestMigrationService` (spec §7 "Guest migration to
//  account"; ADR 0011). Composes local `GuestClosetStore` reads with the
//  *live*, Supabase-backed `ClosetRepository` — never the guest-routing
//  `GuestAwareClosetRepository` — so migrated items are always written as
//  real, RLS-owned rows and never accidentally looped back into guest
//  storage.
//

import Foundation

public struct LiveGuestMigrationService: GuestMigrationService {
    private let closetRepository: ClosetRepository
    private let guestClosetStore: GuestClosetStore

    public init(closetRepository: ClosetRepository, guestClosetStore: GuestClosetStore) {
        self.closetRepository = closetRepository
        self.guestClosetStore = guestClosetStore
    }

    public func migrateClosetItems(guestUserID: UUID, to session: AuthSession) async -> GuestMigrationResult {
        let localItems = await guestClosetStore.items(for: guestUserID)
        var migratedCount = 0

        for item in localItems {
            var owned = item
            // Ownership comes from the freshly authenticated session, never
            // from whatever `userID` the local guest record happened to
            // carry — ADR 0011 explicitly rejects a client-supplied id
            // becoming the owner. `session.userID` is the only value that
            // can possibly pass the destination table's RLS policy anyway,
            // but this is enforced here rather than left to RLS alone.
            owned.userID = session.userID
            do {
                _ = try await closetRepository.createItem(owned, images: [])
            } catch {
                // Stop at the first failure rather than skipping ahead —
                // everything not yet migrated (including this one) stays in
                // local guest storage, so the migration is retryable
                // instead of silently dropping items (ADR 0011).
                let remaining = await guestClosetStore.items(for: guestUserID).count
                return GuestMigrationResult(migratedItemCount: migratedCount, remainingItemCount: remaining)
            }
            await guestClosetStore.remove(id: item.id, for: guestUserID)
            migratedCount += 1
        }

        return GuestMigrationResult(migratedItemCount: migratedCount, remainingItemCount: 0)
    }
}
