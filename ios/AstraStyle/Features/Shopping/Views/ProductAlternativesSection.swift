import SwiftUI

struct ProductAlternativesSection: View {
    @Environment(AppRouter.self) private var router

    let loaded: ProductDecisionViewModel.Loaded

    var body: some View {
        if !loaded.evaluation.alternatives.isEmpty {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                AstraSectionHeader(title: String(localized: "Other options", comment: "Server-scored product alternatives"))
                Text(String(
                    localized: "A stronger wardrobe match means a higher closet compatibility score, not a claim about garment quality. Retailer and affiliate details appear on the product page.",
                    comment: "Limits of the alternative score and source fields"
                ))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(loaded.evaluation.alternatives) { alternative in
                    alternativeRow(alternative)
                }
            }
            .accessibilityIdentifier("productDecision.alternatives")
        }
    }

    private func alternativeRow(_ alternative: ProductAlternative) -> some View {
        let lowerPriced = ProductAlternativeComparison.isLowerPriced(
            alternative,
            primaryPrice: loaded.candidate?.price,
            primaryCurrency: loaded.candidate?.currency
        )
        let strongerMatch = ProductAlternativeComparison.isStrongerWardrobeMatch(
            alternative,
            primaryScore: loaded.evaluation.compatibilityScore
        )
        return Button {
            router.push(ShopRoute.productDecision(candidateID: alternative.productCandidateID))
        } label: {
            AstraCard {
                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    HStack(alignment: .top) {
                        Text(alternative.name)
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.textPrimary)
                        Spacer(minLength: AstraSpacing.sm)
                        if alternative.sponsored {
                            Text(String(localized: "Sponsored", comment: "Sponsored alternative label"))
                                .astraText(.caption)
                                .foregroundStyle(AstraColor.textMuted)
                        }
                    }
                    Text(alternativeCategory(lowerPriced: lowerPriced, strongerMatch: strongerMatch))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                    priceLabel(alternative)
                    Text(String(localized: "Wardrobe compatibility: \(alternative.compatibilityScore)", comment: "Alternative's server-scored compatibility"))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                    Text(String(localized: "Review product details", comment: "Opens the product and its affiliate disclosure"))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("productDecision.alternative.\(alternative.id.uuidString.lowercased())")
    }

    @ViewBuilder
    private func priceLabel(_ alternative: ProductAlternative) -> some View {
        if let price = alternative.price, let currency = alternative.currency {
            Text(price, format: .currency(code: currency))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
        } else if let price = alternative.price {
            Text(String(localized: "Price amount: \(price.formatted()) · currency not provided", comment: "Alternative price lacks a currency code"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
        } else {
            Text(String(localized: "Price not provided", comment: "Alternative price unavailable"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
        }
    }

    private func alternativeCategory(lowerPriced: Bool, strongerMatch: Bool) -> String {
        switch (lowerPriced, strongerMatch) {
        case (true, true):
            String(localized: "Lower price · stronger wardrobe match", comment: "Alternative comparison tags")
        case (true, false):
            String(localized: "Lower price", comment: "Alternative comparison tag")
        case (false, true):
            String(localized: "Stronger wardrobe match", comment: "Alternative comparison tag")
        case (false, false):
            String(localized: "Alternative", comment: "Alternative without comparable advantage")
        }
    }
}
