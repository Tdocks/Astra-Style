//
//  SavedItemsView.swift
//  AstraStyle
//
//  Saved wishlist pieces from Product Decision. Not a dashboard.
//

import SwiftUI

struct SavedItemsView: View {
    @State private var viewModel: SavedItemsViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: SavedItemsViewModel) {
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
                failure(error)
            case .empty:
                empty
            case .loaded(let items):
                list(items)
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Saved", comment: "Saved wishlist title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text(String(
                localized: "Nothing saved yet.",
                comment: "Saved wishlist empty"
            ))
            .astraText(.body)
            .foregroundStyle(AstraColor.textSecondary)
            Text(String(
                localized: "Tap Saved on a product decision to keep a piece here.",
                comment: "Saved wishlist empty hint"
            ))
            .astraText(.callout)
            .foregroundStyle(AstraColor.textMuted)
            Spacer()
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("profile.saved.empty")
    }

    private func list(_ items: [ProductCandidate]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AstraSpacing.md) {
                ForEach(items) { item in
                    Button {
                        router.push(ProfileRoute.productDecision(candidateID: item.id))
                    } label: {
                        row(item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.saved.\(item.id.uuidString)")
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("profile.saved.list")
    }

    private func row(_ item: ProductCandidate) -> some View {
        AstraCard {
            HStack(alignment: .top, spacing: AstraSpacing.md) {
                AstraRemoteImage(
                    url: item.imageURL,
                    aspectRatio: 4.0 / 5.0,
                    thumbnail: .listRowThumbnail,
                    accessibilityDescription: "\(item.name) by \(item.brand ?? item.retailer)"
                )
                .frame(width: 88)

                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    Text(item.name)
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.brand ?? item.retailer)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func failure(_ error: AstraError) -> some View {
        VStack(spacing: AstraSpacing.md) {
            Text(error.message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
            if error.isRetryable {
                Button(String(localized: "Try again", comment: "Retry saved list")) {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.astraSecondary)
            }
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
