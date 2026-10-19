import Foundation
import Testing
import UserNotifications
@testable import AstraStyle

@MainActor
struct LiveReminderServiceTests {
    @Test("Rejected scheduling does not persist a successful opt-in and can be retried")
    func rejectedOptIn() async throws {
        let scheduler = TestReminderScheduler()
        let defaults = try #require(UserDefaults(suiteName: "astra.reminder-test.\(UUID())"))
        let service = LiveReminderService(scheduler: scheduler, defaults: defaults)
        scheduler.failNextAdd = true
        do {
            _ = try await service.setEnabled(.dailyOutfit, enabled: true)
            Issue.record("Scheduling failure must reach the caller")
        } catch {}
        #expect(!service.preferences().isEnabled(.dailyOutfit))
        _ = try await service.setEnabled(.dailyOutfit, enabled: true)
        #expect(service.preferences().isEnabled(.dailyOutfit))
        #expect(scheduler.requests["astra.daily"] != nil)
        defaults.removeObject(forKey: "astra.reminderPreferences")
    }

    @Test("Failed time change retains preferences and restores the previous request")
    func rejectedTimeChange() async throws {
        let scheduler = TestReminderScheduler()
        let defaults = try #require(UserDefaults(suiteName: "astra.reminder-test.\(UUID())"))
        let service = LiveReminderService(scheduler: scheduler, defaults: defaults)
        _ = try await service.setEnabled(.dailyOutfit, enabled: true)
        scheduler.failNextAdd = true
        do {
            try await service.setMorningTime(hour: 10, minute: 15)
            Issue.record("Time scheduling failure must reach the caller")
        } catch {}
        #expect(service.preferences().morningHour == 7)
        let trigger = scheduler.requests["astra.daily"]?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 7)
        #expect(trigger?.dateComponents.minute == 30)
        defaults.removeObject(forKey: "astra.reminderPreferences")
    }

    @Test("Denied permission neither enables nor schedules a reminder")
    func deniedPermission() async throws {
        let scheduler = TestReminderScheduler()
        scheduler.status = .denied
        let defaults = try #require(UserDefaults(suiteName: "astra.reminder-test.\(UUID())"))
        let service = LiveReminderService(scheduler: scheduler, defaults: defaults)
        let status = try await service.setEnabled(.dailyOutfit, enabled: true)
        #expect(status == .denied)
        #expect(!service.preferences().isEnabled(.dailyOutfit))
        #expect(scheduler.requests.isEmpty)
    }
}

@MainActor
private final class TestReminderScheduler: ReminderNotificationScheduling {
    var status: ReminderAuthorization = .authorized
    var failNextAdd = false
    var requests: [String: UNNotificationRequest] = [:]

    func authorization() async -> ReminderAuthorization { status }
    func requestAuthorization() async throws -> Bool { status == .authorized }
    func pendingIdentifiers() async -> [String] { Array(requests.keys) }
    func removePending(withIdentifiers identifiers: [String]) {
        for id in identifiers { requests.removeValue(forKey: id) }
    }
    func add(_ request: UNNotificationRequest) async throws {
        if failNextAdd {
            failNextAdd = false
            throw CocoaError(.fileWriteUnknown)
        }
        requests[request.identifier] = request
    }
}
