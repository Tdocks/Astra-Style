//
//  WearFeedbackControlsView.swift
//  AstraStyle
//
//  P4-OUTFIT-14's "Mark Worn" flow, as three controls: Wore it / Skip /
//  Dislike. Thin by design — every write, every in-flight guard, and the
//  exactly-one-row guarantee live on `WearFeedbackViewModel`; this view
//  only renders its state and forwards taps.
//

import SwiftUI

struct WearFeedbackControlsView: View {
    @Bindable var viewModel: WearFeedbackViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            if let outcome = viewModel.lastOutcome {
                confirmation(for: outcome)
            }

            HStack(spacing: AstraSpacing.sm) {
                Button {
                    Task { await viewModel.markWorn() }
                } label: {
                    if viewModel.isRecordingWear {
                        ProgressView().tint(AstraColor.textOnAccent)
                    } else {
                        Text(String(localized: "Wore it", comment: "Marks an outfit as worn today"))
                    }
                }
                .buttonStyle(.astraPrimary)
                .disabled(viewModel.isRecordingWear || viewModel.isRecordingFeedback)
                .accessibilityIdentifier("outfitBuilder.wearFeedback.woreIt")

                Button(String(localized: "Skip", comment: "Records that the wearer skipped this outfit")) {
                    Task { await viewModel.skip() }
                }
                .buttonStyle(.astraTertiary)
                .disabled(viewModel.isRecordingWear || viewModel.isRecordingFeedback)
                .accessibilityIdentifier("outfitBuilder.wearFeedback.skip")

                Button(String(localized: "Dislike", comment: "Records negative feedback on this outfit")) {
                    Task { await viewModel.dislike() }
                }
                .buttonStyle(.astraTertiary)
                .disabled(viewModel.isRecordingWear || viewModel.isRecordingFeedback)
                .accessibilityIdentifier("outfitBuilder.wearFeedback.dislike")
            }
        }
        .alert(
            Text(errorTitle),
            isPresented: errorPresented,
            presenting: viewModel.actionError
        ) { _ in
            Button(String(localized: "OK", comment: "Dismisses an alert")) { viewModel.clearActionError() }
        } message: { error in
            Text(error.message)
        }
    }

    private func confirmation(for outcome: WearFeedbackViewModel.Outcome) -> some View {
        Text(confirmationCopy(for: outcome))
            .astraText(.caption)
            .foregroundStyle(AstraColor.textSecondary)
            .accessibilityIdentifier("outfitBuilder.wearFeedback.confirmation")
    }

    private func confirmationCopy(for outcome: WearFeedbackViewModel.Outcome) -> String {
        switch outcome {
        case .wore:
            return String(localized: "Logged as worn today.", comment: "Confirmation after marking an outfit worn")
        case .feedback(.skipped):
            return String(localized: "Noted — skipped.", comment: "Confirmation after skipping an outfit")
        case .feedback(.dislike):
            return String(localized: "Noted — Kyra will factor this in.", comment: "Confirmation after disliking an outfit")
        case .feedback:
            return String(localized: "Feedback recorded.", comment: "Generic confirmation after recording outfit feedback")
        }
    }

    private var errorTitle: String {
        String(localized: "That didn't save", comment: "Title of the alert shown when wear feedback fails to save")
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.actionError != nil },
            set: { isPresented in
                if !isPresented { viewModel.clearActionError() }
            }
        )
    }
}

#Preview("Wear feedback controls") {
    WearFeedbackControlsView(
        viewModel: WearFeedbackViewModel(outfitID: UUID(), outfitRepository: MockOutfitRepository())
    )
    .padding(AstraSpacing.pagePadding)
    .background(AstraColor.backgroundPrimary)
    .preferredColorScheme(.dark)
}
