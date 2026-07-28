//
//  SessionStore.swift
//  AstraStyle
//
//  The single source of truth for "who is signed in right now", shared
//  across the app via the environment (spec §8 "Shared authenticated
//  session: injected session store"). Wraps Supabase Auth (Sign in with
//  Apple, email OTP, session refresh — spec §7) and Keychain-backed
//  persistence (spec §7 "Session restoration").
//
//  Conforms to `AstraAuthTokenProviding` so `AstraAPIClient` can attach a
//  bearer token to every Edge Function call without owning auth logic
//  itself.
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
public final class SessionStore: AstraAuthTokenProviding {
    public private(set) var currentSession: AuthSession?
    public private(set) var isRestoring = true

    private let supabase: SupabaseClient
    private let keychain: KeychainTokenStore

    public init(
        apiClient: AstraAPIClient,
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current),
        keychain: KeychainTokenStore = KeychainTokenStore()
    ) {
        self.supabase = supabase
        self.keychain = keychain
        apiClient.setAuthTokenProvider(self)
    }

    public var isSignedIn: Bool { currentSession != nil }
    public var isGuest: Bool { currentSession?.isGuest ?? false }

    // MARK: - AstraAuthTokenProviding

    public nonisolated func currentAccessToken() async -> String? {
        await MainActor.run { self.currentSession?.accessToken }
    }

    // MARK: - Session lifecycle

    /// Attempts to restore a session from Keychain, refreshing it against
    /// Supabase if it's expired. Called once at launch by
    /// `AstraStyleApp.bootstrap()`.
    @discardableResult
    public func restoreSession() async throws -> AuthSession? {
        defer { isRestoring = false }

        guard let stored = try keychain.load() else {
            currentSession = nil
            return nil
        }

        if stored.isGuest {
            currentSession = stored
            return stored
        }

        guard stored.isExpired else {
            currentSession = stored
            return stored
        }

        do {
            let refreshed = try await supabase.auth.refreshSession(refreshToken: stored.refreshToken)
            let session = AuthSession(
                userID: refreshed.user.id,
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken,
                expiresAt: Date(timeIntervalSince1970: refreshed.expiresAt)
            )
            try persist(session)
            return session
        } catch {
            // Refresh token itself is invalid/expired — the user must sign
            // in again. This is a normal, expected path, not a crash.
            try? keychain.clear()
            currentSession = nil
            return nil
        }
    }

    public func adopt(_ session: AuthSession) throws {
        try persist(session)
    }

    public func signOut() async throws {
        if !isGuest {
            try? await supabase.auth.signOut()
        }
        try keychain.clear()
        currentSession = nil
    }

    private func persist(_ session: AuthSession) throws {
        try keychain.save(session)
        currentSession = session
    }
}
