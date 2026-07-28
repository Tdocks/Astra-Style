//
//  LiveCalendarService.swift
//  AstraStyle
//
//  EventKit-backed `CalendarService` (spec §7 "Calendar: when enabling
//  occasion-aware recommendations", §6.8). Maps `EKEvent` to the domain
//  `Occasion` type; a best-effort `dressCode` guess from the event title
//  is left to the server (spec §14's outfit generation call receives the
//  raw event and infers dress code from title/location itself) — this
//  layer only supplies `nil` and lets the user set it manually if desired.
//

import EventKit
import Foundation

public final class LiveCalendarService: CalendarService, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func requestAccessIfNeeded() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            do {
                return try await store.requestFullAccessToEvents()
            } catch {
                return false
            }
        default:
            return false
        }
    }

    public func fetchUpcomingEvents(in range: DateInterval, userID: UUID) async -> [Occasion] {
        guard await requestAccessIfNeeded() else { return [] }

        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        let events = store.events(matching: predicate)

        return events.map { event in
            Occasion(
                id: UUID(astraDeterministicFrom: event.eventIdentifier ?? UUID().uuidString),
                userID: userID,
                title: event.title ?? String(localized: "Untitled Event"),
                startsAt: event.startDate,
                endsAt: event.endDate,
                location: event.location,
                dressCode: nil,
                source: .calendarSynced,
                calendarEventIdentifier: event.eventIdentifier
            )
        }
    }
}
