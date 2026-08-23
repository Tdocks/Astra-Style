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

    /// Supabase anonymous sign-in (ADR 0018). Real `user_id`; photos stay local.
    func signInAnonymously() async throws -> AuthSession

    /// Links Apple to the current anonymous user. Same `user_id` after success.
    func linkAppleIdentity(identityToken: String, nonce: String) async throws -> AuthSession

    /// Links email OTP to the current anonymous user. Same `user_id` after success.
    func linkEmailIdentity(email: String, code: String) async throws -> AuthSession

    /// Restores a previously-persisted session from Keychain, refreshing
    /// the access token if it has expired. Returns `nil` if there is no
    /// stored session to restore.
    func restoreSession() async throws -> AuthSession?

    func signOut() async throws

    /// Requests permanent deletion of the account and everything it owns
    /// (spec §15 "Data deletion", `DELETE /account`).
    ///
    /// Returns as soon as the server has ACCEPTED the request — HTTP 202 —
    /// not once deletion has actually finished. `AccountDeletionStatus`'s
    /// own header explains why its `status` can only ever be
    /// `.pending`/`.processing`: the row cascade, the Storage purge, and
    /// the `auth.users` delete all run server-side, after this call has
    /// already returned (`account/handler.ts`'s "WHY THE CASCADE RUNS
    /// AFTER THE RESPONSE" comment).
    ///
    /// Idempotent from the caller's perspective: calling this a second
    /// time while a deletion is already in flight for the caller returns
    /// the SAME existing job rather than starting a second one or
    /// throwing (see `account/handler.ts`'s `requestDeletion` doc
    /// comment) — nothing here has to guard against a double-tap or a
    /// retried request landing twice.
    ///
    /// Signs the local session out as its last internal step, once the
    /// server has acknowledged the request — matching
    /// `LiveAuthRepository`'s existing order (delete, then sign out) so a
    /// network failure on the DELETE call never leaves a session-less
    /// client that cannot retry.
    func deleteAccount() async throws -> AccountDeletionStatus
}
