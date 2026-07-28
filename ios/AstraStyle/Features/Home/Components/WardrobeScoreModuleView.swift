//
//  WardrobeScoreModuleView.swift
//  AstraStyle
//
//  Spec §6.11 secondary module: "Wardrobe Score".
//

import SwiftUI

struct WardrobeScoreModuleView: View {
    let score: WardrobeScore

    var body: some View {
        AstraCard {
            HStack(spacing: AstraSpacing.md) {
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text("Wardrobe Score")
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                    Text(scoreDescription)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(AstraColor.divider, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(score.overall) / 100)
                        .stroke(AstraColor.accentChampagneAccessible, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(score.overall)")
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                }
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            }
            .padding(AstraSpacing.pagePadding)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Wardrobe Score: \(score.overall) out of 100"))
        .accessibilityValue(Text(scoreDescription))
    }

    private var scoreDescription: String {
        switch score.overall {
        case 85...: String(localized: "Excellent versatility and utilization")
        case 65..<85: String(localized: "Solid, with room to close a few gaps")
        default: String(localized: "A few strategic pieces would go a long way")
        }
    }
}
