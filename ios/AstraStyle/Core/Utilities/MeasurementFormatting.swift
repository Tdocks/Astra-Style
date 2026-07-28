//
//  MeasurementFormatting.swift
//  AstraStyle
//
//  Converts the raw `Double` measurement fields on `BodyProfile`
//  (spec §9 — stored in whichever unit `Profile.units` indicates) into
//  user-facing strings, and formats currency for prices, all Dynamic-Type
//  and locale safe by going through `Foundation.FormatStyle` rather than
//  hand-built strings.
//

import Foundation

public enum MeasurementFormatting {
    /// Formats a length value (height, chest, waist, inseam, neck) stored
    /// per `UnitsPreference`.
    public static func formattedLength(_ value: Double?, units: UnitsPreference) -> String? {
        guard let value else { return nil }
        let measurement: Measurement<UnitLength> = units == .imperial
            ? Measurement(value: value, unit: .inches)
            : Measurement(value: value, unit: .centimeters)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .personHeight))
    }

    /// Height specifically renders as feet+inches in imperial locales
    /// (spec §6.6 "Height"), which `.personHeight` usage already handles
    /// for `UnitLength`.
    public static func formattedHeight(_ value: Double?, units: UnitsPreference) -> String? {
        formattedLength(value, units: units)
    }

    public static func formattedWeight(_ value: Double?, units: UnitsPreference) -> String? {
        guard let value else { return nil }
        let measurement: Measurement<UnitMass> = units == .imperial
            ? Measurement(value: value, unit: .pounds)
            : Measurement(value: value, unit: .kilograms)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .personWeight))
    }

    public static func formattedPrice(_ value: Decimal?, currencyCode: String?) -> String? {
        guard let value else { return nil }
        return value.formatted(.currency(code: currencyCode ?? Locale.current.currency?.identifier ?? "USD"))
    }

    /// e.g. "$42 / wear" for the closet item detail and Product Decision
    /// Page (spec §6.15, §6.19).
    public static func formattedCostPerWear(_ value: Decimal?, currencyCode: String?) -> String {
        guard let value, let formattedPrice = formattedPrice(value, currencyCode: currencyCode) else {
            return String(localized: "Not enough wears yet", comment: "Cost-per-wear placeholder")
        }
        return String(localized: "\(formattedPrice) / wear", comment: "Cost-per-wear value, e.g. $42 / wear")
    }
}
