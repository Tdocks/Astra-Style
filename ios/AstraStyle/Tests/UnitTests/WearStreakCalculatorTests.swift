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
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ ymd: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = utc
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: ymd)!
    }

    @Test("Worn today continues a run ending today")
    func currentIncludesToday() {
        let stats = WearStreakCalculator.stats(
            days: [day("2026-08-21"), day("2026-08-22"), day("2026-08-23")],
            today: day("2026-08-23"),
            calendar: utc
        )
        #expect(stats.current == 3)
        #expect(stats.best == 3)
    }

    @Test("A gap yesterday zeros current even if a long run exists")
    func gapZerosCurrent() {
        let stats = WearStreakCalculator.stats(
            days: [day("2026-08-01"), day("2026-08-02"), day("2026-08-20")],
            today: day("2026-08-23"),
            calendar: utc
        )
        #expect(stats.current == 0)
        #expect(stats.best == 2)
    }

    @Test("Worn yesterday still counts while today is unfinished")
    func yesterdayKeepsStreak() {
        let stats = WearStreakCalculator.stats(
            days: [day("2026-08-21"), day("2026-08-22")],
            today: day("2026-08-23"),
            calendar: utc
        )
        #expect(stats.current == 2)
        #expect(stats.best == 2)
    }

    @Test("Empty history is a zero streak, not a wear_count fallback")
    func emptyIsZero() {
        let stats = WearStreakCalculator.stats(days: [], today: day("2026-08-23"), calendar: utc)
        #expect(stats == WearStreak(current: 0, best: 0))
    }
}
