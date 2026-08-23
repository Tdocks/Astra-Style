//
//  GuestLimits.swift
//  AstraStyle
//
//  Anonymous-auth trial cap (ADR 0018). Signed-in free stays at
//  `FreeTierLimits.maxClosetItems` (30). Photos never use this type —
//  they stay off `user-content` until Apple/email link.
//

import Foundation

public enum GuestLimits {
    public static let maxClosetItems = 10
}
