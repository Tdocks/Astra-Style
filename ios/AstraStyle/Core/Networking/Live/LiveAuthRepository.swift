//
//  LiveAuthRepository.swift
//  AstraStyle
//
//  Production `AuthRepository`. Delegates the actual Supabase Auth calls
//  and Keychain persistence to `SessionStore` (Core/Auth) so there is a
//  single place that owns "what is the current session" — this type is a
//  thin, protocol-shaped façade over it, plus the one operation that isn't
//  really an auth-provider concern: account deletion, which fans out
//  across storage/embeddings/rows server-side (spec §15) via
//  `DELETE /account`.
//

import Foundation
import Supabase

public final class LiveAuthRepository: AuthRepository, @unchecked Sendable {
    private let apiClient: AstraAPIClient
    private let supabase: SupabaseClient
    private let sessionStore: SessionStore

    public init(apiClient: AstraAPIClient, sessionStore: SessionStore, supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)) {
        self.apiClient = apiClient
        self.sessionStore = sessionStore
        self.supabase = supabase
    }

    public func signInWithApple(identityToken: String, nonce: String) async throws -> AuthSession {
        do {
            let response = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: identityToken, nonce: nonce)
            )
            let session = AuthSession(
                userID: response.user.id,
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: Date(timeIntervalSince1970: response.expiresAt)
            )
            try await sessionStore.adopt(session)
            return session
        } catch {
            throw AstraError.auth("Sign in with Apple failed. Please try again.")
        }
    }

    public func requestEmailOTP(email: String) async throws {
        do {
            try await supabase.auth.signInWithOTP(email: email)
        } catch {
            throw AstraError.auth("We couldn't send a code to that email address.")
        }
    }

    public func verifyEmailOTP(email: String, code: String) async throws -> AuthSession {
        do {
            let response = try await supabase.auth.verifyOTP(email: email, token: code, type: .email)
            let session = AuthSession(
                userID: response.user.id,
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: Date(timeIntervalSince1970: response.expiresAt)
            )
            try await sessionStore.adopt(session)
            return session
        } catch {
            throw AstraError.auth("That code didn't match. Please check and try again.")
        }
    }

    public func continueAsGuest() async throws -> AuthSession {
        // Guest mode is intentionally local-only (spec §6.2): a synthetic
        // session with no server round trip, capped client-side by the
        // repository layers that check `AuthSession.isGuest`.
        let session = AuthSession(
            userID: UUID(),
            accessToken: "",
            refreshToken: "",
            expiresAt: .distantFuture,
            isGuest: true
        )
        try await sessionStore.adopt(session)
        return session
    }

    public func migrateGuestToAccount(identityToken: String, nonce: String) async throws -> AuthSession {
        // Sign in for real, then the Live repositories are responsible for
        // re-pointing any content created under the guest's local-only
        // storage at the newly-authenticated user id (spec §7 "Guest
        // migration to account"). That reconciliation is intentionally not
        // performed here — it belongs to whichever repository owns the
        // guest-local data (Closet, primarily).
        try await signInWithApple(identityToken: identityToken, nonce: nonce)
    }

    public func restoreSession() async throws -> AuthSession? {
        try await sessionStore.restoreSession()
    }

    public func signOut() async throws {
        try await sessionStore.signOut()
    }

    public func deleteAccount() async throws {
        _ = try await apiClient.send(.deleteAccount, as: AstraEmptyPayload.self)
        try await sessionStore.signOut()
    }
}
