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
                .accessibilityAddTraits(.isHeader)
            content
        }
        .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            HStack(spacing: AstraSpacing.sm) {
                ProgressView().tint(AstraColor.accentChampagne)
                Text(String(localized: "Loading your saved and purchased items…", comment: "Profile shopping counts loading"))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
            .accessibilityIdentifier("profile.shoppingStats.loading")
        case .loaded(let savedCount, let purchasedCount):
            let line = String(
                localized: "\(savedCount) saved · \(purchasedCount) purchased",
                comment: "Profile wishlist and purchased counts"
            )
            if savedCount > 0 {
                Button {
                    router.push(ProfileRoute.savedItems)
                } label: {
                    cardContent(line: line, showChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.savedRow")
                .accessibilityHint(Text(String(
                    localized: "Opens your saved pieces",
                    comment: "Saved row hint"
                )))
            } else {
                cardContent(line: line, showChevron: false)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(message)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Try again", comment: "Retry Profile shopping counts")) {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.astraSecondary)
                .accessibilityIdentifier("profile.shoppingStats.retry")
            }
            .accessibilityIdentifier("profile.shoppingStats.error")
        }
    }

    private func cardContent(line: String, showChevron: Bool) -> some View {
        AstraCard {
            HStack(spacing: AstraSpacing.md) {
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(line)
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
    enum State: Equatable, Sendable {
        case loading
        case loaded(savedCount: Int, purchasedCount: Int)
        case failed(String)
    }

    private(set) var state: State = .loading

    private let shoppingRepository: ShoppingRepository
    private var loadGeneration = UUID()

    init(shoppingRepository: ShoppingRepository) {
        self.shoppingRepository = shoppingRepository
    }

    func onAppear() async {
        await load()
    }

    func retry() async {
        await load()
    }

    private func load() async {
        loadGeneration = UUID()
        let generation = loadGeneration
        state = .loading
        do {
            async let savedItems = shoppingRepository.fetchWishlist()
            async let purchasedItems = shoppingRepository.fetchPurchased()
            let (saved, purchased) = try await (savedItems, purchasedItems)
            guard loadGeneration == generation else { return }
            state = .loaded(savedCount: saved.count, purchasedCount: purchased.count)
        } catch let error as AstraError {
            guard loadGeneration == generation else { return }
            state = .failed(error.message)
        } catch {
            guard loadGeneration == generation else { return }
            state = .failed(String(localized: "Your shopping counts couldn't load. Check your connection and try again.", comment: "Profile shopping stats error"))
        }
    }
}
