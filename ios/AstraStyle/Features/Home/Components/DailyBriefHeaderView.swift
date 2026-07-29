//
//  DailyBriefHeaderView.swift
//  AstraStyle
//
//  Spec §6.11 header: "Good morning, [Name]", Kyra avatar button, weather
//  and location, schedule summary if permission granted.
//

import SwiftUI

struct DailyBriefHeaderView: View {
    let greetingName: String
    let weather: WeatherSnapshot?
    let schedule: ScheduleSnapshot?
    let units: UnitsPreference
    let onTapKyra: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AstraSpacing.md) {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                // An empty name means we have nobody to greet — a guest, or a
                // profile with no display name. "Good evening, there." reads
                // like a mail-merge fallback, which is the opposite of the
                // personal stylist this screen is meant to be. Drop the clause
                // entirely rather than filling it with a placeholder.
                Text(greetingName.isEmpty
                     ? "\(AstraDateFormatting.timeOfDayGreeting())."
                     : "\(AstraDateFormatting.timeOfDayGreeting()), \(greetingName).")
                    .astraText(.title2)
                    .foregroundStyle(AstraColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: AstraSpacing.sm) {
                    if let weather {
                        Label {
                            Text(AstraWeatherFormatting.temperatureRange(low: weather.temperatureLow, high: weather.temperatureHigh, units: units))
                        } icon: {
                            Image(systemName: weather.condition.sfSymbolName)
                        }
                        .labelStyle(.titleAndIcon)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                        .accessibilityLabel(Text("Weather: \(AstraWeatherFormatting.temperatureRange(low: weather.temperatureLow, high: weather.temperatureHigh, units: units))"))
                    }

                    if let locationName = weather?.locationName {
                        Text(locationName)
                            .astraText(.callout)
                            .foregroundStyle(AstraColor.textMuted)
                    }
                }

                if let schedule, schedule.eventCount > 0 {
                    Text(schedule.headline ?? AstraDateFormatting.scheduleSummary(eventCount: schedule.eventCount))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                        .accessibilityLabel(Text("Today's schedule: \(schedule.headline ?? AstraDateFormatting.scheduleSummary(eventCount: schedule.eventCount))"))
                }
            }

            Spacer(minLength: AstraSpacing.sm)

            Button(action: onTapKyra) {
                // The Astra mark, not a generic glyph. Kyra is the product's
                // voice, so the brand mark is the honest button for reaching
                // her — and it is ours rather than a symbol every other app
                // also uses.
                AstraMonogram(size: 20)
                    .frame(width: 44, height: 44)
                    .background(AstraColor.surfaceElevated, in: Circle())
            }
            .accessibilityLabel(Text("Ask Kyra"))
            .accessibilityHint(Text("Opens a conversation with your stylist"))
        }
    }
}
