//
//  CurrencyFormatting.swift
//  AstraStyle
//
//  Money to string, plus the single rule for what to do when a row does
//  not say which money it is. Lives in `Core/Utilities/` for the same
//  reason `MeasurementFormatting.swift` and `DateAndWeatherFormatting.swift`
//  do: formatting is presentation logic that unrelated screens need, and a
//  private copy inside any one of them is a copy the others drift from.
//
//  PROMOTION COMPLETE — READ THIS BEFORE ADDING A SECOND SPELLING.
//  `ClosetItemDetailCopy` (Features/Closet/ViewModels/ClosetItemDetailViewModel.swift)
//  used to carry `currency(_:code:)` and `fallbackCurrencyCode`, under its
//  own note saying both belonged here and should MOVE — not be copied — the
//  moment a second surface needed them. The closet metrics row was that
//  second surface. Both members are now deleted from there and its call
//  sites read this file, so there is exactly one answer in the codebase to
//  "how is a garment's price written down".
//
//  The item detail screen picked up one behaviour change on the way in,
//  and it is recorded at the call site rather than only here: it now reads
//  a currency code through `normalizedCurrencyCode` instead of a bare
//  `??`, so a row storing `"usd"` or `"  "` reads the same on that screen
//  as it does in the closet total.
//
//  `MeasurementFormatting` used to carry a second money spelling whose
//  missing-code fallback was the DEVICE LOCALE's currency. That is the
//  exact rule `fallbackCurrencyCode` exists to rule out. Those helpers are
//  gone; cost-per-wear lives here and uses the USD labelling fallback.
//

import Foundation

public enum CurrencyFormatting {

    /// How a `nil` or blank `closet_items.currency` is read.
    ///
    /// USD rather than the device locale's currency. Formerly
    /// `ClosetItemDetailCopy.fallbackCurrencyCode`, and now the only copy,
    /// so that one jacket cannot read as $180 on the item screen and £180
    /// inside a closet total:
    /// the number came from somewhere, and relabelling a recorded amount
    /// because of where the phone is would be a quiet, confident lie about
    /// what he paid.
    ///
    /// This is a LABELLING fallback and never a conversion. Nothing in this
    /// file, and nothing that calls it, converts between currencies.
    public static let fallbackCurrencyCode = "USD"

    /// The bucket an amount belongs to, given whatever the row stored.
    ///
    /// Trimmed and uppercased so `"usd"`, `"USD "` and `"USD"` are one
    /// currency rather than three. `closet_items.currency` is free text
    /// filled in by an importer, a form, and eventually a scan pipeline, so
    /// all three spellings will exist — and three buckets for one currency
    /// would report a mixed-currency closet that is not mixed, which is the
    /// exact failure the split-by-currency total exists to avoid.
    public static func normalizedCurrencyCode(_ raw: String?) -> String {
        guard let raw else { return fallbackCurrencyCode }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? fallbackCurrencyCode : trimmed
    }

    /// Deliberately does not force two decimal places. `.currency(code:)`
    /// already applies each currency's own minor-unit count, and a
    /// hardcoded `.fractionLength(2)` would render ¥1,200 as ¥1,200.00.
    public static func formatted(_ amount: Decimal, code: String) -> String {
        amount.formatted(.currency(code: code))
    }

    /// e.g. "$42 / wear" for closet metrics and item detail (spec §6.15).
    ///
    /// A nil amount means "not enough wears yet" rather than "$0 / wear".
    /// A nil or blank currency code uses `fallbackCurrencyCode` (USD) — never
    /// the device locale — so a London phone does not quietly relabel a
    /// dollar amount as pounds.
    public static func formattedCostPerWear(_ value: Decimal?, currencyCode: String?) -> String {
        guard let value else {
            return String(localized: "Not enough wears yet", comment: "Cost-per-wear placeholder")
        }
        let code = normalizedCurrencyCode(currencyCode)
        let price = formatted(value, code: code)
        return String(localized: "\(price) / wear", comment: "Cost-per-wear value, e.g. $42 / wear")
    }
}
