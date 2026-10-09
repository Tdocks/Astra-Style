import SwiftUI

struct ShopTheLookMissingProductCard: View {
    let piece: ShopTheLookViewModel.MissingPiece
    let onReview: (UUID) -> Void

    var body: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                if let candidate = piece.candidate {
                    productDetails(candidate)
                } else {
                    unavailableDetails
                }
            }
        }
    }

    private func productDetails(_ candidate: ProductCandidate) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            header(name: candidate.name, sponsored: candidate.isSponsored)
            Text(candidate.retailer ?? String(localized: "Retailer not provided", comment: "Missing retailer data"))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
            price(candidate.price, currency: candidate.currency)
            sizes(piece.availableSizes)
            Text(piece.affiliateDisclosure)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shopTheLook.disclosure.\(candidate.id.uuidString.lowercased())")
            Button {
                onReview(candidate.id)
            } label: {
                Text(String(localized: "Review product", comment: "Open product decision from Shop the Look"))
                    .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("shopTheLook.reviewProduct.\(candidate.id.uuidString.lowercased())")
        }
    }

    private func header(name: String, sponsored: Bool) -> some View {
        HStack(alignment: .top, spacing: AstraSpacing.sm) {
            Image(systemName: "bag")
                .astraIcon(.control)
                .foregroundStyle(AstraColor.accentChampagneAccessible)
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(name).astraText(.headline).foregroundStyle(AstraColor.textPrimary)
                Text(categoryName(piece.role)).astraText(.caption).foregroundStyle(AstraColor.textMuted)
            }
            Spacer()
            if sponsored {
                Text(String(localized: "Sponsored", comment: "Sponsored product disclosure label"))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
            }
        }
    }

    @ViewBuilder
    private func price(_ value: Decimal?, currency: String?) -> some View {
        if let value {
            Text(value, format: .currency(code: currency ?? "USD"))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textPrimary)
        } else {
            Text(String(localized: "Price not provided", comment: "Missing product price"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
        }
    }

    private func sizes(_ values: [String]) -> some View {
        Text(values.isEmpty
            ? String(localized: "Sizes not provided", comment: "Missing product size data")
            : String(localized: "Listed sizes: \(values.joined(separator: ", "))", comment: "Reported available sizes"))
        .astraText(.caption)
        .foregroundStyle(values.isEmpty ? AstraColor.textMuted : AstraColor.textSecondary)
    }

    private var unavailableDetails: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            header(name: "\(categoryName(piece.role)) product", sponsored: false)
            Text(String(localized: "Product details are unavailable. No retailer, price, size, or purchase link is shown.", comment: "Fail-closed product data state"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text(piece.affiliateDisclosure)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
        }
    }

    private func categoryName(_ role: OutfitItemRole) -> String {
        ClothingCategory(rawValue: role.rawValue)?.displayName ?? role.rawValue
    }
}
