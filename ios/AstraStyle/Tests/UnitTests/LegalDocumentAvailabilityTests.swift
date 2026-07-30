//
//  LegalDocumentAvailabilityTests.swift
//  AstraStyleTests
//
//  `AstraLegal` used to vend four non-optional `URL`s pointing at
//  `astrastyle.app`, a domain that has never been registered (NXDOMAIN,
//  verified 2026-07-30). Two of them are rendered on the pre-auth welcome
//  screen, so tapping either opened Safari on a DNS error — a dead control
//  that looked alive, and an App Store review blocker (P1-AUTH-06,
//  P7-PRIVACY-05).
//
//  The fix is a single `isPublished` flag and optional URLs, so the absence is
//  a fact the compiler enforces at every call site. These tests pin that
//  relationship in both directions, so the flag cannot be flipped as a
//  cosmetic change and the URLs cannot quietly become non-optional again.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Legal documents are not claimed to exist before they do")
struct LegalDocumentAvailabilityTests {

    @Test("Every legal URL is nil exactly when the documents are unpublished")
    func urlsTrackTheFlag() {
        let urls = [
            AstraLegal.termsURL,
            AstraLegal.privacyURL,
            AstraLegal.dataDeletionURL,
            AstraLegal.affiliateDisclosureURL
        ]
        if AstraLegal.isPublished {
            #expect(urls.allSatisfy { $0 != nil }, "isPublished is true but a document has no URL")
            #expect(
                urls.compactMap { $0?.scheme }.allSatisfy { $0 == "https" },
                "A legal document must be served over https"
            )
        } else {
            #expect(
                urls.allSatisfy { $0 == nil },
                "A URL was vended for a document that has not been published"
            )
        }
    }

    /// Deliberately asserts today's state rather than a tautology. When the
    /// domain is registered and the documents are written, this test fails —
    /// and the fix is to update it in the same change, which is exactly the
    /// prompt we want at that moment. Until then it is the one place in the
    /// test suite that records "the legal documents do not exist" as a
    /// checked fact rather than a comment.
    @Test("The documents are still unpublished — update this test when they ship")
    func documentsAreStillUnpublished() {
        #expect(
            AstraLegal.isPublished == false,
            """
            AstraLegal.isPublished is true. If the domain is registered and Terms/Privacy \
            are actually live, update this test and P1-AUTH-06 / P7-PRIVACY-05 in \
            docs/03-progress.md.
            """
        )
    }
}
