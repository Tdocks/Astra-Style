//
//  OnboardingWardrobeGraphView.swift
//  AstraStyle
//
//  Product picker (ADR 0019). Not a Settings gender toggle — chosen once.
//

import SwiftUI

struct OnboardingWardrobeGraphView: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            graphCard(
                graph: .menswear3Role,
                title: String(localized: "Men's looks", comment: "Onboarding wardrobe graph option"),
                detail: String(localized: "Tops, bottoms, shoes, and the layers that pull them together.",
                               comment: "Onboarding wardrobe graph option detail")
            )
            graphCard(
                graph: .womenswear,
                title: String(localized: "Dresses and separates", comment: "Onboarding wardrobe graph option"),
                detail: String(localized: "Dresses or separates, with shoes and finishing layers.",
                               comment: "Onboarding wardrobe graph option detail")
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.wardrobeGraph")
    }

    private func graphCard(graph: WardrobeGraph, title: String, detail: String) -> some View {
        let selected = model.draft.wardrobeGraph == graph
        return Button {
            model.selectWardrobeGraph(graph)
        } label: {
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(title)
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                Text(detail)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AstraSpacing.md)
            .background(AstraColor.surfaceElevated, in: RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .strokeBorder(selected ? AstraColor.accentChampagne : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("onboarding.wardrobeGraph.\(graph.rawValue)")
    }
}
