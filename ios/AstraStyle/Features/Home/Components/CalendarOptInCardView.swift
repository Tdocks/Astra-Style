//
//  CalendarOptInCardView.swift
//  AstraStyle
//
//  Explains the calendar permission before iOS presents its access prompt.
//  Event names and locations stay on device; recommendations receive only
//  an event count and a formality band inferred locally.
//

import SwiftUI

struct CalendarOptInCardView: View {
    let isRequesting: Bool
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            HStack(spacing: AstraSpacing.xs) {
                Image(systemName: "calendar")
                    .astraIcon(.emphasis)
                    .foregroundStyle(AstraColor.textMuted)
                    .accessibilityHidden(true)
                Text("Dress for what's on your calendar")
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
            }

            Text("Astra checks today's events while the app is open. Event names and places stay on this device; Kyra receives only the event count and a general dress level.")
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onEnable) {
                if isRequesting {
                    ProgressView()
                        .tint(AstraColor.accentChampagneAccessible)
                        .accessibilityLabel(Text("Checking"))
                } else {
                    Text("Connect Calendar")
                }
            }
            .buttonStyle(.astraSecondary)
            .disabled(isRequesting)
            .accessibilityIdentifier("home.calendar.enable")
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

struct CalendarDeniedNoticeView: View {
    var body: some View {
        Text("Calendar access is off. Add an occasion manually whenever you like.")
            .astraText(.caption)
            .foregroundStyle(AstraColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("home.calendar.denied")
    }
}
