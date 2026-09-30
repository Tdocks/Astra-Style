import Foundation
import UserNotifications

@MainActor
public final class LiveReminderService: ReminderService {
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let preferencesKey = "astra.reminderPreferences"
    private var upcomingEventDates: [Date] = []

    public init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
    }

    public func authorization() async -> ReminderAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    public func preferences() -> ReminderPreferences {
        guard let data = defaults.data(forKey: preferencesKey),
              let preferences = try? JSONDecoder().decode(ReminderPreferences.self, from: data) else {
            return ReminderPreferences()
        }
        return preferences
    }

    public func setEnabled(_ kind: ReminderKind, enabled: Bool) async throws -> ReminderAuthorization {
        var preferences = preferences()
        if enabled {
            var status = await authorization()
            if status == .notDetermined {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                status = granted ? .authorized : .denied
            }
            guard status == .authorized else { return status }
            preferences.enabledKinds.insert(kind)
        } else {
            preferences.enabledKinds.remove(kind)
        }
        save(preferences)
        await rescheduleRecurring(preferences)
        await refreshOccasionReminders(eventDates: upcomingEventDates)
        return await authorization()
    }

    public func setMorningTime(hour: Int, minute: Int) async throws {
        var preferences = preferences()
        preferences.morningHour = min(max(hour, 0), 23)
        preferences.morningMinute = min(max(minute, 0), 59)
        save(preferences)
        await rescheduleRecurring(preferences)
    }

    public func refreshOccasionReminders(eventDates: [Date]) async {
        upcomingEventDates = eventDates
        let preferences = preferences()
        let ids = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix("astra.occasion.") }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard preferences.isEnabled(.upcomingOccasion), await authorization() == .authorized else { return }

        for date in eventDates where date > .now.addingTimeInterval(60 * 30) {
            let leadTime: TimeInterval = date > .now.addingTimeInterval(60 * 60 * 24) ? 60 * 60 * 24 : 60 * 60
            let fireDate = date.addingTimeInterval(-leadTime)
            guard fireDate > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "An event is coming up"
            content.body = "Check your calendar and choose a look that fits the day."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                repeats: false
            )
            let identifier = "astra.occasion.\(Int(date.timeIntervalSince1970))"
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    public func schedulePackingReminder(at date: Date) async {
        guard preferences().isEnabled(.packingTrip), await authorization() == .authorized,
              let reminderDate = Calendar.current.date(byAdding: .day, value: -1, to: date),
              reminderDate > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your trip is coming up"
        content.body = "Open Astra Style to check your packing plan."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
            repeats: false
        )
        try? await center.add(UNNotificationRequest(
            identifier: "astra.packing.\(Int(date.timeIntervalSince1970))",
            content: content,
            trigger: trigger
        ))
    }

    private func rescheduleRecurring(_ preferences: ReminderPreferences) async {
        let recurringIDs = ["astra.daily", "astra.monthly", "astra.laundry"]
        center.removePendingNotificationRequests(withIdentifiers: recurringIDs)
        guard await authorization() == .authorized else { return }

        if preferences.isEnabled(.dailyOutfit) {
            await schedule(
                id: "astra.daily",
                title: "Today's look is ready",
                body: "Open Astra Style for an outfit that fits your day.",
                components: DateComponents(hour: preferences.morningHour, minute: preferences.morningMinute),
                repeats: true
            )
        }
        if preferences.isEnabled(.monthlyReview) {
            await schedule(
                id: "astra.monthly",
                title: "Your monthly review is ready",
                body: "See what you wore, added, and want to try next.",
                components: DateComponents(day: 1, hour: 9, minute: 0),
                repeats: true
            )
        }
        if preferences.isEnabled(.laundry) {
            await schedule(
                id: "astra.laundry",
                title: "A quick closet check",
                body: "Update laundry status to keep your outfit options current.",
                components: DateComponents(hour: 20, minute: 0),
                repeats: true
            )
        }
    }

    private func schedule(id: String, title: String, body: String, components: DateComponents, repeats: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func save(_ preferences: ReminderPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: preferencesKey)
    }
}
