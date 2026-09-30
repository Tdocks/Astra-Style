import SwiftUI
import UIKit

struct DailyReminderOptInCard: View {
    let service: ReminderService
    @State private var isEnabled = false
    @State private var permissionDenied = false
    @State private var isSaving = false

    var body: some View {
        if !isEnabled {
            AstraCard {
                VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                    Text("Want a morning outfit reminder?")
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                    Text(permissionDenied
                         ? "Notifications are off. You can allow them in Settings."
                         : "Your look is ready here whenever you need it. A reminder is optional.")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if permissionDenied {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        } else {
                            Task { await enableReminder() }
                        }
                    } label: {
                        if isSaving {
                            ProgressView().tint(AstraColor.accentChampagneAccessible)
                                .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                        } else {
                            Text(permissionDenied ? "Open Settings" : "Remind me at 7:30 AM")
                                .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                        }
                    }
                    .buttonStyle(.astraSecondary)
                    .disabled(isSaving)
                }
            }
            .task { isEnabled = service.preferences().isEnabled(.dailyOutfit) }
            .accessibilityIdentifier("home.dailyReminderOptIn")
        }
    }

    @MainActor
    private func enableReminder() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let status = try await service.setEnabled(.dailyOutfit, enabled: true)
            isEnabled = status == .authorized && service.preferences().isEnabled(.dailyOutfit)
            permissionDenied = status == .denied
        } catch {
            permissionDenied = true
        }
    }
}
