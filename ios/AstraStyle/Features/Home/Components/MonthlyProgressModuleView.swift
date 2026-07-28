//
//  MonthlyProgressModuleView.swift
//  AstraStyle
//
//  Spec §6.11 secondary module: "Monthly progress" — a teaser linking into
//  the full Monthly Review (spec §6.23). Full monthly review content is
//  owned by Features/Profile per the P7-SUB ticket set; this is
//  intentionally just the Home-surfaced summary line.
//

import SwiftUI

struct MonthlyProgressModuleView: View {
    let wearsThisMonth: Int
    let newItemsThisMonth: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            AstraCard {
                HStack(spacing: AstraSpacing.sm) {
                    VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                        Text("This Month")
                            .astraText(.micro)
                            .foregroundStyle(AstraColor.textMuted)
                        Text("\(wearsThisMonth) wears logged · \(newItemsThisMonth) new pieces")
                            .astraText(.callout)
                            .foregroundStyle(AstraColor.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .astraIcon(.disclosure)
                        .foregroundStyle(AstraColor.textMuted)
                }
                .padding(AstraSpacing.pagePadding)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("This month: \(wearsThisMonth) wears logged, \(newItemsThisMonth) new pieces"))
        .accessibilityHint(Text("Opens your Style Journey"))
    }
}
