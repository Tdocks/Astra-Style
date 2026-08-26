//
//  ProfileShoppingStatsCard.swift
//  AstraStyle
//
//  Wishlist / purchased counts (P6-SHOP-07). Not the P7-HOME-05 dashboard.
//

import SwiftUI

struct ProfileShoppingStatsCard: View {
    @State private var viewModel: ProfileShoppingStatsViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: ProfileShoppingStatsViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(String(localized: "Saved", comment: "Profile wishlist section"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
            if viewModel.savedCount > 0 {
                Button {
                    router.push(ProfileRoute.savedItems)
                } label: {
                    cardContent(showChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.savedRow")
                .accessibilityHint(Text(String(
                    localized: "Opens your saved pieces",
                    comment: "Saved row hint"
                )))
            } else {
                cardContent(showChevron: false)
            }
        }
        .task { await viewModel.onAppear() }
    }

    private func cardContent(showChevron: Bool) -> some View {
        AstraCard {
            HStack(spacing: AstraSpacing.md) {
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(viewModel.line)
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profile.shoppingStats")
                    if showChevron {
                        Text(String(
                            localized: "View saved pieces",
                            comment: "Profile saved list affordance"
                        ))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                    }
                }
                if showChevron {
                    Spacer(minLength: AstraSpacing.sm)
                    Image(systemName: "chevron.right")
                        .astraIcon(.disclosure)
                        .foregroundStyle(AstraColor.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
@Observable
final class ProfileShoppingStatsViewModel {
    private(set) var line = String(
        localized: "Saved and purchased items will show here.",
        comment: "Profile shopping stats placeholder"
    )
    private(set) var savedCount = 0

    private let shoppingRepository: ShoppingRepository

    init(shoppingRepository: ShoppingRepository) {
        self.shoppingRepository = shoppingRepository
    }

    func onAppear() async {
        let saved = (try? await shoppingRepository.fetchWishlist())?.count ?? 0
        let bought = (try? await shoppingRepository.fetchPurchased())?.count ?? 0
        savedCount = saved
        line = String(
            localized: "\(saved) saved · \(bought) purchased",
            comment: "Profile wishlist and purchased counts"
        )
    }
}
