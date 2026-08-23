//
//  StudioHomeView.swift
//  AstraStyle
//
//  Style Studio tab: gallery of generations plus the same Visualize door
//  Home and outfit detail already use. No preset mall.
//

import SwiftUI

struct StudioHomeView: View {
    @State private var viewModel: StudioHomeViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: StudioHomeViewModel) {
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
            case .loaded(let generations):
                gallery(generations)
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Style Studio", comment: "Studio tab title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.presentModal(.studioGeneration(outfitID: nil))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "See a look on you", comment: "Studio generate"))
                .accessibilityIdentifier("studio.start")
            }
        }
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text(String(
                localized: "See a look on you before you wear it.",
                comment: "Studio empty title"
            ))
            .astraText(.body)
            .foregroundStyle(AstraColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            AstraButton(
                title: String(localized: "See a look on you", comment: "Studio generate CTA")
            ) {
                router.presentModal(.studioGeneration(outfitID: nil))
            }
            .accessibilityIdentifier("studio.empty.start")
            Spacer()
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("studio.empty")
    }

    private func failed(_ error: AstraError) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text(error.message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
            Button(String(localized: "Try again", comment: "Studio retry")) {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.astraSecondary)
            Spacer()
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func gallery(_ generations: [StudioGeneration]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AstraSpacing.md) {
                ForEach(generations.filter { !$0.isDeleted }) { generation in
                    Button {
                        router.push(StudioRoute.generation(generationID: generation.id))
                    } label: {
                        AstraCard {
                            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                                Text(statusLabel(generation.status))
                                    .astraText(.headline)
                                    .foregroundStyle(AstraColor.textPrimary)
                                Text(generation.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .astraText(.caption)
                                    .foregroundStyle(AstraColor.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("studio.generation.\(generation.id.uuidString)")
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("studio.gallery")
    }

    private func statusLabel(_ status: StudioGenerationStatus) -> String {
        switch status {
        case .queued: String(localized: "Queued", comment: "Studio generation status")
        case .generating: String(localized: "Generating", comment: "Studio generation status")
        case .complete: String(localized: "Visual estimate", comment: "Studio generation status")
        case .failed: String(localized: "Didn't finish", comment: "Studio generation status")
        }
    }
}
