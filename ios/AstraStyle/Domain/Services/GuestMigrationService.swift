//
//  GuestMigrationService.swift
//  AstraStyle
//
//  Guest -> account closet migration (spec §7 "Guest migration to
//  account"; ADR 0011). `AuthRepository.migrateGuestToAccount` only
//  performs the credential exchange — by its own doc comment, "that
//  reconciliation is intentionally not performed here — it belongs to
//  whichever repository owns the guest-local data." This is that owner.
//
//  Deliberately decoupled from *how* the new session was established:
//  ADR 0011 draws no behavioural distinction between Sign in with Apple and
//  email OTP once a real session exists, so this takes an already-minted
//  `AuthSession` rather than performing auth itself. Call it immediately
//  after any successful sign-in/re-auth that happened from within a guest
//  session.
//
//  Live conformance lives in Core/Persistence (`LiveGuestMigrationService`)
//  since it composes `GuestClosetStore` (local) with the *live*
//  `ClosetRepository` (never the guest-routing wrapper — items must land as
//  real, RLS-owned Supabase rows, not loop back into guest storage).
//

import Foundation

public protocol GuestMigrationService: Sendable {
    /// Uploads every item stored locally under `guestUserID` to `session`'s
    /// account, then removes each one from local guest storage as it's
    /// confirmed. Stops at the first failure and reports how far it got
    /// (ADR 0011: "on partial failure, guest data is retained locally ...
    /// resumable/retryable rather than silently dropping unmigrated
    /// items") — this method never throws for a partial closet-transfer
    /// failure, since the account itself was already created successfully
    /// by the time this runs; callers inspect `remainingItemCount` instead.
    func migrateClosetItems(guestUserID: UUID, to session: AuthSession) async -> GuestMigrationResult
}

public struct GuestMigrationResult: Sendable, Equatable {
    /// Guest items successfully uploaded and inserted under the new
    /// account.
    public let migratedItemCount: Int
    /// Guest items still sitting in local guest storage because a transfer
    /// failed partway through. Zero means every item transferred cleanly.
    public let remainingItemCount: Int

    public init(migratedItemCount: Int, remainingItemCount: Int) {
        self.migratedItemCount = migratedItemCount
        self.remainingItemCount = remainingItemCount
    }

    public var isComplete: Bool { remainingItemCount == 0 }
}
