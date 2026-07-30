//
//  OnboardingStep.swift
//  AstraStyle
//
//  The ordered sequence of spec §6.3–§6.10.
//
//  Declared as an enum with an explicit order rather than inferred from an
//  array of views, so that progress, resumption, and "can I skip this" are
//  answerable without touching the view layer — and testable without a UI.
//

import Foundation

public enum OnboardingStep: String, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case intro          // §6.3 Kyra introduction
    case goals          // §6.4 Style goals
    case identity       // §6.5 Style identity
    case measurements   // §6.6 Measurements and fit
    case appearance     // §6.7 Appearance profile
    case lifestyle      // §6.8 Lifestyle
    case quiz           // §6.9 Style preference quiz
    case result         // §6.10 Style DNA result

    public var id: String { rawValue }

    public static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.index < rhs.index
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Steps the user answers. Excludes `intro` (nothing to answer) and
    /// `result` (an outcome, not a question), so the progress indicator counts
    /// what a user would count.
    ///
    /// Showing "1 of 8" on a screen that only says hello, and again on the
    /// results page, makes the flow feel longer than it is and the progress bar
    /// dishonest.
    public static var answerableSteps: [OnboardingStep] {
        allCases.filter { $0 != .intro && $0 != .result }
    }

    /// 1-based position among the answerable steps, or nil for intro/result.
    public var answerablePosition: Int? {
        guard let i = Self.answerableSteps.firstIndex(of: self) else { return nil }
        return i + 1
    }

    public var title: String {
        switch self {
        case .intro: String(localized: "Meet Kyra", comment: "Onboarding step title")
        case .goals: String(localized: "What are you after?", comment: "Onboarding step title")
        case .identity: String(localized: "How do you want to look?", comment: "Onboarding step title")
        case .measurements: String(localized: "Sizes and fit", comment: "Onboarding step title")
        case .appearance: String(localized: "A few details", comment: "Onboarding step title")
        case .lifestyle: String(localized: "How you live", comment: "Onboarding step title")
        case .quiz: String(localized: "Which would you wear?", comment: "Onboarding step title")
        case .result: String(localized: "Your Style DNA", comment: "Onboarding step title")
        }
    }

    /// One line under the title, saying what the step is for.
    ///
    /// Every step gets one. A form that asks for a man's inseam without saying
    /// why is a form he abandons, and §6.7 explicitly requires explaining why
    /// each field is used.
    public var rationale: String {
        switch self {
        case .intro:
            String(localized: "A short introduction before the questions start.",
                   comment: "Onboarding step rationale")
        case .goals:
            String(localized: "This decides what Kyra leads with — everyday outfits, filling gaps, or smarter buying.",
                   comment: "Onboarding step rationale")
        case .identity:
            String(localized: "Pick three directions that appeal, then say which one is most you.",
                   comment: "Onboarding step rationale")
        case .measurements:
            String(localized: "Sizes let Kyra judge cut and fit rather than guessing. Skip anything you don't know — it still works.",
                   comment: "Onboarding step rationale")
        case .appearance:
            String(localized: "Entirely optional. These only affect colour suggestions, and you can leave every one blank.",
                   comment: "Onboarding step rationale")
        case .lifestyle:
            String(localized: "Where you go and what you spend shapes what's actually useful to recommend.",
                   comment: "Onboarding step rationale")
        case .quiz:
            String(localized: "A few quick comparisons. There is no right answer.",
                   comment: "Onboarding step rationale")
        case .result:
            String(localized: "What Kyra took from your answers. Edit anything that's wrong.",
                   comment: "Onboarding step rationale")
        }
    }

    /// Whether this step may be passed without answering.
    ///
    /// Only `identity` is required, because §6.5 specifies an exact shape
    /// ("choose three, then rank one primary") that a partial answer cannot
    /// satisfy — two identities with no primary is not a smaller answer, it is
    /// an unusable one. Everything else, including all of §6.6 and §6.7,
    /// tolerates being skipped entirely: `FrameProfile` is built to degrade
    /// (docs/14 §2) and Style DNA is built to work from less.
    public var isSkippable: Bool {
        self != .identity
    }

    public var next: OnboardingStep? {
        let all = Self.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return nil }
        return all[i + 1]
    }

    public var previous: OnboardingStep? {
        let all = Self.allCases
        guard let i = all.firstIndex(of: self), i > 0 else { return nil }
        return all[i - 1]
    }
}
