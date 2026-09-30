//
//  ScheduleSnapshotBuilder.swift
//  AstraStyle
//
//  Creates the smallest calendar summary the recommendation service needs.
//  Calendar event names and locations are read on device only; the request
//  carries an event count and one inferred formality band.
//

import Foundation

public enum ScheduleSnapshotBuilder {
    public static func build(from events: [Occasion]) -> ScheduleSnapshot {
        let ordered = events.sorted { $0.startsAt < $1.startsAt }
        let formality = ordered.lazy.compactMap { event in
            event.dressCode.map(formality(for:)) ?? inferFormality(from: event.title)
        }.first
        let count = ordered.count
        let headline: String?
        if count == 0 {
            headline = nil
        } else if count == 1 {
            headline = String(localized: "One event coming up today", comment: "Calendar summary without event details")
        } else {
            headline = String(localized: "\(count) events coming up today", comment: "Calendar summary without event details")
        }
        return ScheduleSnapshot(eventCount: count, earliestFormalityLevel: formality, headline: headline)
    }

    public static func formality(for code: DressCode) -> FormalityLevel {
        switch code {
        case .ultraCasual: .veryCasual
        case .casual, .athletic: .casual
        case .smartCasual, .businessCasual: .balanced
        case .businessFormal, .formal: .formal
        case .blackTie: .veryFormal
        }
    }

    /// Conservative title keywords; unknown calendar titles stay unclassified.
    private static func inferFormality(from title: String) -> FormalityLevel? {
        let value = title.lowercased()
        if ["black tie", "gala", "wedding", "formal"].contains(where: { value.contains($0) }) { return .veryFormal }
        if ["interview", "client meeting", "presentation", "board meeting", "court"].contains(where: { value.contains($0) }) { return .formal }
        if ["meeting", "office", "work", "conference"].contains(where: { value.contains($0) }) { return .balanced }
        if ["date", "dinner", "restaurant", "drinks"].contains(where: { value.contains($0) }) { return .casual }
        if ["gym", "workout", "run", "practice"].contains(where: { value.contains($0) }) { return .veryCasual }
        return nil
    }
}
