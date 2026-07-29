//
//  CreateAccountReason.swift
//  AstraStyle
//
//  Where the guest -> account creation prompt was triggered from (spec §7
//  "Guest migration to account"). Mirrors `PaywallContext`'s role for the
//  subscription paywall: both `AppRouter` (to route to the right modal) and
//  the presenting view (to pick the right copy) need this, and `Domain` is
//  the one layer both are allowed to depend on.
//

import Foundation

public enum CreateAccountReason: Sendable, Equatable {
    /// A guest tapped a general "create an account" affordance (e.g. from
    /// the Profile tab's guest banner), not because they were blocked.
    case guestUpgrade
    /// A guest's closet write was rejected by `GuestClosetError.capReached`
    /// (spec §6.2 "Local closet capped at 10 items").
    case closetCapReached
}
