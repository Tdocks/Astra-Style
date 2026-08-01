//
//  CurrencyFormattingTests.swift
//  AstraStyleTests
//
//  Pins the money-formatting rules after folding the old
//  `MeasurementFormatting` helpers in: USD labelling fallback (never the
//  device locale), and the "/ wear" sentence used by Closet metrics.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("CurrencyFormatting")
struct CurrencyFormattingTests {

    @Test("Nil currency code labels with USD, not the device locale")
    func nilCurrencyUsesUSDFallback() {
        let formatted = CurrencyFormatting.formattedCostPerWear(
            Decimal(42),
            currencyCode: nil
        )
        #expect(formatted.contains("42"))
        #expect(formatted.contains("/ wear"))
        // The amount is labelled as USD even on a non-US device locale —
        // that is the whole point of rejecting Locale.current.
        let usdOnly = CurrencyFormatting.formatted(Decimal(42), code: "USD")
        #expect(formatted.hasPrefix(usdOnly) || formatted.contains(usdOnly))
    }

    @Test("Nil amount is an honest placeholder, not $0 / wear")
    func nilAmountIsPlaceholder() {
        let formatted = CurrencyFormatting.formattedCostPerWear(nil, currencyCode: "USD")
        #expect(formatted == "Not enough wears yet")
    }

    @Test("Blank currency codes normalize to the USD fallback")
    func blankCurrencyNormalizesToUSD() {
        #expect(CurrencyFormatting.normalizedCurrencyCode("  ") == "USD")
        #expect(CurrencyFormatting.normalizedCurrencyCode("usd") == "USD")
        #expect(CurrencyFormatting.normalizedCurrencyCode("GBP") == "GBP")
    }
}
