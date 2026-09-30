//
//  MockAuthRepository.swift
//  AstraStyle
//
//  In-memory `AuthRepository` for previews/tests (spec §31). Always
//  "succeeds" so preview flows never sit on a real network call.
//

import Foundation

public actor MockAuthRepository: AuthRepository {
    private var session: AuthSession?
    /// Optional, so this stays usable in isolated unit tests that don't
    /// want a `SessionStore` at all. When present (as it is from
    /// `AppContainer.preview()`), every method also mirrors its result into
    /// it using the in-memory-only mock-session path so
    /// `container.sessionStore.isSignedIn`
    /// reflects reality in previews too, rather than only this actor's own
    /// private `session`.
    private let sessionStore: SessionStore?

    public init(startSignedIn: Bool = true, sessionStore: SessionStore? = nil) {
        self.sessionStore = sessionStore
        if startSignedIn {
            session = AuthSession(userID: SampleData.userID, accessToken: "preview-token", refreshToken: "preview-refresh", expiresAt: .distantFuture)
        }
    }

    public func signInWithApple(identityToken: String, nonce: String) async throws -> AuthSession {
        let newSession = AuthSession(userID: SampleData.userID, accessToken: "preview-token", refreshToken: "preview-refresh", expiresAt: .distantFuture)
        session = newSession
        await sessionStore?.adoptInMemory(newSession)
        return newSession
    }

    public func requestEmailOTP(email: String) async throws {}

    public func verifyEmailOTP(email: String, code: String) async throws -> AuthSession {
        let newSession = AuthSession(userID: SampleData.userID, accessToken: "preview-token", refreshToken: "preview-refresh", expiresAt: .distantFuture)
        session = newSession
        await sessionStore?.adoptInMemory(newSession)
        return newSession
    }

    public func signInAnonymously() async throws -> AuthSession {
        let newSession = AuthSession(
            userID: SampleData.userID,
            accessToken: "preview-token",
            refreshToken: "preview-refresh",
            expiresAt: .distantFuture,
            isAnonymous: true
        )
        session = newSession
        await sessionStore?.adoptInMemory(newSession)
        return newSession
    }

    public func linkAppleIdentity(identityToken: String, nonce: String) async throws -> AuthSession {
        let uid = session?.userID ?? SampleData.userID
        let newSession = AuthSession(
            userID: uid,
            accessToken: "preview-token",
            refreshToken: "preview-refresh",
            expiresAt: .distantFuture,
            isAnonymous: false
        )
        session = newSession
        await sessionStore?.adoptInMemory(newSession)
        return newSession
    }

    public func linkEmailIdentity(email: String, code: String) async throws -> AuthSession {
        try await linkAppleIdentity(identityToken: email, nonce: code)
    }

    public func restoreSession() async throws -> AuthSession? {
        session
    }

    public func signOut() async throws {
        session = nil
        await sessionStore?.clearInMemorySession()
    }

    public func deleteAccount() async throws -> AccountDeletionStatus {
        session = nil
        await sessionStore?.clearInMemorySession()
        return AccountDeletionStatus(deletionID: UUID(), status: .pending)
    }
}
