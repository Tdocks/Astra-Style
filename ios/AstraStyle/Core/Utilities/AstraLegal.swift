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
//  ⚠️ THE DOCUMENTS ARE WRITTEN BUT NOT PUBLISHED. `isPublished` is still
//  `false` and every accessor still returns `nil`. What changed on 2026-07-31
//  is where they will live and what is left to do:
//
//    • The four documents now exist in the repository under `legal/` — a
//      Privacy Policy, Terms of Service, data-deletion instructions and an
//      affiliate disclosure, drafted from the actual schema rather than a
//      template.
//    • They are UNREVIEWED DRAFTS carrying visible `[[NEEDS INPUT]]`
//      placeholders: legal entity name, registered address, governing law,
//      contact addresses, and a flagged biometric-privacy question (face
//      images plus body measurements — see `legal/README.md`) that needs a
//      lawyer, not an engineer.
//    • The `legal` storage bucket exists and is public
//      (`20260731120000_legal_documents_bucket.sql`). Nothing has been
//      uploaded to it.
//
//  Publishing an unreviewed privacy policy is worse than publishing none: the
//  unpublished state is honest, and the published one makes promises nobody
//  has checked. So the flag stays down until the placeholders are filled and
//  the drafts are reviewed. Flip it in that same change.
//
//  This file models "the documents are not published" as a fact the compiler
//  can see, instead of as four URLs that happen to 404. The previous shape
//  returned a non-optional `URL` for every document, so every call site looked
//  correct, compiled clean, and silently opened Safari on a DNS error — the
//  worst available failure for a link an App Store reviewer will tap.
//

import Foundation

/// URLs for the user-facing legal documents.
public enum AstraLegal {
    /// Where the documents are served from.
    ///
    /// Supabase Storage rather than a domain, because **there is no domain**.
    /// `astrastyle.app` is unregistered — RDAP returned 404 on 2026-07-31,
    /// meaning nobody owns it, so the links were dead because it was never
    /// bought rather than because it lapsed. An App Store submission needs a
    /// working privacy-policy URL, and the project already pays for storage
    /// that serves one over HTTPS today at no extra cost.
    ///
    /// It is not a pretty URL, and it does not need to be: it is a destination
    /// a user reaches by tapping "Privacy Policy", not something anyone types.
    /// Moving to a custom domain later changes this one line — which is the
    /// entire reason the host is a constant and the paths are relative to it.
    private static let host = "https://anutsdzbxycaavmmkewo.supabase.co"

    /// Public-object prefix for the `legal` bucket. Separate from `host` so a
    /// move to a custom domain replaces the host alone and leaves the document
    /// filenames untouched.
    private static let prefix = "/storage/v1/object/public/legal"

    /// Whether the documents at the paths below have actually been published.
    ///
    /// `false` today, deliberately — the bucket is empty and the drafts are
    /// unreviewed. Flip it in the same change that fills every
    /// `[[NEEDS INPUT]]` placeholder and uploads the reviewed documents; not
    /// before. While it is `false` every accessor returns `nil`, which forces
    /// each call site to handle "no document yet" explicitly rather than
    /// presenting a dead link as a live one.
    public static let isPublished = false

    /// Terms of Service. Spec §29 requires these to prohibit uploading images
    /// of people without their permission — load-bearing for Style Studio.
    public static var termsURL: URL? { resolved("terms.html") }

    /// Privacy Policy. Spec §29 requires it to describe image processing, model
    /// providers, retention, and affiliate relationships.
    public static var privacyURL: URL? { resolved("privacy.html") }

    /// How to request deletion of an account and all associated data (§15).
    public static var dataDeletionURL: URL? { resolved("data-deletion.html") }

    /// Affiliate disclosure (§17: relationships must be clearly disclosed).
    public static var affiliateDisclosureURL: URL? { resolved("affiliate-disclosure.html") }

    /// `nil` while unpublished.
    ///
    /// Deliberately silent rather than `assertionFailure`-ing: the loud failure
    /// here is a *compile-time* one. Every call site has to handle `nil`, so
    /// "we forgot the documents don't exist" cannot be written at all, which is
    /// stronger than a runtime trap that only fires on the code path someone
    /// happened to exercise in Debug. `LegalDocumentAvailabilityTests` pins the
    /// invariant so the flag cannot be flipped without the URLs following.
    private static func resolved(_ filename: String) -> URL? {
        guard isPublished else { return nil }
        return URL(string: host + prefix + "/" + filename)
    }
}
