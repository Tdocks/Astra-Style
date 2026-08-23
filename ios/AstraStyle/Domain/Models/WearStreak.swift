//
//  WearStreak.swift
//  AstraStyle
//
//  Consecutive calendar days with any mark-worn (item or outfit). Not a
//  badge on closet_items.wear_count (ADR 0020).
//

import Foundation

public struct WearStreak: Equatable, Sendable {
    public var current: Int
    public var best: Int

    public init(current: Int, best: Int) {
        self.current = current
        self.best = best
    }
}

/// One `wear_days` row. `worn_on` is a Postgres `date` (`YYYY-MM-DD`).
public struct WearDay: Identifiable, Hashable, Sendable {
    public var userID: UUID
    public var wornOn: Date

    public var id: String { "\(userID.uuidString)-\(wornOn.timeIntervalSince1970)" }

    public init(userID: UUID, wornOn: Date) {
        self.userID = userID
        self.wornOn = wornOn
    }
}

extension WearDay: Codable {
    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case wornOn = "worn_on"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        let raw = try container.decode(String.self, forKey: .wornOn)
        let prefix = String(raw.prefix(10))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: prefix) else {
            throw DecodingError.dataCorruptedError(
                forKey: .wornOn,
                in: container,
                debugDescription: "wear_days.worn_on must be YYYY-MM-DD"
            )
        }
        wornOn = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        try container.encode(formatter.string(from: wornOn), forKey: .wornOn)
    }
}

public enum WearStreakCalculator: Sendable {
    /// Current streak includes today if worn today, otherwise yesterday
    /// (the day is not over). Best is the longest consecutive run in `days`.
    public static func stats(
        days: some Sequence<Date>,
        today: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> WearStreak {
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let starts = Set(days.map { utc.startOfDay(for: $0) })
        let todayStart = utc.startOfDay(for: today)
        let best = longestRun(in: starts, calendar: utc)

        guard let yesterday = utc.date(byAdding: .day, value: -1, to: todayStart) else {
            return WearStreak(current: 0, best: best)
        }

        let cursorStart: Date
        if starts.contains(todayStart) {
            cursorStart = todayStart
        } else if starts.contains(yesterday) {
            cursorStart = yesterday
        } else {
            return WearStreak(current: 0, best: best)
        }

        var current = 0
        var cursor = cursorStart
        while starts.contains(cursor) {
            current += 1
            guard let previous = utc.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return WearStreak(current: current, best: max(best, current))
    }

    private static func longestRun(in days: Set<Date>, calendar: Calendar) -> Int {
        let sorted = days.sorted()
        guard let first = sorted.first else { return 0 }
        var best = 1
        var run = 1
        var previous = first
        for day in sorted.dropFirst() {
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            if gap == 1 {
                run += 1
                best = max(best, run)
            } else if gap != 0 {
                run = 1
            }
            previous = day
        }
        return best
    }
}
