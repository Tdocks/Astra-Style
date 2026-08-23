//
//  ReferralCopyTests.swift
//  AstraStyleTests
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("One-guy referral copy")
struct ReferralCopyTests {
    @Test("Share names the code and the job, not a dashboard")
    func shareIncludesCode() {
        let text = ReferralCopy.shareText(code: "ASTRA001")
        #expect(text.contains("ASTRA001"))
        #expect(text.contains("hate shopping"))
    }

    @Test("Missing code still names the product")
    func missingCode() {
        #expect(ReferralCopy.shareText(code: nil).contains("Astra Style"))
    }
}

@Suite("Profile referral apply")
@MainActor
struct ProfileReferralViewModelTests {
    @Test("Apply stamps referredAlready")
    func applySucceeds() async {
        let model = ProfileReferralViewModel(profileRepository: MockProfileRepository())
        await model.onAppear()
        #expect(model.code == "ASTRA001")
        model.incomingCode = "OTHERGUY"
        await model.applyIncomingCode()
        #expect(model.referredAlready)
        #expect(model.note == "Code applied.")
    }
}
