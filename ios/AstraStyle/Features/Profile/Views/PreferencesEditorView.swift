//
//  PreferencesEditorView.swift
//  AstraStyle
//
//  Post-onboarding editor for identity and visual quiz answers.
//

import SwiftUI

struct PreferencesEditorView: View {
    @State private var viewModel: PreferencesEditorViewModel

    init(viewModel: PreferencesEditorViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                ProgressView()
                    .tint(AstraColor.accentChampagne)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                failure(error)
            case .ready, .saving:
                editorContent
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Preferences", comment: "Preferences editor title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var editorContent: some View {
        @Bindable var model = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                Text(String(
                    localized: "These are the answers behind your Style DNA. Change them here any time.",
                    comment: "Preferences editor intro"
                ))
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                OnboardingIdentityView(
                    selected: $model.draft.selectedIdentities,
                    primary: $model.draft.primaryIdentity
                )

                OnboardingQuizView(
                    draft: $model.draft,
                    engine: viewModel.quizEngine
                )

                AstraButton(
                    title: String(localized: "Save preferences", comment: "Preferences save"),
                    isLoading: viewModel.isSaving
                ) {
                    Task { await viewModel.save() }
                }
                .disabled(viewModel.isSaving || !model.draft.hasCompleteIdentitySelection)
                .accessibilityIdentifier("profile.preferences.save")

                if let confirmation = viewModel.confirmation {
                    Text(confirmation)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                        .accessibilityIdentifier("profile.preferences.confirmation")
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
    }

    private func failure(_ error: AstraError) -> some View {
        VStack(spacing: AstraSpacing.md) {
            Text(error.message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
            Button(String(localized: "Try again", comment: "Retry preferences load")) {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.astraSecondary)
        }
        .padding(AstraSpacing.pagePadding)
    }
}
