//
//  ProductDecisionCopyTests.swift
//  AstraStyleTests
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Product decision share is skip/wait only")
struct ProductDecisionCopyTests {
    @Test("Skip shares the refusal plus the garment")
    func skipSharesRefusal() {
        #expect(
            ProductDecisionCopy.shareText(verdict: .skip, garmentName: "Black bomber")
                == "Astra said skip: Black bomber"
        )
    }

    @Test("Wait shares the refusal plus the garment")
    func waitSharesRefusal() {
        #expect(
            ProductDecisionCopy.shareText(verdict: .waitForSale, garmentName: "Black bomber")
                == "Astra said wait: Black bomber"
        )
    }

    @Test("Buy and consider do not produce share text")
    func buyAndConsiderDoNotShare() {
        #expect(ProductDecisionCopy.shareText(verdict: .buy, garmentName: "Black bomber") == nil)
        #expect(ProductDecisionCopy.shareText(verdict: .consider, garmentName: "Black bomber") == nil)
    }

    @Test("Skip with no name is still a refusal, not a CTA")
    func skipWithoutName() {
        #expect(ProductDecisionCopy.shareText(verdict: .skip, garmentName: nil) == "Astra said skip")
        #expect(ProductDecisionCopy.shareText(verdict: .skip, garmentName: "  ") == "Astra said skip")
    }
}
