//
//  UpcomingOccasionsModuleView.swift
//  AstraStyle
//
//  Spec §6.11 secondary module: "Upcoming occasions".
//

import SwiftUI

struct UpcomingOccasionsModuleView: View {
    let occasions: [Occasion]
    let onSelect: (Occasion) -> Void

    var body: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text("Upcoming Occasions")
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)

                ForEach(occasions) { occasion in
                    Button {
                        onSelect(occasion)
                    } label: {
                        OccasionRow(occasion: occasion)
                    }
                    .buttonStyle(.plain)

                    if occasion.id != occasions.last?.id {
                        Divider().overlay(AstraColor.divider)
                    }
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
    }
}

private struct OccasionRow: View {
    let occasion: Occasion

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(occasion.title)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textPrimary)
                Text(occasion.startsAt.formatted(date: .omitted, time: .shortened))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .astraIcon(.disclosure)
                .foregroundStyle(AstraColor.textMuted)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(occasion.title), \(occasion.startsAt.formatted(date: .omitted, time: .shortened))"))
        .accessibilityAddTraits(.isButton)
    }
}
