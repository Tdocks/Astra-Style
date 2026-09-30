import Foundation

@MainActor
public final class MockReminderService: ReminderService {
    private var storedPreferences = ReminderPreferences()
    public private(set) var scheduledPackingDates: [Date] = []

    public init() {}

    public func authorization() async -> ReminderAuthorization { .authorized }
    public func preferences() -> ReminderPreferences { storedPreferences }

    public func setEnabled(_ kind: ReminderKind, enabled: Bool) async throws -> ReminderAuthorization {
        if enabled {
            storedPreferences.enabledKinds.insert(kind)
        } else {
            storedPreferences.enabledKinds.remove(kind)
        }
        return .authorized
    }

    public func setMorningTime(hour: Int, minute: Int) async throws {
        storedPreferences.morningHour = min(max(hour, 0), 23)
        storedPreferences.morningMinute = min(max(minute, 0), 59)
    }

    public func refreshOccasionReminders(eventDates: [Date]) async {}
    public func schedulePackingReminder(at date: Date) async {
        guard storedPreferences.isEnabled(.packingTrip) else { return }
        scheduledPackingDates.append(date)
    }
}
