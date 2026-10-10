import SwiftUI

struct NotificationSettingsView: View {
    let service: ReminderService
    @State private var preferences = ReminderPreferences()
    @State private var authorization: ReminderAuthorization = .notDetermined
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 30)) ?? .now
    @State private var isLoading = true
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                DatePicker("Morning reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .disabled(!preferences.isEnabled(.dailyOutfit))
                    .onChange(of: reminderTime) { _, value in
                        Task {
                            let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
                            try? await service.setMorningTime(hour: parts.hour ?? 7, minute: parts.minute ?? 30)
                            preferences = service.preferences()
                        }
                    }
                reminderToggle(.dailyOutfit)
            } header: {
                Text("Daily help")
            } footer: {
                Text("Astra Style never asks for notification access until you turn on a reminder here or from Home.")
            }
            Section("More reminders") {
                reminderToggle(.upcomingOccasion)
                reminderToggle(.laundry)
                reminderToggle(.monthlyReview)
                reminderToggle(.packingTrip)
            }
            if let message {
                Section { Text(message).foregroundStyle(AstraColor.textSecondary) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView()
                    .tint(AstraColor.accentChampagneAccessible)
                    .accessibilityIdentifier("profile.notifications.loading")
            }
        }
        .task { await load() }
        .accessibilityIdentifier("profile.notificationSettings")
    }

    private func reminderToggle(_ kind: ReminderKind) -> some View {
        Toggle(isOn: Binding(
            get: { preferences.isEnabled(kind) },
            set: { enabled in Task { await setEnabled(kind, enabled: enabled) } }
        )) {
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(kind.title)
                Text(kind.description)
                    .font(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
            }
        }
        .tint(AstraColor.accentChampagneAccessible)
        .disabled(isLoading)
        .accessibilityIdentifier("profile.reminder.\(kind.rawValue)")
    }

    @MainActor
    private func load() async {
        preferences = service.preferences()
        authorization = await service.authorization()
        reminderTime = Calendar.current.date(from: DateComponents(
            hour: preferences.morningHour,
            minute: preferences.morningMinute
        )) ?? .now
        isLoading = false
    }

    @MainActor
    private func setEnabled(_ kind: ReminderKind, enabled: Bool) async {
        message = nil
        do {
            authorization = try await service.setEnabled(kind, enabled: enabled)
            preferences = service.preferences()
            if authorization == .denied && enabled {
                message = "Notifications are disabled for Astra Style. Turn them on in Settings to use reminders."
            }
        } catch {
            message = "This reminder couldn't be updated. Please try again."
        }
    }
}
