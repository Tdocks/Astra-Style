//
//  CreateAccountViewModel.swift
//  AstraStyle
//
//  Drives `CreateAccountSheet` (spec §7 "Guest migration to account";
//  ADR 0011). Owns the Sign in with Apple flow and, once *any* real session
//  exists (Apple here, or email OTP reported in by `EmailAuthSheet`),
//  drives the local-guest-closet-to-account transfer via
//  `GuestMigrationService` — the repository-level cap enforcement in
//  `GuestClosetRepository` guarantees this is the path a guest who hit the
//  10-item cap needs, not a dead end.
//

import Foundation

@MainActor
@Observable
public final class CreateAccountViewModel {
    public enum Phase: Equatable {
        case idle
        case authenticating
        case migratingCloset
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var migratedItemCount: Int?
    public private(set) var remainingItemCount: Int?

    private let authRepository: AuthRepository
    private let guestMigrationService: GuestMigrationService
    private let appleSignIn: AppleSignInProviding
    /// The guest session's id, captured by the caller *before* presenting
    /// this view model — must be read before any sign-in call succeeds,
    /// since a successful sign-in immediately replaces
    /// `SessionStore.currentSession` with the new, non-guest one.
    private let guestUserID: UUID?

    public init(
        authRepository: AuthRepository,
        guestMigrationService: GuestMigrationService,
        appleSignIn: AppleSignInProviding,
        guestUserID: UUID?
    ) {
        self.authRepository = authRepository
        self.guestMigrationService = guestMigrationService
        self.appleSignIn = appleSignIn
        self.guestUserID = guestUserID
    }

    /// `true` once migration has run and left nothing behind — the sheet
    /// should dismiss.
    public var isFinished: Bool {
        guard case .idle = phase else { return false }
        return migratedItemCount != nil
    }

    public func continueWithApple() async {
        phase = .authenticating
        do {
            let result = try await appleSignIn.performSignIn()
            let session = try await authRepository.migrateGuestToAccount(
                identityToken: result.identityToken,
                nonce: result.rawNonce
            )
            await migrateCloset(into: session)
        } catch let error as AstraError where error.category == .cancelled {
            // User dismissed the Apple sheet — back to idle silently, not
            // an error state.
            phase = .idle
        } catch let error as AstraError {
            phase = .failed(error.message)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Call after any other auth surface (currently `EmailAuthSheet`) has
    /// already established a real session — closet migration doesn't care
    /// which method produced it.
    public func finishAfterExternalSignIn(session: AuthSession) async {
        await migrateCloset(into: session)
    }

    private func migrateCloset(into session: AuthSession) async {
        guard let guestUserID else {
            // Nothing was ever a guest session (e.g. this view model was
            // constructed without one) — the account itself still exists
            // and succeeded; there's simply nothing local to move.
            migratedItemCount = 0
            remainingItemCount = 0
            phase = .idle
            return
        }
        phase = .migratingCloset
        let result = await guestMigrationService.migrateClosetItems(guestUserID: guestUserID, to: session)
        migratedItemCount = result.migratedItemCount
        remainingItemCount = result.remainingItemCount
        phase = result.isComplete
            ? .idle
            : .failed(String(localized: "Some items couldn't be moved yet. They're still saved on this device — try again from Profile."))
    }
}
