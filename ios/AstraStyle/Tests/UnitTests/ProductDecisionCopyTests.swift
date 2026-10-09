//
//  ProductDecisionCopyTests.swift
//  AstraStyleTests
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Product decision share is skip/wait only")
struct ProductDecisionCopyTests {
    @Test("A nullable catalog retailer does not make the entire shared catalog fail to decode")
    func nullableRetailerDecodesWithoutFailingCatalogRow() throws {
        let json = """
            {
              "id":"11111111-1111-4111-8111-111111111111",
              "canonical_url":"https://example.com/item",
              "retailer":null,
              "brand":null,
              "name":"Test item",
              "category":"top",
              "price":null,
              "currency":"USD",
              "image_url":null,
              "affiliate_url":null,
              "availability":{},
              "attributes":{},
              "last_checked_at":null,
              "sponsored":null
            }
            """
        let candidate = try JSONDecoder().decode(ProductCandidate.self, from: Data(json.utf8))

        #expect(candidate.name == "Test item")
        #expect(candidate.retailer == nil)
    }

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
