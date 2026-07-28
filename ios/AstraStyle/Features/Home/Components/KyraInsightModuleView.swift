//
//  KyraInsightModuleView.swift
//  AstraStyle
//
//  Spec §6.11 secondary module: "Kyra's Insight". Surfaces the
//  `kyra_message` already generated with today's brief (spec §9
//  `daily_briefs.kyra_message`) rather than making another network call.
//

import SwiftUI

struct KyraInsightModuleView: View {
    let message: String

    var body: some View {
        AstraCard {
            HStack(alignment: .top, spacing: AstraSpacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AstraColor.accentChampagne)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text("Kyra's Insight")
                        .astraText(.micro)
                        .foregroundStyle(AstraColor.textMuted)
                    Text(message)
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textPrimary)
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Kyra's Insight: \(message)"))
    }
}
