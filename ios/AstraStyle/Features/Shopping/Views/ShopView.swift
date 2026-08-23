//
//  ShopView.swift
//  AstraStyle
//
//  Catalog browse over curated product_candidates. Not Discover Unlocks.
//

import SwiftUI

struct ShopView: View {
    @State private var viewModel: ShopViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: ShopViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .tint(AstraColor.accentChampagne)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                failed(error)
            case .empty:
                empty
            case .loaded(let items):
                catalog(items)
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Shop", comment: "Shop tab title"))
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text(String(
                localized: "Nothing in the catalog yet.",
                comment: "Shop empty catalog"
            ))
            .astraText(.body)
            .foregroundStyle(AstraColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Text(String(
                localized: "Paste a link on Home when something tempts you. Discover Unlocks scores pieces that fill a gap in what you own.",
                comment: "Shop empty hint"
            ))
            .astraText(.callout)
            .foregroundStyle(AstraColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("shop.empty")
    }

    private func failed(_ error: AstraError) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text(error.message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
            Button(String(localized: "Try again", comment: "Shop retry")) {
                Task { await viewModel.refresh() }
            }
            Spacer()
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func catalog(_ items: [ProductCandidate]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AstraSpacing.md) {
                ForEach(items) { item in
                    Button {
                        router.push(ShopRoute.productDecision(candidateID: item.id))
                    } label: {
                        row(item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .accessibilityIdentifier("shop.catalog")
    }

    private func row(_ item: ProductCandidate) -> some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                HStack {
                    Text(item.name)
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: AstraSpacing.sm)
                    if item.isSponsored {
                        Text(String(localized: "Sponsored", comment: "Shop sponsored label"))
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textMuted)
                    }
                }
                Text(item.brand ?? item.retailer)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                if let price = item.price {
                    Text(price, format: .currency(code: item.currency ?? "USD"))
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textPrimary)
                }
                Text(item.category.displayName)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
