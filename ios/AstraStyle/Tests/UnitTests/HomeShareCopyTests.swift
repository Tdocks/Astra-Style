//
//  HomeShareCopyTests.swift
//  AstraStyleTests
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Home share is name plus why, never invented copy")
struct HomeShareCopyTests {
    @Test("Name only when why is missing")
    func nameOnlyWhenWhyMissing() {
        #expect(HomeShareCopy.shareText(name: "Navy knit", why: nil) == "Navy knit")
    }

    @Test("Blank why is treated as absent")
    func blankWhyIsAbsent() {
        #expect(HomeShareCopy.shareText(name: "Navy knit", why: "") == "Navy knit")
        #expect(HomeShareCopy.shareText(name: "Navy knit", why: "  ") == "Navy knit")
    }

    @Test("Appends the why-copy Home already showed")
    func appendsWhy() {
        #expect(
            HomeShareCopy.shareText(name: "Navy knit", why: "The knit is the right weight for 62°.")
                == "Navy knit\n\nThe knit is the right weight for 62°."
        )
    }
}
