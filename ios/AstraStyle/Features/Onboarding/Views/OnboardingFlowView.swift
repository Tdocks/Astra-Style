//
//  OnboardingFlowView.swift
//  AstraStyle
//
//  The §6.3–§6.10 container. Owns the view model, routes each step to its
//  screen, and persists after every change.
//
//  Steps §6.7 (appearance), §6.9 (quiz) and §6.10 (result) are stubs for now,
//  and say so on screen rather than pretending. §6.9 needs the generated pair
//  imagery; §6.10 needs `POST /style-dna/generate`, which needs Kyra's provider
//  decided. A stub that admits what it is beats a screen that looks finished and
//  silently does nothing.
//

import SwiftUI

public struct OnboardingFlowView: View {
    @Environment(AppRouter.self) private var router
    @State private var model: OnboardingViewModel

    public init(model: OnboardingViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Group {
            if model.step == .intro {
                OnboardingIntroView(onBegin: { Task { await model.advance() } })
            } else {
                OnboardingStepScaffold(
                    step: model.step,
                    advanceTitle: model.advanceTitle,
                    advanceIsSkip: model.advanceIsSkip,
                    canAdvance: model.canAdvance,
                    canGoBack: model.canGoBack,
                    onAdvance: { Task { await model.advance() } },
                    onBack: { Task { await model.goBack() } }
                ) {
                    stepContent
                }
            }
        }
        .task { await model.restore() }
        // Persist on every draft mutation rather than only on step change, so a
        // kill between screens still keeps what was typed on the current one.
        .onChange(of: model.draft) { _, _ in Task { await model.persist() } }
        .onChange(of: model.submission) { _, state in
            switch state {
            case .succeeded, .savedLocally:
                // Both outcomes reach the app. A guest's answers are saved
                // locally and submitted at account creation (ADR 0011), so
                // holding him on the onboarding screen would be punishing him
                // for not having signed up yet.
                router.routeState = .main
            default:
                break
            }
        }
        .overlay { submissionOverlay }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .intro:
            EmptyView()   // handled above, outside the scaffold
        case .goals:
            OnboardingGoalsView(selected: $model.draft.goals)
        case .identity:
            OnboardingIdentityView(
                selected: $model.draft.selectedIdentities,
                primary: $model.draft.primaryIdentity
            )
        case .measurements:
            OnboardingMeasurementsView(draft: $model.draft)
        case .appearance:
            OnboardingAppearanceView(draft: $model.draft)
        case .lifestyle:
            OnboardingStubStep(
                headline: String(localized: "Not built yet", comment: "Onboarding stub headline"),
                detail: String(localized: "Occupation, dress code, budget and travel land here. They decide what Kyra bothers recommending.",
                               comment: "Onboarding stub detail")
            )
        case .quiz:
            OnboardingStubStep(
                headline: String(localized: "Not built yet", comment: "Onboarding stub headline"),
                detail: String(localized: "Paired outfit comparisons land here once the imagery is generated.",
                               comment: "Onboarding stub detail")
            )
        case .result:
            OnboardingStubStep(
                headline: String(localized: "Almost there", comment: "Onboarding stub headline"),
                detail: String(localized: "Your Style DNA summary lands here. Finishing now saves everything you've entered.",
                               comment: "Onboarding stub detail")
            )
        }
    }

    @ViewBuilder
    private var submissionOverlay: some View {
        switch model.submission {
        case .submitting:
            ZStack {
                AstraColor.backgroundPrimary.opacity(0.86).ignoresSafeArea()
                VStack(spacing: AstraSpacing.md) {
                    ProgressView().tint(AstraColor.accentChampagne)
                    Text("Saving your answers…")
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                }
            }
            .transition(.opacity)

        case .failed(let message):
            ZStack {
                AstraColor.backgroundPrimary.opacity(0.94).ignoresSafeArea()
                VStack(spacing: AstraSpacing.md) {
                    Text("That didn't save")
                        .astraText(.title2)
                        .foregroundStyle(AstraColor.textPrimary)

                    Text(message)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                        .multilineTextAlignment(.center)

                    // Reassurance, and true: the draft is only cleared after the
                    // server accepts it, so nothing has been lost.
                    Text("Your answers are still here.")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)

                    AstraButton(title: String(localized: "Try again", comment: "Retry submission")) {
                        Task { await model.retrySubmission() }
                    }
                    .accessibilityIdentifier("onboarding.retry")
                }
                .padding(AstraSpacing.pagePadding)
            }
            .transition(.opacity)

        default:
            EmptyView()
        }
    }
}

/// Placeholder body for the steps that are not built.
///
/// Deliberately plain, and deliberately says "not built yet". Spec §19's
/// placeholder rule and `scripts/check_ui_conventions.py` forbid internal ticket
/// ids in user-facing copy, so this describes the screen's purpose in the
/// product's voice instead.
private struct OnboardingStubStep: View {
    let headline: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(headline)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
            Text(detail)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.card).fill(AstraColor.surfaceElevated)
        )
    }
}
