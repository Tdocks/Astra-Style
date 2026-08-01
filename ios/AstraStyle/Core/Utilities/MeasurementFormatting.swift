//
//  MeasurementFormatting.swift
//  AstraStyle
//
//  Converts the raw `Double` measurement fields on `BodyProfile`
//  (spec §9 — stored in whichever unit `Profile.units` indicates) into
//  user-facing strings, Dynamic-Type and locale safe by going through
//  `Foundation.FormatStyle` rather than hand-built strings.
//
//  Money formatting lives in `CurrencyFormatting` — do not add a second
//  spelling here. The old helpers used the device locale as a currency
//  fallback, which quietly relabelled amounts; that rule is rejected.
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
}
