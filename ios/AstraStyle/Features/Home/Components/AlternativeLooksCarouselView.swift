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
                        // Stable id for UI tests, matching
                        // `closet.grid.item.<id>`'s convention — VoiceOver
                        // still reads the tile's own composed label below.
                        .accessibilityIdentifier("home.alternatives.\(outfit.id.uuidString.lowercased())")
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
            // Was a static tshirt glyph for every alternative regardless of
            // whether the outfit had a real photo — the P4-HOME-04 gap this
            // file exists to close ("modules render placeholders where they
            // should render measured values"). `AstraRemoteImage` already
            // does the honest thing when there truly is no photo (its own
            // hanger fallback, `AstraRemoteImage.swift`'s header), so this
            // tile no longer needs its own placeholder art on top of that.
            AstraRemoteImage(
                url: outfit.heroImageURL ?? outfit.generatedPreviewURL,
                aspectRatio: 140.0 / 175.0,
                thumbnail: .closetGridTile,
                cornerRadius: AstraSpacing.cardRadius,
                accessibilityDescription: String(localized: "Preview of \(outfit.name)", comment: "Accessibility description of an alternative outfit's thumbnail")
            )
                .frame(width: 140, height: 175)
                .overlay(alignment: .bottomLeading) {
                    // Same §11/§13 guardrail as the hero card (`HeroOutfitCardView.heroImage`).
                    if outfit.heroImageURL == nil, outfit.generatedPreviewURL != nil {
                        GeneratedImageBadge()
                            .padding(AstraSpacing.xxs)
                    }
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
