//
//  AuthSession.swift
//  AstraStyle
//
//  A transient (never persisted as-is; tokens live in Keychain via
//  Core/Auth) representation of an authenticated Supabase session.
//

import Foundation

public struct AuthSession: Equatable, Sendable {
    public let userID: UUID
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    // There is no `isGuest`. Every session is a real, server-side one
    // (ADR 0014) — so there is no longer a shape of this type that means
    // "signed in, but not really", and no call site has to remember to ask.

    public init(userID: UUID, accessToken: String, refreshToken: String, expiresAt: Date) {
        self.userID = userID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool { expiresAt <= .now }
}
