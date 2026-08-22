//
//  DiscoverView.swift
//  AstraStyle
//
//  Lookbooks of his clothes. Brand spotlights and shop-the-look stay out.
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
            case .loaded(let outfits):
                list(outfits)
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Your lookbooks", comment: "Discover title"))
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text(String(
                localized: "Wear This or save a look first.",
                comment: "Discover empty — lookbooks come from his outfits"
            ))
            .astraText(.body)
            .foregroundStyle(AstraColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("discover.empty")
            Spacer()
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func list(_ outfits: [Outfit]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AstraSpacing.sm) {
                ForEach(outfits) { outfit in
                    Button {
                        router.push(DiscoverRoute.lookbook(id: outfit.id))
                    } label: {
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
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("discover.lookbook.\(outfit.id.uuidString)")
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
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
