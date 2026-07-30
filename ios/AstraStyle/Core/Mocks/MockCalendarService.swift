//
//  MockCalendarService.swift
//  AstraStyle
//
//  In-memory `CalendarService` for previews/tests (spec §31).
//

import Foundation

public struct MockCalendarService: CalendarService {
    public var permissionGranted: Bool
    public var events: [Occasion]

    public init(permissionGranted: Bool = true, events: [Occasion]? = nil) {
        self.permissionGranted = permissionGranted
        self.events = events ?? [
            Occasion(
                id: UUID(),
                userID: SampleData.userID,
                title: "Client meeting — Q3 roadmap review",
                startsAt: Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: .now) ?? .now,
                endsAt: Calendar.current.date(bySettingHour: 11, minute: 30, second: 0, of: .now),
                location: "Downtown office",
                dressCode: .businessCasual,
                source: .calendarSync
            ),
            Occasion(
                id: UUID(),
                userID: SampleData.userID,
                title: "Dinner with Sarah",
                startsAt: Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: .now) ?? .now,
                endsAt: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: .now),
                location: "Lilia, Williamsburg",
                dressCode: .casual,
                source: .calendarSync
            )
        ]
    }

    public func requestAccessIfNeeded() async -> Bool { permissionGranted }

    public func fetchUpcomingEvents(in range: DateInterval, userID: UUID) async -> [Occasion] {
        guard permissionGranted else { return [] }
        return events.filter { range.contains($0.startsAt) }
    }
}
