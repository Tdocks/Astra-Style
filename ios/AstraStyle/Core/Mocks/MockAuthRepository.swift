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
    /// it — matching `LiveAuthRepository`'s behavior of calling
    /// `sessionStore.adopt(_:)` — so `container.sessionStore.isGuest` and
    /// friends reflect reality in previews too, rather than only this
    /// actor's own private `session`.
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
        try? await sessionStore?.adopt(newSession)
        return newSession
    }

    public func requestEmailOTP(email: String) async throws {}

    public func verifyEmailOTP(email: String, code: String) async throws -> AuthSession {
        let newSession = AuthSession(userID: SampleData.userID, accessToken: "preview-token", refreshToken: "preview-refresh", expiresAt: .distantFuture)
        session = newSession
        try? await sessionStore?.adopt(newSession)
        return newSession
    }

    public func continueAsGuest() async throws -> AuthSession {
        let newSession = AuthSession(userID: UUID(), accessToken: "", refreshToken: "", expiresAt: .distantFuture, isGuest: true)
        session = newSession
        try? await sessionStore?.adopt(newSession)
        return newSession
    }

    public func migrateGuestToAccount(identityToken: String, nonce: String) async throws -> AuthSession {
        try await signInWithApple(identityToken: identityToken, nonce: nonce)
    }

    public func restoreSession() async throws -> AuthSession? {
        session
    }

    public func signOut() async throws {
        session = nil
        try? await sessionStore?.signOut()
    }

    public func deleteAccount() async throws {
        session = nil
        try? await sessionStore?.signOut()
    }
}
