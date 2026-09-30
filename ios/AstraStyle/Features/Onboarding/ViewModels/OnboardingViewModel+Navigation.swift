//
//  OnboardingViewModel+Navigation.swift
//  AstraStyle
//

import Foundation

extension OnboardingViewModel {
    public var canGoBack: Bool { step.previous != nil }

    /// Whether Continue is enabled. The wardrobe graph, §6.4 style goal and
    /// §6.5 identity are required decisions — see `OnboardingStep.isSkippable`.
    public var canAdvance: Bool {
        switch step {
        case .goals: !draft.goals.isEmpty
        case .identity: draft.hasCompleteIdentitySelection
        case .wardrobeGraph: draft.wardrobeGraph != nil
        default: true
        }
    }

    /// The label for the forward button, which changes when the step is being
    /// passed without an answer.
    ///
    /// Saying "Skip" when nothing has been entered and "Continue" when
    /// something has is a small honesty: the user knows which he just did, and
    /// a button that always says Continue hides the fact that he answered
    /// nothing.
    public var advanceTitle: String {
        if step == .result {
            return String(localized: "Finish", comment: "Onboarding forward button")
        }
        // §6.9 is the one step whose content advances INSIDE itself: choosing an
        // outfit moves to the next comparison, so the footer button never means
        // "next question". Saying "Continue" while comparisons are still
        // waiting would be offering the user a control that looks like the one
        // he has been tapping and does something entirely different — it leaves
        // the step. Naming the number he is walking away from is the honest
        // version, and it is also the version he can decline.
        if step == .quiz {
            if quizEngine.isFinished(given: draft.quizAnswers) {
                return String(localized: "Continue", comment: "Onboarding forward button")
            }
            let remaining = quizEngine.comparisonCount
                - quizEngine.answeredCount(given: draft.quizAnswers)
            if remaining == quizEngine.comparisonCount {
                return String(localized: "Skip for now", comment: "Onboarding forward button")
            }
            return String(
                format: String(localized: "Skip the last %d",
                               comment: "Onboarding forward button; %d is how many comparisons are left"),
                remaining
            )
        }
        if stepHasAnyAnswer {
            return String(localized: "Continue", comment: "Onboarding forward button")
        }
        return step.isSkippable
            ? String(localized: "Skip for now", comment: "Onboarding forward button")
            : String(localized: "Continue", comment: "Onboarding forward button")
    }

    /// Whether the forward button is offering to skip rather than to submit.
    ///
    /// Kept alongside `advanceTitle` so the label and the button's visual weight
    /// are derived from the same condition and cannot disagree.
    public var advanceIsSkip: Bool {
        if step == .quiz { return !quizEngine.isFinished(given: draft.quizAnswers) }
        return step != .result && !stepHasAnyAnswer && step.isSkippable
    }

    /// Whether the current step has received any input at all. Drives
    /// `advanceTitle` and nothing else.
    var stepHasAnyAnswer: Bool {
        switch step {
        case .intro, .result: true
        case .wardrobeGraph: draft.wardrobeGraph != nil
        case .goals: !draft.goals.isEmpty
        case .identity: !draft.selectedIdentities.isEmpty
        case .measurements:
            [draft.height, draft.weight, draft.chest, draft.waist, draft.inseam, draft.neck]
                .contains(where: \.isAnswered)
                || draft.shoeSize != nil || draft.shirtSize != nil || draft.trouserSize != nil
                || draft.preferredFit != nil || !draft.fitIssues.isEmpty
        case .appearance:
            draft.skinTone != nil || draft.skinUndertone != nil || draft.hairColor != nil || draft.eyeColor != nil
                || draft.facialHair != nil || draft.wearsGlasses != nil || draft.tattoosVisible != nil
        case .lifestyle:
            draft.occupationCategory != nil || draft.dressCode != nil
                || draft.typicalWeek != nil
                || !draft.commonOccasions.isEmpty || draft.laundryCadence != nil
                || draft.monthlyBudget != nil || !draft.preferredBrands.isEmpty
                || draft.travelFrequency != nil || draft.religiousServiceAttireNeeds != nil
                || draft.sustainabilityPreference != nil
        // Counted through the engine rather than off the array, so an answer
        // left over from a build whose imagery has since changed does not make
        // an untouched step look answered.
        case .quiz: quizEngine.answeredCount(given: draft.quizAnswers) > 0
        // Consent on its own is not an answer. A man who read the explanation,
        // acknowledged it and then decided against a photo has skipped this
        // step, and the forward button should say so.
        case .reference: draft.referenceImageFilename != nil || !draft.referenceStoragePaths.isEmpty
        case .firstItems: !firstItems.isEmpty
        }
    }

}
