//
//  GuestLimits.swift
//  AstraStyle
//
//  Spec §6.2 "Guest mode restrictions" as named constants, so the cap is a
//  single source of truth rather than a bare `10` copy-pasted across the
//  repository, the view model, and the upgrade-prompt copy. Enforcement
//  itself lives at the repository boundary — see `GuestClosetRepository`
//  (Core/Persistence) — not here; this file only names the numbers and the
//  typed failure they produce.
//

import Foundation

/// Numeric limits for guest mode (spec §6.2): "Local closet capped at 10
/// items. No cloud sync. One Style Studio sample. No shopping history."
public enum GuestLimits {
    /// Spec §6.2 "Local closet capped at 10 items."
    public static let maxClosetItems = 10

    /// Spec §6.2 "One Style Studio sample."
    public static let maxStyleStudioSamples = 1
}

/// Typed failure for guest-mode closet writes that would exceed
/// `GuestLimits.maxClosetItems`. Deliberately a distinct type from
/// `AstraError` (rather than a new `AstraError.Category`) so call sites can
/// catch this exact condition — "show the create-account prompt" — without
/// pattern-matching on a message string or a category that also covers
/// unrelated validation failures.
public enum GuestClosetError: Error, Sendable, Equatable, LocalizedError {
    /// A guest tried to add an item beyond `limit` (always
    /// `GuestLimits.maxClosetItems` in production; the value travels with
    /// the case so the message doesn't have to re-import the constant).
    case capReached(limit: Int)

    public var errorDescription: String? {
        switch self {
        case .capReached(let limit):
            return String(
                localized: "Guest mode is limited to \(limit) closet items. Create an account to keep this closet, sync it across devices, and add more.",
                comment: "Shown when a guest tries to add a closet item past the guest-mode cap"
            )
        }
    }
}
