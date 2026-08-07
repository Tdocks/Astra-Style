//
//  OnboardingFlowView.swift
//  AstraStyle
//
//  The §5.1 steps 6–13 container (screens §6.3–§6.10 plus the two §5.1-only
//  steps between the quiz and the result). Owns the view model, routes each
//  step to its screen, and persists after every change.
//
//  Step §6.10 (result) is the one step whose content is not a question, and it
//  changes two things about this container:
//
//    • Submission happens on the way INTO it, not out of it — see
//      `OnboardingViewModel`'s header for why generating before writing the
//      answers would hand every new user a null identity.
//    • There is no longer a full-screen submission overlay here. The result
//      view renders saving, generating, regenerating and failure inline,
//      because a modal spinner over the screen the whole flow exists to reach
//      would hide the previous result during a regenerate — and holding that
//      result on screen is precisely what makes the regenerate legible.
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
                    onBack: { Task { await model.goBack() } },
                    content: { stepContent }
                )
            }
        }
        .task { await model.restore() }
        // Persist on every draft mutation rather than only on step change, so a
        // kill between screens still keeps what was typed on the current one.
        .onChange(of: model.draft) { _, _ in Task { await model.persist() } }
        .onChange(of: model.isFinished) { _, finished in
            // Routing is keyed on the user FINISHING, not on the submission
            // succeeding — a failed submit must not strand him on the last
            // screen with no way forward. And it cannot be keyed on the
            // submission anyway: that now runs when §6.10 OPENS, so routing
            // off it would skip the screen entirely.
            if finished { router.routeState = .main }
        }
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
            OnboardingLifestyleView(draft: $model.draft)
        case .quiz:
            // The engine comes from the view model rather than being built here,
            // because the scaffold's forward button already depends on it — its
            // label has to say how many comparisons are being skipped. Two
            // engines built from the same bundle would agree today and diverge
            // the moment either side gained a filter.
            OnboardingQuizView(draft: $model.draft, engine: model.quizEngine)
        case .reference:
            // Takes the model rather than a binding into the draft. The consent
            // record, the stored bytes and the upload are one decision with one
            // owner (§29), and handing this screen a `$draft` binding would let
            // it write a consent timestamp without the image, or an image
            // without the consent — two states this feature must not have.
            OnboardingReferenceView(model: model)
        case .firstItems:
            // Same reasoning, different dependency: this step writes real
            // `closet_items` rows through `ClosetRepository`, which is a
            // repository call and therefore not something a `View` may make
            // (CLAUDE.md: no network calls in views).
            OnboardingFirstItemsView(model: model)
        case .result:
            OnboardingResultView(model: model)
        }
    }
}
