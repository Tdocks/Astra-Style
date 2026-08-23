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
                expiresAt: Date(timeIntervalSince1970: response.expiresAt),
                isAnonymous: response.user.isAnonymous
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
        let response: AuthResponse
        do {
            response = try await supabase.auth.verifyOTP(email: email, token: code, type: .email)
        } catch {
            throw AstraError.auth("That code didn't match. Please check and try again.")
        }

        // `AuthResponse` is an enum, not a struct with a session on it. The
        // `.user` case means the code verified but email confirmation is still
        // outstanding, so there is no session to adopt — a distinct situation
        // from a wrong code, and one the user can actually act on. Catching it
        // here rather than inside the `do` keeps the generic "didn't match"
        // message from swallowing it.
        guard case .session(let supabaseSession) = response else {
            throw AstraError.auth(
                "Your email address isn't confirmed yet. Check your inbox for the confirmation link, then try again."
            )
        }

        let session = AuthSession(
            userID: supabaseSession.user.id,
            accessToken: supabaseSession.accessToken,
            refreshToken: supabaseSession.refreshToken,
            expiresAt: Date(timeIntervalSince1970: supabaseSession.expiresAt),
            isAnonymous: supabaseSession.user.isAnonymous
        )
        try await sessionStore.adopt(session)
        return session
    }

    public func signInAnonymously() async throws -> AuthSession {
        do {
            let response = try await supabase.auth.signInAnonymously()
            let session = AuthSession(
                userID: response.user.id,
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: Date(timeIntervalSince1970: response.expiresAt),
                isAnonymous: true
            )
            try await sessionStore.adopt(session)
            return session
        } catch {
            throw Self.anonymousSignInError(from: error)
        }
    }

    /// Hosted GoTrue returns `anonymous_provider_disabled` until Auth →
    /// Providers → Anonymous is on. Map that to a sentence Apple/email can
    /// still act on, not a generic retry.
    static func anonymousSignInError(from error: Error) -> AstraError {
        let blob = "\(error) \(error.localizedDescription)".lowercased()
        if blob.contains("anonymous_provider_disabled") || blob.contains("anonymous sign-ins are disabled") {
            return AstraError.auth(
                "Guest trial isn't turned on for this server yet. Continue with Apple or email."
            )
        }
        return AstraError.auth("Couldn't start a trial without an account. Please try again.")
    }

    public func linkAppleIdentity(identityToken: String, nonce: String) async throws -> AuthSession {
        let before = await sessionStore.currentUserID()
        do {
            _ = try await supabase.auth.linkIdentityWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: identityToken, nonce: nonce)
            )
            let response = try await supabase.auth.session
            let session = AuthSession(
                userID: response.user.id,
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: Date(timeIntervalSince1970: response.expiresAt),
                isAnonymous: false
            )
            if let before, before != session.userID {
                throw AstraError.auth("That Apple account belongs to a different user. Sign in with it instead.")
            }
            try await sessionStore.adopt(session)
            return session
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.auth("Couldn't link Apple to this trial. Please try again.")
        }
    }

    public func linkEmailIdentity(email: String, code: String) async throws -> AuthSession {
        let before = await sessionStore.currentUserID()
        let response: AuthResponse
        do {
            response = try await supabase.auth.verifyOTP(email: email, token: code, type: .email)
        } catch {
            throw AstraError.auth("That code didn't match. Please check and try again.")
        }
        guard case .session(let supabaseSession) = response else {
            throw AstraError.auth(
                "Your email address isn't confirmed yet. Check your inbox for the confirmation link, then try again."
            )
        }
        let session = AuthSession(
            userID: supabaseSession.user.id,
            accessToken: supabaseSession.accessToken,
            refreshToken: supabaseSession.refreshToken,
            expiresAt: Date(timeIntervalSince1970: supabaseSession.expiresAt),
            isAnonymous: false
        )
        if let before, before != session.userID {
            throw AstraError.auth("That email belongs to a different user. Sign in with it instead.")
        }
        try await sessionStore.adopt(session)
        return session
    }

    public func restoreSession() async throws -> AuthSession? {
        try await sessionStore.restoreSession()
    }

    public func signOut() async throws {
        try await sessionStore.signOut()
    }

    public func deleteAccount() async throws -> AccountDeletionStatus {
        let status = try await apiClient.send(.deleteAccount, as: AccountDeletionStatus.self)
        try await sessionStore.signOut()
        return status
    }
}
