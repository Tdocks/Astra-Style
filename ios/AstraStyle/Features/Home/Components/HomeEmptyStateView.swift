//
//  HomeEmptyStateView.swift
//  AstraStyle
//
//  Spec §6.11 empty state: "Prompt to add 5 closet items" — and spec §21's
//  example copy verbatim: "Add five pieces and Kyra can begin building
//  real outfits."
//

import SwiftUI

struct HomeEmptyStateView: View {
    let onScanItem: () -> Void

    var body: some View {
        VStack(spacing: AstraSpacing.md) {
            Spacer(minLength: AstraSpacing.xl)

            Image(systemName: "sparkles.rectangle.stack")
                .astraIcon(.display)
                .foregroundStyle(AstraColor.accentChampagne)
                .accessibilityHidden(true)

            Text("Let's build your first look")
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)

            Text("Add five pieces and Kyra can begin building real outfits.")
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AstraSpacing.xl)

            AstraButton(title: String(localized: "Scan Your First Item", comment: "Home empty state CTA"), action: onScanItem)
                .padding(.top, AstraSpacing.sm)

            Spacer(minLength: AstraSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(AstraSpacing.pagePadding)
        .accessibilityElement(children: .contain)
    }
}
