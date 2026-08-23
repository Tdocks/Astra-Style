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
    private let sessionRefresher: SessionRefreshing

    public init(
        apiClient: AstraAPIClient,
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current),
        keychain: KeychainTokenStore = KeychainTokenStore(),
        sessionRefresher: SessionRefreshing? = nil
    ) {
        self.supabase = supabase
        self.keychain = keychain
        // Defaults to a live wrapper over the same `supabase` instance so
        // existing call sites don't need to change; tests inject a fake
        // conformance instead (see Tests/UnitTests/SessionRestoreTests.swift)
        // to exercise the refresh branch without a live Supabase project.
        self.sessionRefresher = sessionRefresher ?? LiveSessionRefresher(supabase: supabase)
        apiClient.setAuthTokenProvider(self)
    }

    public var isSignedIn: Bool { currentSession != nil }

    // MARK: - AstraAuthTokenProviding

    public nonisolated func currentAccessToken() async -> String? {
        await MainActor.run { self.currentSession?.accessToken }
    }

    /// The current session's user id — `nil` only when nobody is signed in.
    ///
    /// `nonisolated` so it can be captured in a `@Sendable` closure and
    /// read from a background context: it is handed to repositories and
    /// view models that are not on the main actor, and forcing every one of
    /// them onto it just to read one id would be a real cost for no reason.
    ///
    /// This used to have two siblings, and the distinction between them was
    /// load-bearing while guest mode existed. It is not now (ADR 0014):
    /// there is one kind of session, so there is one question to ask.
    public nonisolated func currentUserID() async -> UUID? {
        await MainActor.run { self.currentSession?.userID }
    }

    public nonisolated func currentIsAnonymous() async -> Bool {
        await MainActor.run { self.currentSession?.isAnonymous == true }
    }

    // MARK: - Session lifecycle

    /// Restores a session from Keychain, refreshing it against Supabase if
    /// it's expired. Called once at launch by `AstraStyleApp.bootstrap()`.
    ///
    /// Every failure mode below resolves to `nil` (never a thrown error
    /// that would leave `AstraStyleApp.bootstrap()` stuck) so a bad restore
    /// always routes cleanly to `.signedOut` rather than hanging on the
    /// splash screen:
    ///   - No stored session at all -> `nil`.
    ///   - A stored session that fails to *decode* (Keychain item present
    ///     but corrupt — an OS upgrade, a partially-written value, or a
    ///     schema change) is functionally identical to "no session" from
    ///     the user's perspective: the entry is wiped and restoration
    ///     proceeds as if it had never existed, rather than propagating a
    ///     decode error all the way up through app launch.
    ///   - A valid, non-expired session is restored as-is.
    ///   - An expired session is refreshed via `sessionRefresher`; if
    ///     the refresh token itself is expired or has been revoked
    ///     server-side, the stale entry is cleared and this returns `nil`
    ///     — a normal "please sign in again" outcome, not a crash.
    @discardableResult
    public func restoreSession() async throws -> AuthSession? {
        defer { isRestoring = false }

        let stored: AuthSession?
        do {
            stored = try keychain.load()
        } catch {
            try? keychain.clear()
            currentSession = nil
            return nil
        }

        guard let stored else {
            currentSession = nil
            return nil
        }

        guard stored.isExpired else {
            currentSession = stored
            return stored
        }

        do {
            let refreshed = try await sessionRefresher.refreshSession(refreshToken: stored.refreshToken)
            let session = AuthSession(
                userID: refreshed.userID,
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken,
                expiresAt: refreshed.expiresAt,
                isAnonymous: stored.isAnonymous
            )
            try persist(session)
            return session
        } catch {
            // Refresh token itself is invalid/expired/revoked — the user
            // must sign in again. This is a normal, expected path, not a
            // crash.
            try? keychain.clear()
            currentSession = nil
            return nil
        }
    }

    public func adopt(_ session: AuthSession) throws {
        try persist(session)
    }

    public func signOut() async throws {
        try? await supabase.auth.signOut()
        try keychain.clear()
        currentSession = nil
    }

    private func persist(_ session: AuthSession) throws {
        try keychain.save(session)
        currentSession = session
    }
}
