//
//  DateAndWeatherFormatting.swift
//  AstraStyle
//
//  Shared date and weather presentation helpers for the Home Daily Brief
//  header (spec §6.11 "Weather and location", "Schedule summary") and
//  outfit weather ranges (spec §6.12).
//

import Foundation

public enum AstraDateFormatting {
    /// "Good morning, Marcus." / "Good afternoon, Marcus." / "Good evening,
    /// Marcus." — the Daily Brief greeting (spec §6.11).
    public static func timeOfDayGreeting(for date: Date = .now, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 0..<12: return String(localized: "Good morning", comment: "Daily Brief greeting")
        case 12..<18: return String(localized: "Good afternoon", comment: "Daily Brief greeting")
        default: return String(localized: "Good evening", comment: "Daily Brief greeting")
        }
    }

    /// "Tuesday, June 3" — used under the Daily Brief header.
    public static func longWeekdayAndDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// "3 events today" schedule summary chip (spec §6.11).
    public static func scheduleSummary(eventCount: Int) -> String {
        eventCount == 0
            ? String(localized: "No events today", comment: "Schedule summary, zero events")
            : String(localized: "^[\(eventCount) event](inflect: true) today", comment: "Schedule summary with event count")
    }
}

public enum AstraWeatherFormatting {
    /// "68°–74°F" range formatting used on the Home header and outfit
    /// weather range (spec §6.12 "Weather range"). Inputs are always in
    /// Fahrenheit — `WeatherSnapshot`'s storage convention, set by
    /// `LiveWeatherService` regardless of the user's display preference —
    /// and are converted here to whichever unit `units` calls for.
    public static func temperatureRange(low fahrenheitLow: Double, high fahrenheitHigh: Double, units: UnitsPreference) -> String {
        let lowFormatted = displayMeasurement(fahrenheit: fahrenheitLow, units: units)
        let highFormatted = displayMeasurement(fahrenheit: fahrenheitHigh, units: units)
        return "\(lowFormatted)–\(highFormatted)"
    }

    public static func singleTemperature(_ fahrenheitValue: Double, units: UnitsPreference) -> String {
        displayMeasurement(fahrenheit: fahrenheitValue, units: units)
    }

    private static func displayMeasurement(fahrenheit: Double, units: UnitsPreference) -> String {
        let measurement = Measurement(value: fahrenheit, unit: UnitTemperature.fahrenheit)
        let displayUnit: UnitTemperature = units == .imperial ? .fahrenheit : .celsius
        return measurement.converted(to: displayUnit)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
