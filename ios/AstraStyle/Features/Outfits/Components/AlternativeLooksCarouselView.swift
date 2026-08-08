//
//  AlternativeLooksCarouselView.swift
//  AstraStyle
//
//  Spec §6.11's "Alternative looks carousel" secondary module, promoted to
//  a shared component per `P4-OUTFIT-13`: "Implement a shared
//  horizontal-paging carousel component ... reused on both the Daily
//  Brief and Outfit detail." It used to live under `Features/Home
//  /Components` as a Home-only type; that file is gone and this is its
//  only implementation, so nothing can drift into a second copy.
//
//  SPRING PHYSICS, NOT THE STANDARD EASE. Spec §3 "Motion" is explicit:
//  "Outfit alternatives: horizontal paging with spring settling" — and
//  `AstraMotion.outfitPaging` already exists for exactly this token. The
//  Home-only version this replaced used `AstraMotion.standard` (a linear
//  220 ms ease-in-out) instead, which was a real gap against the
//  acceptance bar this ticket sets ("uses spring physics ... not a linear
//  animation"), not a deliberate choice — fixed here rather than carried
//  forward into the shared component.
//

import SwiftUI

/// A horizontal-paging carousel of alternative outfit looks, used by the
/// Daily Brief's "Alternative Looks" module and by Outfit detail wherever
/// a screen has a real set of alternatives to offer (see that call site's
/// own header for what "real" means there).
public struct AlternativeLooksCarouselView: View {
    let outfits: [Outfit]
    let onSelect: (Outfit) -> Void

    public init(outfits: [Outfit], onSelect: @escaping (Outfit) -> Void) {
        self.outfits = outfits
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AstraSpacing.sm) {
                    ForEach(outfits) { outfit in
                        Button {
                            AstraHaptics.selection()
                            onSelect(outfit)
                        } label: {
                            AlternativeLookTile(outfit: outfit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("alternativeLooks.tile.\(outfit.id.uuidString.lowercased())")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .astraAnimation(AstraMotion.outfitPaging, value: outfits)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityIdentifier("alternativeLooks.carousel")
    }

    private var title: String {
        String(localized: "Alternative Looks", comment: "Section header for the alternative outfit looks carousel")
    }

    private var accessibilityLabel: String {
        String(localized: "\(title), \(outfits.count) options", comment: "VoiceOver summary of the alternative looks carousel")
    }
}

private struct AlternativeLookTile: View {
    let outfit: Outfit

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            // A real thumbnail when the outfit has one, the same honest
            // no-photo fallback every other surface uses when it doesn't —
            // never the static hanger placeholder this tile used to show
            // unconditionally, which looked identical for an outfit with a
            // hero image and one without.
            AstraRemoteImage(
                url: outfit.heroImageURL ?? outfit.generatedPreviewURL,
                aspectRatio: 4.0 / 5.0,
                thumbnail: .closetGridTile,
                accessibilityDescription: imageDescription
            )
            .frame(width: Self.tileWidth)
            .overlay(alignment: .bottomLeading) {
                // Same §11/§13 guardrail `HeroOutfitCardView` applies: a
                // curated `heroImageURL` never carries the badge, a
                // Style-Studio-only `generatedPreviewURL` always does.
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
        .frame(width: Self.tileWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }

    // 140 pt — matches this tile's pre-promotion width, kept as its own
    // named constant (there is no "carousel tile" token in `AstraSpacing`
    // yet) the same way `ClosetItemHeroSection.stripThumbnailSize` is.
    private static let tileWidth: CGFloat = 140

    private var imageDescription: String {
        String(localized: "Editorial preview of \(outfit.name)", comment: "Accessibility description of an alternative outfit look's thumbnail")
    }

    // Matches this tile's original (non-localized-interpolation) form:
    // a plain concatenated string handed straight to `Text(_:)`, the same
    // pattern `AlternativeLookTile` used before promotion.
    private var accessibilityLabel: String {
        "\(outfit.name)\(outfit.compatibilityScore.map { ", \($0) percent match" } ?? "")"
    }
}
