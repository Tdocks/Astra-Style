//
//  AppearanceEditorView.swift
//  AstraStyle
//
//  The Release-reachable home for the appearance questions deferred from
//  first-run. Reuses the exact onboarding content so depth, undertone, copy,
//  and accessibility stay one vocabulary.
//

import SwiftUI

struct AppearanceEditorView: View {
    @State private var viewModel: AppearanceEditorViewModel

    init(viewModel: AppearanceEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var model = viewModel

        Group {
            switch viewModel.phase {
            case .loading:
                ProgressView()
                    .tint(AstraColor.accentChampagne)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                failure(error)
            case .ready, .saving:
                ScrollView {
                    VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                        Text(String(
                            localized: "Optional details that refine color, contrast, collars, and visual estimates. Leave anything blank.",
                            comment: "Appearance editor introduction"
                        ))
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                        AppearanceProfileEditorContent(
                            skinTone: $model.appearance.skinTone,
                            skinUndertone: $model.appearance.skinUndertone,
                            hairColor: $model.appearance.hairColor,
                            eyeColor: $model.appearance.eyeColor,
                            facialHair: $model.appearance.facialHair,
                            wearsGlasses: $model.appearance.wearsGlasses,
                            tattoosVisible: $model.appearance.tattoosVisible
                        )

                        AstraButton(
                            title: String(localized: "Save details", comment: "Appearance editor save"),
                            isLoading: viewModel.isSaving
                        ) {
                            Task { await viewModel.save() }
                        }
                        .disabled(viewModel.isSaving)
                        .accessibilityIdentifier("profile.appearance.save")

                        if let confirmation = viewModel.confirmation {
                            Text(confirmation)
                                .astraText(.caption)
                                .foregroundStyle(AstraColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("profile.appearance.confirmation")
                        }
                    }
                    .padding(AstraSpacing.pagePadding)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Appearance", comment: "Appearance editor title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private func failure(_ error: AstraError) -> some View {
        VStack(spacing: AstraSpacing.md) {
            Text(error.message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
            if error.isRetryable {
                Button(String(localized: "Try Again", comment: "Retries appearance loading")) {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.astraSecondary)
            }
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
