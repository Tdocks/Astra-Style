//
//  WearStreakCalculatorTests.swift
//  AstraStyleTests
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Wear streak is consecutive calendar days, not wear_count")
struct WearStreakCalculatorTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func day(_ ymd: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = utc
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        return try #require(formatter.date(from: ymd))
    }

    @Test("Worn today continues a run ending today")
    func currentIncludesToday() throws {
        let stats = WearStreakCalculator.stats(
            days: [try day("2026-08-21"), try day("2026-08-22"), try day("2026-08-23")],
            today: try day("2026-08-23"),
            calendar: utc
        )
        #expect(stats.current == 3)
        #expect(stats.best == 3)
    }

    @Test("A gap yesterday zeros current even if a long run exists")
    func gapZerosCurrent() throws {
        let stats = WearStreakCalculator.stats(
            days: [try day("2026-08-01"), try day("2026-08-02"), try day("2026-08-20")],
            today: try day("2026-08-23"),
            calendar: utc
        )
        #expect(stats.current == 0)
        #expect(stats.best == 2)
    }

    @Test("Worn yesterday still counts while today is unfinished")
    func yesterdayKeepsStreak() throws {
        let stats = WearStreakCalculator.stats(
            days: [try day("2026-08-21"), try day("2026-08-22")],
            today: try day("2026-08-23"),
            calendar: utc
        )
        #expect(stats.current == 2)
        #expect(stats.best == 2)
    }

    @Test("Empty history is a zero streak, not a wear_count fallback")
    func emptyIsZero() throws {
        let stats = WearStreakCalculator.stats(days: [], today: try day("2026-08-23"), calendar: utc)
        #expect(stats == WearStreak(current: 0, best: 0))
    }
}
