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

    // There is no `continueAsGuest()` and no `migrateGuestToAccount(...)`.
    // An account is required before onboarding (ADR 0014), so the only two
    // ways into a session are the two above.

    /// Restores a previously-persisted session from Keychain, refreshing
    /// the access token if it has expired. Returns `nil` if there is no
    /// stored session to restore.
    func restoreSession() async throws -> AuthSession?

    func signOut() async throws

    /// Permanently deletes the account and all associated data
    /// (spec §15 "Data deletion", `DELETE /account`).
    func deleteAccount() async throws
}
