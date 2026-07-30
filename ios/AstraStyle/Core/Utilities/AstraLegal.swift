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
//  ⚠️ NOTHING BEHIND THESE URLS EXISTS YET. `astrastyle.app` is NXDOMAIN
//  (verified 2026-07-30: `nslookup` returns NXDOMAIN, `curl` returns
//  "Could not resolve host"), and no Terms or Privacy Policy text exists
//  anywhere in this repository. Registering the domain and writing the policy
//  content are product/legal decisions, not code — see P1-AUTH-06 and
//  P7-PRIVACY-05 in docs/03-progress.md.
//
//  This file therefore models "the documents are not published" as a fact the
//  compiler can see, instead of as four URLs that happen to 404. The previous
//  shape returned a non-optional `URL` for every document, so every call site
//  looked correct, compiled clean, and silently opened Safari on a DNS error —
//  the worst available failure for a link an App Store reviewer will tap.
//

import Foundation

/// URLs for the user-facing legal documents.
public enum AstraLegal {
    /// The marketing/legal host. **Not registered.** This and `isPublished`
    /// below are the only two lines that change when the real domain goes
    /// live; every URL and every call site follows from them.
    private static let host = "https://astrastyle.app"

    /// Whether `host` resolves *and* the documents at the paths below have
    /// actually been published.
    ///
    /// `false` today, deliberately. Flip it to `true` in the same change that
    /// registers the domain and publishes the documents — not before. While it
    /// is `false` every accessor below returns `nil`, which forces each call
    /// site to handle "no document yet" explicitly rather than presenting a
    /// dead link as a live one.
    public static let isPublished = false

    /// Terms of Service. Spec §29 requires these to prohibit uploading images
    /// of people without their permission — load-bearing for Style Studio.
    public static var termsURL: URL? { resolved("/terms") }

    /// Privacy Policy. Spec §29 requires it to describe image processing, model
    /// providers, retention, and affiliate relationships.
    public static var privacyURL: URL? { resolved("/privacy") }

    /// How to request deletion of an account and all associated data (§15).
    public static var dataDeletionURL: URL? { resolved("/privacy/delete") }

    /// Affiliate disclosure (§17: relationships must be clearly disclosed).
    public static var affiliateDisclosureURL: URL? { resolved("/affiliate-disclosure") }

    /// `nil` while unpublished.
    ///
    /// Deliberately silent rather than `assertionFailure`-ing: the loud failure
    /// here is a *compile-time* one. Every call site has to handle `nil`, so
    /// "we forgot the documents don't exist" cannot be written at all, which is
    /// stronger than a runtime trap that only fires on the code path someone
    /// happened to exercise in Debug. `LegalDocumentAvailabilityTests` pins the
    /// invariant so the flag cannot be flipped without the URLs following.
    private static func resolved(_ path: String) -> URL? {
        guard isPublished else { return nil }
        return URL(string: host + path)
    }
}
