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
    /// `true` for the limited local-only guest mode (spec §6.2 "Guest mode
    /// restrictions"): capped closet, no cloud sync, one Style Studio
    /// sample, no shopping history.
    public let isGuest: Bool

    public init(userID: UUID, accessToken: String, refreshToken: String, expiresAt: Date, isGuest: Bool = false) {
        self.userID = userID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.isGuest = isGuest
    }

    public var isExpired: Bool { expiresAt <= .now }
}
