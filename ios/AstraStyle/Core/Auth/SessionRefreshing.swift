//
//  SessionRefreshing.swift
//  AstraStyle
//
//  Isolates `SessionStore.restoreSession()` from the concrete Supabase SDK
//  call it needs (exchange a stored refresh token for a new access token)
//  so the expired-but-refreshable and expired-and-unrefreshable restore
//  paths can be exercised in a unit test without a live Supabase project.
//  Before this existed, `restoreSession()`'s refresh branch called
//  `supabase.auth.refreshSession(refreshToken:)` directly against a
//  concrete `SupabaseClient` with no seam to fake — exactly why the doc
//  comment on `AuthRepository.restoreSession()` could say the method
//  "exists" while nothing ever actually drove its refresh branch in a
//  test.
//

import Foundation
import Supabase

/// A successfully refreshed session, decoupled from Supabase's own
/// `Session` type so `SessionStore` (and anything testing it) only depends
/// on this small, `Equatable` shape.
public struct RefreshedSession: Sendable, Equatable {
    public let userID: UUID
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(userID: UUID, accessToken: String, refreshToken: String, expiresAt: Date) {
        self.userID = userID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// Exchanges a stored refresh token for a new access token (spec §7
/// "Session restoration").
public protocol SessionRefreshing: Sendable {
    /// Throws if the refresh token itself is invalid, expired, or revoked
    /// server-side — a normal, expected outcome (the user must sign in
    /// again), not a crash condition.
    func refreshSession(refreshToken: String) async throws -> RefreshedSession
}

/// Production `SessionRefreshing`: a thin wrapper over
/// `SupabaseClient.auth.refreshSession(refreshToken:)`.
public struct LiveSessionRefresher: SessionRefreshing {
    private let supabase: SupabaseClient

    public init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    public func refreshSession(refreshToken: String) async throws -> RefreshedSession {
        let refreshed = try await supabase.auth.refreshSession(refreshToken: refreshToken)
        return RefreshedSession(
            userID: refreshed.user.id,
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresAt: Date(timeIntervalSince1970: refreshed.expiresAt)
        )
    }
}
