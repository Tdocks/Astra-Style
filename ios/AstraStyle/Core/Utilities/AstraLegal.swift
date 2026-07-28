//
//  AstraLegal.swift
//  AstraStyle
//
//  Canonical destinations for the legal documents spec §29 requires.
//
//  These live in one place rather than being written inline at each call site
//  because they appear in at least four: the welcome screen (§6.2), the paywall
//  (§16), profile settings (§6.22), and the account-deletion flow (§29). A
//  typo'd or stale legal URL in any one of them is an App Store review problem,
//  not a cosmetic one.
//

import Foundation

/// URLs for the user-facing legal documents.
public enum AstraLegal {
    /// The marketing/legal host. Swap this single value when the real domain is
    /// registered; every link below follows.
    private static let host = "https://astrastyle.app"

    /// Terms of Service. Spec §29 requires these to prohibit uploading images
    /// of people without their permission — load-bearing for Style Studio.
    public static let termsURL = url("/terms")

    /// Privacy Policy. Spec §29 requires it to describe image processing, model
    /// providers, retention, and affiliate relationships.
    public static let privacyURL = url("/privacy")

    /// How to request deletion of an account and all associated data (§15).
    public static let dataDeletionURL = url("/privacy/delete")

    /// Affiliate disclosure (§17: relationships must be clearly disclosed).
    public static let affiliateDisclosureURL = url("/affiliate-disclosure")

    /// Force-unwrapping is banned repo-wide, and these are compile-time
    /// constants that cannot fail — but "cannot fail" has a way of becoming
    /// "failed in production" after someone edits `host`. Falling back to the
    /// bare host means a bad path yields the website rather than a crash or a
    /// dead link, which is the right failure for a legal link.
    private static func url(_ path: String) -> URL {
        URL(string: host + path) ?? URL(string: host) ?? URL(filePath: "/")
    }
}
