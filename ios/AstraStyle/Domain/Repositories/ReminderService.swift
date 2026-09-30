import Foundation

public enum ReminderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case dailyOutfit
    case upcomingOccasion
    case laundry
    case monthlyReview
    case packingTrip

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dailyOutfit: "Daily outfit"
        case .upcomingOccasion: "Calendar occasions"
        case .laundry: "Closet care"
        case .monthlyReview: "Monthly review"
        case .packingTrip: "Packing trip"
        }
    }

    public var description: String {
        switch self {
        case .dailyOutfit: "A morning reminder to check today's look."
        case .upcomingOccasion: "A private reminder before an upcoming calendar event."
        case .laundry: "A gentle evening reminder to keep closet availability current."
        case .monthlyReview: "A reminder when your monthly style review is ready."
        case .packingTrip: "A reminder the day before a planned trip."
        }
    }
}

public enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

public struct ReminderPreferences: Codable, Sendable, Equatable {
    public var enabledKinds: Set<ReminderKind>
    public var morningHour: Int
    public var morningMinute: Int

    public init(enabledKinds: Set<ReminderKind> = [], morningHour: Int = 7, morningMinute: Int = 30) {
        self.enabledKinds = enabledKinds
        self.morningHour = min(max(morningHour, 0), 23)
        self.morningMinute = min(max(morningMinute, 0), 59)
    }

    public func isEnabled(_ kind: ReminderKind) -> Bool {
        enabledKinds.contains(kind)
    }
}

@MainActor
public protocol ReminderService: Sendable {
    func authorization() async -> ReminderAuthorization
    func preferences() -> ReminderPreferences
    func setEnabled(_ kind: ReminderKind, enabled: Bool) async throws -> ReminderAuthorization
    func setMorningTime(hour: Int, minute: Int) async throws
    func refreshOccasionReminders(eventDates: [Date]) async
    func schedulePackingReminder(at date: Date) async
}
