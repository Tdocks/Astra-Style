//
//  OnboardingStep.swift
//  AstraStyle
//
//  Every onboarding screen the product owns, plus the first-run sequence
//  ADR 0015 actually walks.
//
//  `allCases` is declaration order — the full specified wall, including
//  deferred screens (goals, measurements, appearance, lifestyle, reference).
//  Those cases stay so later Profile/Home prompts can reuse the same views
//  without inventing a second flow. First-run navigation, progress, and
//  resumption read `activeSequence`, not `allCases`.
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
    // The two capture steps have no §6.x screen section of their own.
    // They stay in declaration order for Comparable / draft clamping.
    // First-run navigation uses `activeSequence` (ADR 0015), not `allCases`.
    case reference      // §5.1 step 11 — optional selfie/body reference capture
    case firstItems     // §5.1 step 12 — add first closet items, or skip
    case result         // §6.10 Style DNA result

    public var id: String { rawValue }

    public static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.declarationIndex < rhs.declarationIndex
    }

    /// Position in `allCases`. Used for Comparable and for clamping a restored
    /// draft that parked on a deferred step. Navigation itself uses
    /// `activeSequence`.
    var declarationIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Intro → identity → quiz → first items → result. The dogfood front door
    /// (ADR 0015). Everything else in `allCases` is deferred, not deleted.
    public static let firstRunSequence: [OnboardingStep] = [
        .intro, .identity, .quiz, .firstItems, .result
    ]

    /// First-run unless Debug launched with `-astra-full-onboarding`, which
    /// restores the specified wall so consent-gate tests can still reach
    /// the reference step.
    public static var activeSequence: [OnboardingStep] {
        AstraFeatureFlags.includesDeferredOnboardingSteps
            ? Array(allCases)
            : firstRunSequence
    }

    /// Steps the user answers on the active sequence. Excludes `intro` and
    /// `result`, so the progress indicator counts what a user would count.
    public static var answerableSteps: [OnboardingStep] {
        activeSequence.filter { $0 != .intro && $0 != .result }
    }

    /// Jump a restored draft off a deferred step onto the next first-run
    /// screen. A man who got as far as measurements on an older build must
    /// not resume onto a screen the current front door does not walk — and
    /// must not be sent back to identity after he already answered it.
    public func clampedToActiveSequence() -> OnboardingStep {
        let sequence = Self.activeSequence
        if sequence.contains(self) { return self }
        return sequence.first { $0 > self } ?? sequence.last ?? .result
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
        case .reference: String(localized: "A photo of you", comment: "Onboarding step title")
        case .firstItems: String(localized: "Your first few pieces", comment: "Onboarding step title")
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
            // Was "These only affect colour suggestions" — which the screen then
            // contradicted twice, since facial hair drives collar suggestions
            // and tattoo visibility drives sleeve length. A user reading
            // carefully got two different accounts of what his data does, on a
            // screen collecting appearance data. Says only what is true now.
            String(localized: "Entirely optional. Every question here says what it's for, and you can leave all of them blank.",
                   comment: "Onboarding step rationale")
        case .lifestyle:
            String(localized: "Where you go and what you spend shapes what's actually useful to recommend.",
                   comment: "Onboarding step rationale")
        case .quiz:
            String(localized: "Three quick comparisons. There is no right answer. The rest can wait.",
                   comment: "Onboarding step rationale")
        case .reference:
            // Deliberately leads with "nothing here needs it". A stylist app
            // asking for a photograph of your face has to make the no-thanks
            // path the obvious one, not the grudging one — see
            // `OnboardingReferenceView`'s header.
            String(localized: "Optional, and nothing else in Astra needs it. The next screen says exactly what would happen to the photo before you choose.",
                   comment: "Onboarding step rationale")
        case .firstItems:
            String(localized: "Photograph one to three things you own, or skip — Home is waiting either way.",
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
        let sequence = Self.activeSequence
        if let i = sequence.firstIndex(of: self) {
            guard i + 1 < sequence.count else { return nil }
            return sequence[i + 1]
        }
        let clamped = clampedToActiveSequence()
        return clamped == self ? nil : clamped
    }

    public var previous: OnboardingStep? {
        let sequence = Self.activeSequence
        guard let i = sequence.firstIndex(of: self), i > 0 else { return nil }
        return sequence[i - 1]
    }
}
