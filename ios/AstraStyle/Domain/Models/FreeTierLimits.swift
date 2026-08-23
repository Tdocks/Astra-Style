//
//  FreeTierLimits.swift
//  AstraStyle
//
//  Spec §16 free-tier closet cap as a named constant, mirroring
//  `GuestLimits` for the guest 10-item cap. Enforcement lives at the
//  repository boundary (`FreeTierCappedClosetRepository`) so every
//  signed-in create path — Closet form, onboarding first-items, guest
//  migration — shares one check.
//
//  Premium uncapping reads `Subscription.isEntitledToPremium` (already
//  modeled). Full entitlement resolution and paywall UI are Phase 7
//  (`P7-SUB-04` / `P7-SUB-05`); until then, non-entitled signed-in users
//  are treated as free tier.
//

import Foundation

/// Numeric limits for the free subscription tier (spec §16 "Up to 30
/// closet items").
public enum FreeTierLimits {
    /// Spec §16 free-tier closet item cap.
    public static let maxClosetItems = 30

    /// Spec: one Visualize trial, then paywall. Wear This stays free.
    public static let studioTrialGenerations = 1
}

/// Typed failure for free-tier closet writes that would exceed
/// `FreeTierLimits.maxClosetItems`. Distinct from `GuestClosetError` and
/// from `AstraError` so call sites can surface a limit/upgrade notice
/// without string-matching — and without inventing a paywall UI here
/// (that surface is `P7-SUB-05`).
public enum FreeTierClosetError: Error, Sendable, Equatable, LocalizedError {
    /// A free-tier account tried to add an item beyond `limit`.
    case capReached(limit: Int)

    public var errorDescription: String? {
        switch self {
        case .capReached(let limit):
            return String(
                localized: "Free accounts can save up to \(limit) closet items. Archive something you no longer wear, or upgrade to Premium to keep adding.",
                comment: "Shown when a free-tier user tries to add a closet item past the free-tier cap"
            )
        }
    }
}
