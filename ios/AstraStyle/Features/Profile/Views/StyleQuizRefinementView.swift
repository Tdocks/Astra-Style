import SwiftUI

struct StyleQuizRefinementView: View {
    @State private var viewModel: StyleQuizRefinementViewModel

    init(viewModel: StyleQuizRefinementViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                Text("Refine your taste")
                    .astraText(.displayL)
                Text("Choose one look or select No preference for each comparison. Your answers update all eight Style DNA dimensions.")
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
                switch viewModel.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .ready, .saving:
                    quiz
                case .saved:
                    Label("Your taste profile is up to date.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AstraColor.textPrimary)
                case .failed(let message):
                    errorCard(message)
                case .savedDNAUpdateFailed(let message):
                    VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                        Text("Your answers are saved. Style DNA could not refresh.")
                        Text(message).foregroundStyle(AstraColor.textSecondary)
                        Button("Retry Style DNA") { Task { await viewModel.retryStyleDNA() } }
                            .buttonStyle(.astraSecondary)
                    }
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Taste refinement")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private var quiz: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            OnboardingQuizView(draft: Binding(
                get: { viewModel.draft },
                set: { _ in }
            ), engine: viewModel.engine, onAnswer: { pairID, optionID in
                viewModel.choose(pairID: pairID, optionID: optionID)
            }, onUndo: {
                viewModel.undoLastAnswer()
            })
            if !viewModel.draft.quizAnswers.isEmpty {
                Button("Start comparisons again") { viewModel.restartQuiz() }
                    .buttonStyle(.astraSecondary)
                    .disabled(isSaving)
            }
            Button("Save answers") { Task { await viewModel.save() } }
                .buttonStyle(.astraPrimary)
                .disabled(!viewModel.canSave || isSaving)
                .accessibilityIdentifier("profile.tasteRefinement.save")
        }
    }

    private var isSaving: Bool {
        if case .saving = viewModel.phase { true } else { false }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(message).foregroundStyle(AstraColor.textSecondary)
            Button("Try again") { Task { await viewModel.retryLoad() } }
                .buttonStyle(.astraSecondary)
        }
    }
}
