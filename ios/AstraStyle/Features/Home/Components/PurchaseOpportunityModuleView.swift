//
//  PurchaseOpportunityModuleView.swift
//  AstraStyle
//
//  Spec §6.11 secondary module: "Purchase opportunity with outfit unlock
//  count". Sponsored/organic separation (spec §11 guardrails, §17) is
//  enforced server-side in what populates `PurchaseOpportunity` — this
//  view only renders whatever the provider already ranked.
//

import SwiftUI

struct PurchaseOpportunityModuleView: View {
    let opportunity: PurchaseOpportunity
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            AstraCard {
                HStack(spacing: AstraSpacing.sm) {
                    RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                        .fill(AstraColor.surfaceElevated)
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "bag")
                                .foregroundStyle(AstraColor.textMuted)
                        }

                    VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                        Text(opportunity.productCandidate.name)
                            .astraText(.callout)
                            .foregroundStyle(AstraColor.textPrimary)
                            .lineLimit(1)
                        Text(unlockText)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.accentChampagneAccessible)
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
        .accessibilityLabel(Text("\(opportunity.productCandidate.name). \(unlockText)"))
        .accessibilityHint(Text("Opens the product decision page"))
    }

    private var unlockText: String {
        String(localized: "^[Unlocks \(opportunity.outfitsUnlocked) outfit](inflect: true)", comment: "Purchase opportunity unlock count")
    }
}
