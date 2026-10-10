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
    @ObservationIgnored private var refreshTask: Task<String?, Never>?
    @ObservationIgnored private var sessionRevision = UUID()

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
        await accessTokenForRequest()
    }

    private func accessTokenForRequest() async -> String? {
        guard let stored = currentSession else { return nil }
        guard stored.expiresAt.timeIntervalSinceNow <= 30 else { return stored.accessToken }
        if let refreshTask { return await refreshTask.value }
        let revision = sessionRevision
        let task = Task { @MainActor [weak self] () -> String? in
            guard let self else { return nil }
            defer { if self.sessionRevision == revision { self.refreshTask = nil } }
            do {
                let refreshed = try await self.sessionRefresher.resolveSession(
                    userID: stored.userID, refreshToken: stored.refreshToken)
                guard self.sessionRevision == revision else { return nil }
                guard refreshed.userID == stored.userID, refreshed.expiresAt > .now else {
                    throw AstraError.auth("Please sign in again.")
                }
                let session = AuthSession(userID: refreshed.userID, accessToken: refreshed.accessToken,
                                          refreshToken: refreshed.refreshToken, expiresAt: refreshed.expiresAt,
                                          isAnonymous: stored.isAnonymous)
                // Persist without replacing the revision shared by concurrent waiters.
                try self.keychain.save(session)
                self.currentSession = session
                return session.accessToken
            } catch {
                guard self.sessionRevision == revision else { return nil }
                if Self.isRejectedSession(error) {
                    try? self.keychain.clear()
                    self.currentSession = nil
                }
                // Keep recoverable credentials on connectivity/server failures.
                return nil
            }
        }
        refreshTask = task
        return await task.value
    }

    private static func isRejectedSession(_ error: any Error) -> Bool {
        (error as? AstraError)?.category == .auth
            || (error as? AuthError).map {
                [.refreshTokenNotFound, .refreshTokenAlreadyUsed, .sessionNotFound,
                 .sessionExpired, .userNotFound, .userBanned].contains($0.errorCode)
            } == true
    }

    private func invalidatePendingRefresh() {
        sessionRevision = UUID()
        refreshTask?.cancel()
        refreshTask = nil
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
        invalidatePendingRefresh()
        let revision = sessionRevision
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
            let refreshed = try await sessionRefresher.resolveSession(userID: stored.userID, refreshToken: stored.refreshToken)
            guard sessionRevision == revision else { return nil }
            guard refreshed.userID == stored.userID, refreshed.expiresAt > .now else {
                throw AstraError.auth("Please sign in again.")
            }
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
            guard sessionRevision == revision else { return nil }
            // A connectivity failure must not destroy the only recoverable
            // refresh token. A later launch can retry restoration.
            if Self.isRejectedSession(error) { try? keychain.clear() }
            currentSession = nil
            return nil
        }
    }

    public func adopt(_ session: AuthSession) throws {
        try persist(session)
    }

    /// Installs a preview/test session without writing it to Keychain.
    /// Mock identities must disappear with their process so they cannot
    /// replace a real account session or leave a stale user id behind.
    func adoptInMemory(_ session: AuthSession) {
        invalidatePendingRefresh()
        currentSession = session
    }

    /// Installs a disposable UI-test session in both the app token provider
    /// and the Supabase SDK. This is available only to Debug builds and only
    /// when the configured project URL is loopback, so fixtures cannot point
    /// this path at a hosted project.
    func installLocalQASession(accessToken: String, refreshToken: String, expectedOwnerID: UUID) async throws {
        #if DEBUG
        guard AstraEnvironment.current.isLocalQABackend else {
            throw AstraError.auth("Local QA sessions require the local Supabase environment.")
        }
        let sdkSession = try await supabase.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
        guard sdkSession.user.id == expectedOwnerID else {
            try? await supabase.auth.signOut()
            throw AstraError.auth("The local QA session owner did not match its fixture.")
        }
        invalidatePendingRefresh()
        currentSession = AuthSession(
            userID: sdkSession.user.id,
            accessToken: sdkSession.accessToken,
            refreshToken: sdkSession.refreshToken,
            expiresAt: Date(timeIntervalSince1970: sdkSession.expiresAt)
        )
        #else
        throw AstraError.auth("Local QA sessions are unavailable in this build.")
        #endif
    }

    /// Clears only the current in-memory session. Preview auth must not make
    /// a request to the configured Supabase client when signing out.
    func clearInMemorySession() {
        invalidatePendingRefresh()
        currentSession = nil
    }

    /// Establishes a clean UI-test launch without calling Supabase Auth.
    /// The test flag may run before the mock backend is selected, so remove
    /// only this app's saved token and leave all other local data alone.
    func resetForUITest() {
        invalidatePendingRefresh()
        try? keychain.clear()
        currentSession = nil
    }

    public func signOut() async throws {
        invalidatePendingRefresh()
        currentSession = nil
        let revision = sessionRevision
        try keychain.clear()
        try? await supabase.auth.signOut()
        guard sessionRevision == revision else { return }
        currentSession = nil
    }

    private func persist(_ session: AuthSession) throws {
        try keychain.save(session)
        invalidatePendingRefresh()
        currentSession = session
    }
}
