//
//  HomeStyleEntryPointsView.swift
//  AstraStyle
//

import SwiftUI

/// The two primary ways to ask Kyra for help: a fresh style idea, or a
/// recommendation constrained to garments the user already owns.
struct HomeStyleEntryPointsView: View {
    let onInspiration: () -> Void
    let onClosetOutfit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text("What are you looking for?")
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)

            entryButton(
                title: "Get today's inspiration",
                detail: "Ideas shaped by your style, weather, and plans.",
                symbol: "sparkles",
                identifier: "home.style.inspiration",
                action: onInspiration
            )

            entryButton(
                title: "Style an outfit from my closet",
                detail: "Build a look from pieces you already own.",
                symbol: "hanger",
                identifier: "home.style.fromCloset",
                action: onClosetOutfit
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.styleEntryPoints")
    }

    private func entryButton(
        title: String,
        detail: String,
        symbol: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            AstraCard {
                HStack(spacing: AstraSpacing.md) {
                    Image(systemName: symbol)
                        .astraIcon(.emphasis)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                        .frame(width: AstraSpacing.xl, height: AstraSpacing.xl)

                    VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                        Text(title)
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.textPrimary)
                        Text(detail)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: AstraSpacing.xs)

                    Image(systemName: "chevron.right")
                        .astraIcon(.disclosure)
                        .foregroundStyle(AstraColor.textMuted)
                }
                .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    VStack(spacing: AstraSpacing.md) {
        HomeStyleEntryPointsView(onInspiration: {}, onClosetOutfit: {})
    }
    .padding()
    .background(AstraColor.backgroundPrimary)
    .preferredColorScheme(.dark)
}
