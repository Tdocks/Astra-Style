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
//  The four documents are live on astra-style.com (same URLs as App Store
//  Connect). They are still drafts with counsel placeholders — flipping this
//  flag does not invent entity names; it stops the app from pretending the
//  public pages do not exist.
//

import Foundation

/// URLs for the user-facing legal documents.
public enum AstraLegal {
    private static let host = "https://astra-style.com"

    /// Whether the documents at the paths below are reachable over HTTPS.
    public static let isPublished = true

    /// Terms of Service. Spec §29 requires these to prohibit uploading images
    /// of people without their permission — load-bearing for Style Studio.
    public static var termsURL: URL? { resolved("/terms/") }

    /// Privacy Policy. Spec §29 requires it to describe image processing, model
    /// providers, retention, and affiliate relationships.
    public static var privacyURL: URL? { resolved("/privacy/") }

    /// How to request deletion of an account and all associated data (§15).
    public static var dataDeletionURL: URL? { resolved("/privacy/delete/") }

    /// Affiliate disclosure (§17: relationships must be clearly disclosed).
    public static var affiliateDisclosureURL: URL? { resolved("/affiliate-disclosure/") }

    /// `nil` while unpublished.
    private static func resolved(_ path: String) -> URL? {
        guard isPublished else { return nil }
        return URL(string: host + path)
    }
}
