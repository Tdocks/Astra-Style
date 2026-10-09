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
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                recentDecisionsSection
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
            }
            .padding(AstraSpacing.pagePadding)
        }
        .accessibilityIdentifier("shop.empty")
    }

    private func failed(_ error: AstraError) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                recentDecisionsSection
                Text(error.message)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
                Button(String(localized: "Try again", comment: "Shop retry")) {
                    Task { await viewModel.refresh() }
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
    }

    @ViewBuilder
    private var recentDecisionsSection: some View {
        if viewModel.recentDecisions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(String(localized: "Recent decisions", comment: "Cached product evaluation history section title"))
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                    .accessibilityIdentifier("shop.recentDecisions.title")
                Text(String(localized: "Each verdict is labeled with when it was evaluated and reflects your wardrobe at that time.", comment: "History freshness explanation"))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(viewModel.recentDecisions) { decision in
                    if let candidate = decision.candidate {
                        Button {
                            router.push(viewModel.historicalDecisionRoute(candidateID: candidate.id))
                        } label: {
                            recentDecisionRow(candidate: candidate, evaluation: decision.evaluation)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("shop.recentDecision.\(candidate.id.uuidString.lowercased())")
                    }
                }
            }
            .padding(.bottom, AstraSpacing.md)

        }
    }

    private func recentDecisionRow(candidate: ProductCandidate, evaluation: ProductEvaluation) -> some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                Text(candidate.name)
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                Text("\(verdictTitle(evaluation.verdict)) · \(evaluation.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                Text(String(localized: "Last evaluated — this is not a current verdict.", comment: "History row freshness label"))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func verdictTitle(_ verdict: KyraVerdict) -> String {
        switch verdict {
        case .buy: String(localized: "Buy it", comment: "Product verdict")
        case .consider: String(localized: "Worth considering", comment: "Product verdict")
        case .waitForSale: String(localized: "Wait for a sale", comment: "Product verdict")
        case .skip: String(localized: "Skip it", comment: "Product verdict")
        }
    }

    private func catalog(_ items: [ProductCandidate]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AstraSpacing.md) {
                recentDecisionsSection
                ForEach(items) { item in
                    Button {
                        router.push(ShopRoute.productDecision(candidateID: item.id))
                    } label: {
                        row(item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shop.catalogProduct.\(item.id.uuidString.lowercased())")
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .accessibilityIdentifier("shop.catalog")
    }

    private func row(_ item: ProductCandidate) -> some View {
        AstraCard {
            HStack(alignment: .top, spacing: AstraSpacing.md) {
                AstraRemoteImage(
                    url: item.imageURL,
                    aspectRatio: 4.0 / 5.0,
                    thumbnail: .listRowThumbnail,
                    accessibilityDescription: item.retailerLabel.map { "\(item.name) by \($0)" } ?? item.name
                )
                .frame(width: 88)

                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    HStack(alignment: .top) {
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
                    if let retailerLabel = item.retailerLabel {
                        Text(retailerLabel)
                            .astraText(.callout)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
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
}
