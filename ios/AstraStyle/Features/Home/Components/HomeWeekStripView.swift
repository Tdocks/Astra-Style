//
//  HomeWeekStripView.swift
//  AstraStyle
//
//  Seven local days under Today's Outfit. Not a dashboard above the look.
//  Tapping another day opens that look. Wear This stays on today.
//

import SwiftUI

struct HomeWeekStripView: View {
    let slots: [WeekDaySlot]
    var onSelect: (WeekDaySlot) -> Void
    var onAddOccasion: () -> Void
    var onPackTrip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            HStack {
                Text(String(localized: "This week", comment: "Home week strip title"))
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                Spacer()
                Button(action: onAddOccasion) {
                    Text(String(localized: "Add to the week", comment: "Opens add-occasion"))
                        .astraText(.caption)
                }
                .accessibilityIdentifier("home.week.addOccasion")
            }

            HStack(spacing: AstraSpacing.xs) {
                ForEach(slots) { slot in
                    Button {
                        onSelect(slot)
                    } label: {
                        dayCell(slot)
                    }
                    .buttonStyle(.plain)
                    .disabled(!slot.hasLook)
                    .accessibilityIdentifier("home.week.\(DateFormatter.astraDay.string(from: slot.date))")
                }
            }

            Button(action: onPackTrip) {
                Text(String(localized: "Pack a trip", comment: "Home door into packing"))
                    .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("home.week.pack")
        }
    }

    private func dayCell(_ slot: WeekDaySlot) -> some View {
        let isToday = Calendar.current.isDateInToday(slot.date)
        return VStack(spacing: 4) {
            Text(slot.date.formatted(.dateTime.weekday(.narrow)))
                .astraText(.caption)
                .foregroundStyle(isToday ? AstraColor.accentChampagne : AstraColor.textMuted)
            Text(slot.outfit?.name ?? "—")
                .astraText(.caption)
                .foregroundStyle(slot.hasLook ? AstraColor.textPrimary : AstraColor.textMuted)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
            if let headline = slot.occasionHeadline, !headline.isEmpty {
                Text(headline)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, AstraSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                .fill(isToday ? AstraColor.backgroundSecondary : Color.clear)
        )
    }
}
