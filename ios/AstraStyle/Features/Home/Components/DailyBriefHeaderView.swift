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
                Text("\(AstraDateFormatting.timeOfDayGreeting()), \(greetingName).")
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
                Image(systemName: "sparkles")
                    .astraIcon(.control, weight: .medium)
                    .foregroundStyle(AstraColor.accentChampagne)
                    .frame(width: 44, height: 44)
                    .background(AstraColor.surfaceElevated, in: Circle())
            }
            .accessibilityLabel(Text("Ask Kyra"))
            .accessibilityHint(Text("Opens a conversation with your stylist"))
        }
    }
}
