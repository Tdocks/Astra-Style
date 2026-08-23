//
//  ProfileShoppingStatsCard.swift
//  AstraStyle
//
//  Wishlist / purchased counts (P6-SHOP-07). Not the P7-HOME-05 dashboard.
//

import SwiftUI

struct ProfileShoppingStatsCard: View {
    @State private var viewModel: ProfileShoppingStatsViewModel

    init(viewModel: ProfileShoppingStatsViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(String(localized: "Saved", comment: "Profile wishlist section"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
            AstraCard {
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(viewModel.line)
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profile.shoppingStats")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await viewModel.onAppear() }
    }
}

@MainActor
@Observable
final class ProfileShoppingStatsViewModel {
    private(set) var line = String(
        localized: "Saved and purchased items will show here.",
        comment: "Profile shopping stats placeholder"
    )

    private let shoppingRepository: ShoppingRepository

    init(shoppingRepository: ShoppingRepository) {
        self.shoppingRepository = shoppingRepository
    }

    func onAppear() async {
        let saved = (try? await shoppingRepository.fetchWishlist())?.count ?? 0
        let bought = (try? await shoppingRepository.fetchPurchased())?.count ?? 0
        line = String(
            localized: "\(saved) saved · \(bought) purchased",
            comment: "Profile wishlist and purchased counts"
        )
    }
}
