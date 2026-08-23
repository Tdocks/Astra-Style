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
    public let isAnonymous: Bool

    public init(
        userID: UUID,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        isAnonymous: Bool = false
    ) {
        self.userID = userID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.isAnonymous = isAnonymous
    }

    public var isExpired: Bool { expiresAt <= .now }
}
