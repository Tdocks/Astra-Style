//
//  WeatherOptInCardView.swift
//  AstraStyle
//
//  Spec §7's "Location: when enabling weather", asked in context on first
//  use of Home (P4-HOME-05; moved here from onboarding — see
//  `docs/02-task-breakdown.md`'s `P4-HOME-05` entry and
//  `docs/03-progress.md`'s "Acceptance criteria that are wrong, rather
//  than unmet"). Modeled on `OnboardingReferenceView`'s consent pattern:
//  the explanation is the screen, not a link, and the system prompt only
//  ever follows it — `HomeViewModel.enableWeather()` is the sole caller of
//  `WeatherService.requestLocationPermissionIfNeeded()` reachable from a
//  live screen, and this button is the only thing that calls it.
//
//  WHY THIS IS A CARD AND NOT A SILENT BACKGROUND REQUEST. The easy
//  version of this ticket calls `requestLocationPermissionIfNeeded()` from
//  `HomeViewModel.onAppear()`. That would put the system dialog on screen
//  before a man has read a single word about why Astra wants his location,
//  which is exactly the "no visible payoff, reliably denied permanently"
//  failure `OnboardingLifestyleView`'s header describes for the onboarding
//  version of this same prompt. Explaining first is not decoration; it is
//  the difference between a permission a man grants and one he reflexively
//  declines.
//

import SwiftUI

/// Shown in place of the header's weather line before a location decision
/// exists. Disappears the moment `HomeViewModel.weatherAuthorization`
/// leaves `.notDetermined` — there is nothing left to explain once he has
/// answered, in either direction.
struct WeatherOptInCardView: View {
    let isRequesting: Bool
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            HStack(spacing: AstraSpacing.xs) {
                Image(systemName: "location")
                    .astraIcon(.emphasis)
                    .foregroundStyle(AstraColor.textMuted)
                    .accessibilityHidden(true)

                Text("See today's weather")
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
            }

            Text("Kyra can check today's forecast and factor it into your outfit, using your location only while Astra is open.")
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onEnable) {
                if isRequesting {
                    ProgressView()
                        .tint(AstraColor.accentChampagneAccessible)
                        .accessibilityLabel(Text("Checking"))
                } else {
                    Text("Enable Weather")
                }
            }
            .buttonStyle(.astraSecondary)
            .disabled(isRequesting)
            .accessibilityIdentifier("home.weather.enable")
        }
        .padding(AstraSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .fill(AstraColor.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .strokeBorder(AstraColor.divider, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

/// Spec §21's "Permission denied state", applied to weather the same way
/// the doc's own example applies it to Calendar ("You can still create
/// occasions manually."). No retry control: iOS does not let an app
/// re-trigger this dialog once denied, and offering a button that cannot
/// do anything would be exactly the dead control §22 forbids. The honest
/// thing is a plain statement of what is and is not available, not a
/// nudge toward Settings this screen has no way to act on afterward.
struct WeatherDeniedNoticeView: View {
    var body: some View {
        Text("Weather is off. You can still plan outfits manually.")
            .astraText(.caption)
            .foregroundStyle(AstraColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("home.weather.denied")
    }
}

#Preview("Weather opt-in") {
    VStack(spacing: AstraSpacing.lg) {
        WeatherOptInCardView(isRequesting: false, onEnable: {})
        WeatherOptInCardView(isRequesting: true, onEnable: {})
        WeatherDeniedNoticeView()
    }
    .padding(AstraSpacing.pagePadding)
    .background(AstraColor.backgroundPrimary)
    .preferredColorScheme(.dark)
}
