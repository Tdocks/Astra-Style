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

    public init(startSignedIn: Bool = true) {
        if startSignedIn {
            session = AuthSession(userID: SampleData.userID, accessToken: "preview-token", refreshToken: "preview-refresh", expiresAt: .distantFuture)
        }
    }

    public func signInWithApple(identityToken: String, nonce: String) async throws -> AuthSession {
        let newSession = AuthSession(userID: SampleData.userID, accessToken: "preview-token", refreshToken: "preview-refresh", expiresAt: .distantFuture)
        session = newSession
        return newSession
    }

    public func requestEmailOTP(email: String) async throws {}

    public func verifyEmailOTP(email: String, code: String) async throws -> AuthSession {
        let newSession = AuthSession(userID: SampleData.userID, accessToken: "preview-token", refreshToken: "preview-refresh", expiresAt: .distantFuture)
        session = newSession
        return newSession
    }

    public func continueAsGuest() async throws -> AuthSession {
        let newSession = AuthSession(userID: UUID(), accessToken: "", refreshToken: "", expiresAt: .distantFuture, isGuest: true)
        session = newSession
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
    }

    public func deleteAccount() async throws {
        session = nil
    }
}
