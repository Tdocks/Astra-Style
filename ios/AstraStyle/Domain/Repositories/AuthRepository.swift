//
//  AuthRepository.swift
//  AstraStyle
//
//  Authentication and account lifecycle (spec §7 "Authentication"):
//  Sign in with Apple, email OTP, session restoration, guest migration,
//  and in-app account deletion.
//
//  Conformances live in Core/Auth (`LiveAuthRepository`, built on
//  `AstraAPIClient` + Supabase Auth) and Core/Mocks (`MockAuthRepository`).
//

import Foundation

public protocol AuthRepository: Sendable {
    /// Exchanges an Apple identity token for a Supabase session.
    ///
    /// - Parameter nonce: The *raw* (unhashed) nonce that was SHA-256-hashed
    ///   into the original `ASAuthorizationAppleIDRequest.nonce` (see
    ///   `AppleSignInNonce`/`AppleSignInCoordinator`, Core/Auth). Required by
    ///   Supabase's `signInWithIdToken` to verify `identityToken` wasn't
    ///   replayed from a different sign-in attempt — omitting it is a real,
    ///   silent security gap, not just a missing parameter.
    func signInWithApple(identityToken: String, nonce: String) async throws -> AuthSession

    /// Requests an email magic link / one-time code.
    func requestEmailOTP(email: String) async throws

    /// Verifies the code the user received by email.
    func verifyEmailOTP(email: String, code: String) async throws -> AuthSession

    /// Starts a local-only guest session (spec §6.2 "Explore demo" /
    /// "continue in limited guest mode").
    func continueAsGuest() async throws -> AuthSession

    /// Upgrades an existing guest session to a full account, preserving
    /// locally-created data (spec §7 "Guest migration to account"). See
    /// `signInWithApple(identityToken:nonce:)` for what `nonce` must be.
    func migrateGuestToAccount(identityToken: String, nonce: String) async throws -> AuthSession

    /// Restores a previously-persisted session from Keychain, refreshing
    /// the access token if it has expired. Returns `nil` if there is no
    /// stored session to restore.
    func restoreSession() async throws -> AuthSession?

    func signOut() async throws

    /// Permanently deletes the account and all associated data
    /// (spec §15 "Data deletion", `DELETE /account`).
    func deleteAccount() async throws
}
