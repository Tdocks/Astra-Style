//
//  AlternativeLooksCarouselView.swift
//  AstraStyle
//
//  Spec §6.11 secondary module: "Alternative looks carousel". Horizontal
//  paging per spec §3 Motion ("Outfit alternatives: horizontal paging with
//  spring settling").
//

import SwiftUI

struct AlternativeLooksCarouselView: View {
    let outfits: [Outfit]
    let onSelect: (Outfit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text("Alternative Looks")
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AstraSpacing.sm) {
                    ForEach(outfits) { outfit in
                        Button {
                            onSelect(outfit)
                        } label: {
                            AlternativeLookTile(outfit: outfit)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .astraAnimation(AstraMotion.standard, value: outfits)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Alternative looks, \(outfits.count) options"))
    }
}

private struct AlternativeLookTile: View {
    let outfit: Outfit

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            RoundedRectangle(cornerRadius: AstraSpacing.cardRadius, style: .continuous)
                .fill(AstraColor.surfaceElevated)
                .frame(width: 140, height: 175)
                .overlay {
                    Image(systemName: "tshirt")
                        .astraIcon(.emphasis)
                        .foregroundStyle(AstraColor.textMuted)
                }

            Text(outfit.name)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textPrimary)
                .lineLimit(1)

            if let score = outfit.compatibilityScore {
                Text("\(score)% match")
                    .astraText(.micro)
                    .foregroundStyle(AstraColor.textMuted)
            }
        }
        .frame(width: 140)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(outfit.name)\(outfit.compatibilityScore.map { ", \($0) percent match" } ?? "")"))
        .accessibilityAddTraits(.isButton)
    }
}
