//
//  OnboardingViewModel.swift
//  AstraStyle
//
//  Drives the §6.3–§6.10 flow: step navigation, draft persistence, and the
//  single submission at the end.
//
//  The guest case is the one that shapes this class. Per ADR 0011 a guest has
//  no server profile, so `completeOnboarding` cannot be called for one — but a
//  guest absolutely may work through onboarding, and throwing away his answers
//  at the account-creation prompt would be the worst possible moment to lose
//  them. So the draft is the source of truth throughout and submission is a
//  separate, later act: guests finish the flow locally, and the draft is
//  submitted by `GuestMigrationService` when the account appears.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class OnboardingViewModel {

    public enum SubmissionState: Equatable {
        case idle
        case submitting
        /// Finished locally. A guest reaches this and stops here — his answers
        /// are saved and will be sent when he creates an account.
        case savedLocally
        case succeeded
        case failed(String)
    }

    public private(set) var step: OnboardingStep
    public var draft: OnboardingDraft
    public private(set) var submission: SubmissionState = .idle

    /// The §6.9 comparison set and its sequencing, held here rather than in the
    /// quiz view because the flow's own chrome depends on it: the forward
    /// button's label has to distinguish "skip the whole thing" from "skip the
    /// three you have left", and it cannot do that without knowing how many
    /// comparisons exist.
    public let quizEngine: StyleQuizEngine

    private let store: any OnboardingDraftStoring
    private let profileRepository: any ProfileRepository
    private let sessionStore: SessionStore
    private let logger = Logger(subsystem: "com.astrastyle.app", category: "onboarding")

    /// - Parameter quizCatalog: Defaults to what is in the bundle. Loading it
    ///   here is a few kilobytes of JSON and six bundle lookups on a screen the
    ///   user has not reached yet; it is synchronous so that "how many
    ///   comparisons are there" is answerable the instant the flow is built,
    ///   which every honest progress label on this step depends on. Injectable
    ///   so tests can drive the flow with a comparison set they control.
    public init(
        store: any OnboardingDraftStoring,
        profileRepository: any ProfileRepository,
        sessionStore: SessionStore,
        draft: OnboardingDraft = OnboardingDraft(),
        step: OnboardingStep = .intro,
        quizCatalog: StyleQuizCatalog = .bundled()
    ) {
        self.store = store
        self.profileRepository = profileRepository
        self.sessionStore = sessionStore
        self.draft = draft
        self.step = step
        self.quizEngine = StyleQuizEngine(catalog: quizCatalog)
    }

    // MARK: - Lifecycle

    /// Restores a saved draft and reopens at the furthest step reached.
    ///
    /// Resumes at `furthestStepReached` rather than at the first unanswered
    /// step: a user who deliberately skipped his inseam should not be dropped
    /// back onto it every time he reopens the app, which would read as the app
    /// refusing to accept his answer.
    public func restore() async {
        guard let saved = await store.load() else { return }
        draft = saved
        step = saved.furthestStepReached
    }

    // MARK: - Navigation

    public var canGoBack: Bool { step.previous != nil }

    /// Whether Continue is enabled. Only §6.5 gates it — see
    /// `OnboardingStep.isSkippable`.
    public var canAdvance: Bool {
        switch step {
        case .identity: draft.hasCompleteIdentitySelection
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
        // "next question". Saying "Continue" while three comparisons are still
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
        case .goals: !draft.goals.isEmpty
        case .identity: !draft.selectedIdentities.isEmpty
        case .measurements:
            [draft.height, draft.weight, draft.chest, draft.waist, draft.inseam, draft.neck]
                .contains(where: \.isAnswered)
                || draft.shoeSize != nil || draft.shirtSize != nil || draft.trouserSize != nil
                || draft.preferredFit != nil || !draft.fitIssues.isEmpty
        case .appearance:
            draft.skinUndertone != nil || draft.hairColor != nil || draft.eyeColor != nil
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
        }
    }

    public func advance() async {
        guard canAdvance else { return }
        guard let next = step.next else {
            await submit()
            return
        }
        step = next
        if next > draft.furthestStepReached {
            draft.furthestStepReached = next
        }
        await persist()
    }

    public func goBack() async {
        guard let previous = step.previous else { return }
        // `furthestStepReached` is deliberately NOT rewound. Going back to
        // change an answer should not cost the user the progress he already
        // made, and rewinding it would make a resumed session reopen earlier
        // than he actually got to.
        step = previous
        await persist()
    }

    /// Called after each edit so a draft survives the app being killed.
    public func persist() async {
        await store.save(draft)
    }

    // MARK: - Submission

    public func submit() async {
        submission = .submitting

        let isGuest = await sessionStore.currentIsGuest()
        guard let userID = await currentUserID() else {
            // No session at all. Should be unreachable — onboarding is only
            // routed to when authenticated — but failing loudly beats writing a
            // payload with a fabricated user id.
            submission = .failed(
                String(localized: "You need to be signed in to save this.",
                       comment: "Onboarding submission error")
            )
            return
        }

        if isGuest {
            // ADR 0011: a guest has no server profile, so there is nothing to
            // PATCH. Keep the draft — GuestMigrationService submits it once an
            // account exists. Answers are not lost and nothing is silently
            // dropped on the floor.
            draft.furthestStepReached = .result
            await persist()
            submission = .savedLocally
            return
        }

        do {
            _ = try await profileRepository.completeOnboarding(
                draft.completionPayload(userID: userID, quizCatalog: quizEngine.catalog)
            )
            // Only clear the draft AFTER the server has accepted it. Clearing
            // optimistically would lose every answer if the request failed on a
            // flaky connection, which is exactly when it is most likely to.
            await store.clear()
            submission = .succeeded
        } catch {
            logger.error("completeOnboarding failed: \(error.localizedDescription)")
            submission = .failed(error.localizedDescription)
        }
    }

    /// Retry after a failure. The draft is intact, so this is safe to call
    /// repeatedly.
    public func retrySubmission() async {
        guard case .failed = submission else { return }
        await submit()
    }

    private func currentUserID() async -> UUID? {
        if let guestID = await sessionStore.currentGuestUserID() { return guestID }
        return await MainActor.run { sessionStore.currentSession?.userID }
    }
}
