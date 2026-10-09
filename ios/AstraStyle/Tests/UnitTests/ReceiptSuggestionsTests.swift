import Foundation
import Testing
@testable import AstraStyle

@Suite("Receipt OCR suggestions")
struct ReceiptSuggestionsTests {
    @Test("Explicit total and ISO date become editable suggestions")
    func explicitMetadata() {
        let result = ReceiptSuggestions.parse(["Example Shop", "2026-10-08", "Subtotal USD 45.00", "Total USD 50.00"])
        #expect(result.retailer == "Example Shop")
        #expect(result.total == Decimal(50))
        #expect(result.currency == "USD")
        #expect(result.date != nil)
        #expect(result.text.contains("Subtotal"))
    }
    @Test("Ambiguous totals, locale dates and dollar currency stay unknown")
    func ambiguousMetadata() {
        let result = ReceiptSuggestions.parse(["Total $50.00", "Total $60.00", "08/10/2026"])
        #expect(result.total == nil)
        #expect(result.date == nil)
        #expect(result.retailer == nil)
        #expect(ReceiptSuggestions.parse(["Total $50.00"]).currency == nil)
    }
    @Test("Refund and grouped amounts cannot become partial positive prices")
    func invalidAmounts() {
        for total in ["Total -50.00", "Total -$50.00", "Total EUR 1,299.00", "Subtotal 50.00"] {
            #expect(ReceiptSuggestions.parse([total]).total == nil)
        }
    }
    @Test("Label text does not invent a purchase price")
    func labelText() {
        let result = ReceiptSuggestions.parse(["100% COTTON", "SIZE M", "Wash at 30"])
        #expect(result.total == nil)
        #expect(result.date == nil)
        #expect(result.text.contains("SIZE M"))
    }
}
