import Foundation
import Testing
@testable import AstraStyle

@Suite("Current season resolver")
struct CurrentSeasonResolverTests {
    @Test("uses the calendar season for a northern location")
    func northernHemisphere() throws {
        let calendar = utcCalendar()
        #expect(CurrentSeasonResolver.season(at: try date(month: 1, calendar: calendar), latitude: 40, calendar: calendar) == .winter)
        #expect(CurrentSeasonResolver.season(at: try date(month: 4, calendar: calendar), latitude: 40, calendar: calendar) == .spring)
        #expect(CurrentSeasonResolver.season(at: try date(month: 7, calendar: calendar), latitude: 40, calendar: calendar) == .summer)
        #expect(CurrentSeasonResolver.season(at: try date(month: 10, calendar: calendar), latitude: 40, calendar: calendar) == .fall)
    }

    @Test("reverses seasons for a southern location")
    func southernHemisphere() throws {
        let calendar = utcCalendar()
        #expect(CurrentSeasonResolver.season(at: try date(month: 1, calendar: calendar), latitude: -34, calendar: calendar) == .summer)
        #expect(CurrentSeasonResolver.season(at: try date(month: 4, calendar: calendar), latitude: -34, calendar: calendar) == .fall)
        #expect(CurrentSeasonResolver.season(at: try date(month: 7, calendar: calendar), latitude: -34, calendar: calendar) == .winter)
        #expect(CurrentSeasonResolver.season(at: try date(month: 10, calendar: calendar), latitude: -34, calendar: calendar) == .spring)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func date(month: Int, calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: 15)))
    }
}
