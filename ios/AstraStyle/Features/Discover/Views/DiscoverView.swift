//
//  DiscoverView.swift
//  AstraStyle
//
//  Two lookbook rails plus Unlocks. Not a Shop tab. Home stays private.
//

import SwiftUI

struct DiscoverView: View {
    @State private var viewModel: DiscoverViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: DiscoverViewModel) {
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
            case .loaded(let catalog):
                rails(catalog)
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Discover", comment: "Discover tab title"))
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text(String(
                localized: "Wear This, then make a look public.",
                comment: "Discover empty — public lookbooks start from a worn morning"
            ))
            .astraText(.body)
            .foregroundStyle(AstraColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("discover.empty")
            Text(String(
                localized: "Paste a link on Home when something tempts you.",
                comment: "Discover empty unlocks hint"
            ))
            .astraText(.callout)
            .foregroundStyle(AstraColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rails(_ catalog: DiscoverViewModel.Catalog) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AstraSpacing.xl) {
                lookbookRail(
                    title: String(localized: "Your lookbooks", comment: "Discover own looks rail"),
                    outfits: catalog.mine,
                    empty: String(
                        localized: "Wear This or save a look first.",
                        comment: "Discover own lookbooks empty"
                    ),
                    identifier: "discover.mine"
                )
                lookbookRail(
                    title: String(localized: "Worn by other men", comment: "Discover public worn looks"),
                    outfits: catalog.wornByOthers,
                    empty: String(
                        localized: "Wear This, then make a look public.",
                        comment: "Discover public looks empty"
                    ),
                    identifier: "discover.public"
                )
                unlocksRail(catalog.unlocks)
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
    }

    private func lookbookRail(
        title: String,
        outfits: [Outfit],
        empty: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
            if outfits.isEmpty {
                Text(empty)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier).empty")
            } else {
                ForEach(outfits) { outfit in
                    Button {
                        router.push(DiscoverRoute.lookbook(id: outfit.id))
                    } label: {
                        lookbookCard(outfit)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(identifier).\(outfit.id.uuidString)")
                }
            }
        }
    }

    private func lookbookCard(_ outfit: Outfit) -> some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(outfit.name)
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                if let description = outfit.description, !description.isEmpty {
                    Text(description)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func unlocksRail(_ products: [ProductUnlock]) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(String(localized: "Unlocks", comment: "Discover gap-fill product rail"))
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
            if products.isEmpty {
                Text(String(
                    localized: "Pieces that unlock looks with what you own show up here — from Shop and from links you paste.",
                    comment: "Discover Unlocks empty"
                ))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("discover.unlocks.empty")
            } else {
                ForEach(products) { item in
                    Button {
                        router.push(DiscoverRoute.productDecision(candidateID: item.candidate.id))
                    } label: {
                        AstraCard {
                            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                                Text(item.candidate.name)
                                    .astraText(.headline)
                                    .foregroundStyle(AstraColor.textPrimary)
                                Text(item.candidate.retailer)
                                    .astraText(.caption)
                                    .foregroundStyle(AstraColor.textMuted)
                                Text(unlockLine(item.outfitsUnlocked))
                                    .astraText(.callout)
                                    .foregroundStyle(AstraColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("discover.unlocks.\(item.candidate.id.uuidString)")
                }
            }
        }
    }

    private func unlockLine(_ count: Int) -> String {
        String(
            localized: "Unlocks \(count) new outfits with what you own.",
            comment: "Discover Unlocks outfits-unlocked line"
        )
    }

    private func failed(_ error: AstraError) -> some View {
        VStack(spacing: AstraSpacing.md) {
            Text(error.message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
            if error.isRetryable {
                Button(String(localized: "Try Again", comment: "Retries Discover")) {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.astraSecondary)
            }
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
