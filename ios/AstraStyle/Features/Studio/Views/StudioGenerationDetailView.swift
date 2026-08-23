//
//  StudioGenerationDetailView.swift
//  AstraStyle
//
//  One saved generation from the Studio tab gallery.
//

import SwiftUI

struct StudioGenerationDetailView: View {
    @State private var viewModel: StudioGenerationDetailViewModel

    init(viewModel: StudioGenerationDetailViewModel) {
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
                Text(error.message)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
                    .padding(AstraSpacing.pagePadding)
            case .loaded(let generation):
                ScrollView {
                    VStack(alignment: .leading, spacing: AstraSpacing.md) {
                        Text(String(
                            localized: "Visual estimate",
                            comment: "Studio result badge"
                        ))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                        Text(statusCopy(generation.status))
                            .astraText(.title2)
                            .foregroundStyle(AstraColor.textPrimary)
                        if let url = viewModel.resultImageURL {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                            } placeholder: {
                                ProgressView()
                                    .tint(AstraColor.accentChampagne)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
                            .accessibilityIdentifier("studio.detail.image")
                        }
                    }
                    .padding(AstraSpacing.pagePadding)
                }
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Estimate", comment: "Studio generation detail"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
    }

    private func statusCopy(_ status: StudioGenerationStatus) -> String {
        switch status {
        case .queued: String(localized: "Queued", comment: "Studio generation status")
        case .generating: String(localized: "Generating", comment: "Studio generation status")
        case .complete: String(localized: "This is a visual estimate, not a photograph.", comment: "Studio result disclaimer")
        case .failed: String(localized: "Didn't finish", comment: "Studio generation status")
        }
    }
}
