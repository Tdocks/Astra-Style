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
//  WHY SUBMISSION MOVED TO THE START OF §6.10 RATHER THAN THE END OF IT.
//
//  It used to run when the user tapped forward OFF the result step, which was
//  correct while that step was a stub. It cannot stay there now that the step
//  shows Style DNA, because `POST /style-dna/generate` deliberately sends no
//  body — it reads the profile rows the client has already written (see
//  `LiveProfileRepository.generateStyleDNA`). Generating before submitting
//  would therefore read an empty or stale `style_profiles` row and hand every
//  brand-new user a null identity: the screen would render the server's
//  honest "not enough to call a direction" state for a man who had just
//  answered seven screens of questions. So `loadStyleDNA()` submits first and
//  generates second, and the forward button on §6.10 only leaves the flow.
//
//  WHY THE REFERENCE PHOTO (§5.1 step 11) IS UPLOADED HERE AND NOT AT CAPTURE.
//  See `uploadReferenceImageIfNeeded()`. In short: an image uploaded the moment
//  it is picked is an image that exists on a server for every user who then
//  backs out, force-quits, or changes his mind — exactly ADR 0010's "abandoned
//  upload", whose cleanup is a scheduled sweep that has not been built. Nothing
//  is uploaded until the man has committed to finishing.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class OnboardingViewModel {

    public private(set) var step: OnboardingStep
    public var draft: OnboardingDraft
    public private(set) var submission: SubmissionState = .idle
    public private(set) var styleDNAState: StyleDNAState = .idle

    // MARK: §5.1 step 11 — reference photo

    /// The chosen photo's bytes, held for the preview the capture step draws.
    ///
    /// Not on the draft: the draft is re-encoded to disk on every mutation of
    /// every later screen, and a JPEG inside it would be rewritten on each
    /// keystroke. `ReferenceImageStore` owns the bytes; the draft owns the
    /// filename.
    public internal(set) var referenceImageData: Data?

    /// Set when the upload during submission failed. Non-blocking by design —
    /// see `uploadReferenceImageIfNeeded()`; the answers still reach the
    /// server, and §6.10 offers a retry for this one thing.
    public internal(set) var referenceUploadFailure: String?

    // MARK: §5.1 step 12 — first closet items

    /// Items created during THIS step, newest first.
    ///
    /// Deliberately not "the user's closet". A signed-in user may already own
    /// items, and listing them here would turn an onboarding step into a
    /// closet browser — `P3-CLOSET-08` owns that screen. What belongs on this
    /// screen is what this screen just did.
    public internal(set) var firstItems: [ClosetItem] = []
    public var newItemName: String = ""
    public var newItemCategory: ClothingCategory?
    public var newItemColor: String = ""
    public internal(set) var addItemState: AddItemState = .idle

    /// How many more a guest may add (spec §6.2's 10-item cap), or nil when
    /// the cap does not apply. Read once when the step opens: the cap counts
    /// items already in local guest storage, not just the ones added here, so
    /// a resumed session must not restart the count at zero.
    public internal(set) var guestItemsRemaining: Int?

    /// Set once the user has finished the flow and the app should move on.
    ///
    /// Routing used to hang off `submission` reaching `.succeeded`, which was
    /// fine while submission happened on the way OUT of §6.10. Now that it
    /// happens on the way IN, that same signal would fire the instant the
    /// result screen loaded and bounce the user past the screen the whole flow
    /// exists to reach.
    public private(set) var isFinished = false

    /// The §6.9 comparison set and its sequencing, held here rather than in the
    /// quiz view because the flow's own chrome depends on it: the forward
    /// button's label has to distinguish "skip the whole thing" from "skip the
    /// three you have left", and it cannot do that without knowing how many
    /// comparisons exist.
    public let quizEngine: StyleQuizEngine

    // Internal rather than private: the two step-specific halves of this
    // type live in `OnboardingViewModel+Reference.swift` and
    // `OnboardingViewModel+FirstItems.swift`, and `private` is file-scoped.
    // Split by step rather than kept in one 900-line class, because the §29
    // consent-and-upload rules are the thing a reviewer needs to be able to
    // find without reading the navigation code.
    let store: any OnboardingDraftStoring
    let profileRepository: any ProfileRepository
    let closetRepository: any ClosetRepository
    let referenceStore: any ReferenceImageStoring
    let sessionStore: SessionStore
    let logger = Logger(subsystem: "com.astrastyle.app", category: "onboarding")

    /// - Parameter quizCatalog: Defaults to what is in the bundle. Loading it
    ///   here is a few kilobytes of JSON and six bundle lookups on a screen the
    ///   user has not reached yet; it is synchronous so that "how many
    ///   comparisons are there" is answerable the instant the flow is built,
    ///   which every honest progress label on this step depends on. Injectable
    ///   so tests can drive the flow with a comparison set they control.
    public init(
        store: any OnboardingDraftStoring,
        profileRepository: any ProfileRepository,
        closetRepository: any ClosetRepository,
        referenceStore: any ReferenceImageStoring,
        sessionStore: SessionStore,
        draft: OnboardingDraft = OnboardingDraft(),
        step: OnboardingStep = .intro,
        quizCatalog: StyleQuizCatalog = .bundled()
    ) {
        self.store = store
        self.profileRepository = profileRepository
        self.closetRepository = closetRepository
        self.referenceStore = referenceStore
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
        await restoreReferenceImage()
    }

    /// Reloads the captured photo's bytes, or forgets it if the file is gone.
    ///
    /// The second half matters more than the first. A draft that names a file
    /// which no longer exists would make the capture step claim a photo the
    /// user cannot see and cannot remove, and would put an empty upload in
    /// front of submission. If the bytes are not there, neither is the photo.
    private func restoreReferenceImage() async {
        guard let filename = draft.referenceImageFilename else { return }
        referenceImageData = await referenceStore.load(filename: filename)
        guard referenceImageData == nil else { return }
        draft.referenceImageFilename = nil
        await persist()
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
        // Consent on its own is not an answer. A man who read the explanation,
        // acknowledged it and then decided against a photo has skipped this
        // step, and the forward button should say so.
        case .reference: draft.referenceImageFilename != nil || !draft.referenceStoragePaths.isEmpty
        case .firstItems: !firstItems.isEmpty
        }
    }

    public func advance() async {
        guard canAdvance else { return }
        guard let next = step.next else {
            await finish()
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
        //
        // Leaving §6.10 DOES discard the generated result, and that is the
        // point: going back is the general-purpose edit path (§6.10's "allow
        // user to edit and regenerate" for every input, not just identity), so
        // returning must re-submit the changed answers and re-generate rather
        // than showing a result built from the answers he just changed. The
        // submission state resets with it, because a second `submit()` is
        // exactly what has to happen.
        if step == .result {
            styleDNAState = .idle
            submission = .idle
        }
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
            //
            // This return is also the ONLY thing standing between a guest's
            // photograph and Supabase Storage, which is why the upload below
            // is here rather than on the capture step: one branch, in the one
            // method that already knows whether this session has a server
            // identity, instead of a second guest check on a screen whose
            // author has to remember to write it.
            draft.furthestStepReached = .result
            await persist()
            submission = .savedLocally
            return
        }

        // Before the payload is built, because the payload carries the
        // resulting storage path (`AppearanceProfile.referenceSelfiePaths`).
        // Cannot throw: a failed photo upload must not cost the user seven
        // screens of answers.
        await uploadReferenceImageIfNeeded()

        do {
            _ = try await profileRepository.completeOnboarding(
                draft.completionPayload(userID: userID, quizCatalog: quizEngine.catalog)
            )
            // Only clear the draft AFTER the server has accepted it. Clearing
            // optimistically would lose every answer if the request failed on a
            // flaky connection, which is exactly when it is most likely to.
            await store.clear()
            // The local copy of the photo is redundant the moment the path is
            // in `body_profiles`, and ADR 0010's whole posture is that the
            // standing inventory of face imagery should be as small as it can
            // be. Kept when the upload failed, so the retry has something to
            // send.
            if draft.referenceStoragePaths.isEmpty == false {
                await referenceStore.clear()
            }
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

    // MARK: - Style DNA (spec §6.10)

    /// Saves the answers, then generates the Style DNA the result step draws.
    ///
    /// Called from the result view's `.task`. Guarded on `.idle` so the
    /// re-entry SwiftUI can cause (a `.task` re-running after a state change
    /// higher up) does not fire a second submission and a second billable
    /// generation for one visit to the screen.
    public func loadStyleDNA() async {
        guard case .idle = styleDNAState else { return }
        styleDNAState = .loading

        await submit()

        switch submission {
        case .savedLocally:
            styleDNAState = .guestPreview
        case .succeeded:
            await generate(previous: nil)
        case .failed(let message):
            // The answers did not reach the server, so there is nothing to
            // generate from. Reported as the result step's own failure rather
            // than as a separate overlay, because from the user's side it is
            // one thing that did not work.
            styleDNAState = .failed(message: message, previous: nil)
        case .idle, .submitting:
            styleDNAState = .failed(
                message: String(localized: "That didn't finish saving. Try again.",
                                comment: "Style DNA generation error"),
                previous: nil
            )
        }
    }

    /// Retries after a failure, from whichever half of the work failed.
    public func retryStyleDNA() async {
        guard case .failed(_, let previous) = styleDNAState else { return }
        if case .succeeded = submission {
            // The answers are already saved; only the generation failed. Do not
            // re-submit — it would be a second write of an identical payload.
            styleDNAState = previous.map { .regenerating(previous: $0) } ?? .loading
            await generate(previous: previous)
            return
        }
        styleDNAState = .idle
        await loadStyleDNA()
    }

    /// §6.10's "allow user to edit and regenerate", for the §6.5 answer.
    ///
    /// WHAT IS EDITABLE, AND WHY IT IS THE INPUTS RATHER THAN THE PROSE.
    ///
    /// The spec sentence names no subject, and there are only two readings.
    /// Editing the generated text — retyping the silhouette paragraph, dropping
    /// a signature piece — would make Style DNA stop being a derivation of
    /// anything: the next regenerate silently discards the edit, and until it
    /// does, the screen shows prose attributed to Kyra that Kyra did not write.
    /// Editing the INPUTS keeps the result a function of the answers, which is
    /// the only thing that makes "regenerate" a meaningful verb.
    ///
    /// Of the inputs, identity is the one that gets a shortcut here for three
    /// reasons, not because it was the easiest: §6.5 is the only step the flow
    /// requires; the generator gates the palette, silhouette, signatures and
    /// priorities on it, so nothing else moves the result as far; and the
    /// server says so itself — `composeOpenQuestions` leads with "Which three
    /// style identities look like you. It is the single answer that changes the
    /// most here." Every other input stays editable through Back, which resets
    /// this state and regenerates on the way forward (see `goBack()`), so this
    /// is the shortcut for the highest-leverage answer rather than the only
    /// edit path.
    ///
    /// Two calls, in the order `ProfileRepository` documents: the edit is
    /// written to `style_profiles`, then the endpoint reads it back. One write
    /// path for the user's own answers, not two that can disagree.
    public func regenerate(identities: [StyleIdentity], primary: StyleIdentity?) async {
        // The draft is updated first and unconditionally. Whatever happens to
        // the network call, the man changed his mind and the app should not
        // forget it — and for a guest the draft IS the outcome.
        draft.selectedIdentities = identities
        draft.primaryIdentity = primary
        await persist()

        // ADR 0011: no server profile, so nothing to write and nothing to
        // generate. The screen already says so; this is not a failure.
        if case .guestPreview = styleDNAState { return }

        let previous = currentStyleDNA
        styleDNAState = previous.map { .regenerating(previous: $0) } ?? .loading

        guard let userID = await currentUserID() else {
            styleDNAState = .failed(
                message: String(localized: "You need to be signed in to save this.",
                                comment: "Onboarding submission error"),
                previous: previous
            )
            return
        }

        do {
            // Read-modify-write rather than composing a fresh row from the
            // draft. `updateStyleProfile` upserts the whole record, so building
            // it locally would overwrite the four columns the generator owns
            // (formality, logo, trend, accessory) with nils on every edit.
            let stored = try await profileRepository.fetchStyleProfile()
            var edited = stored ?? draft.styleProfile(userID: userID, quizCatalog: quizEngine.catalog)
            edited.primaryIdentity = primary
            edited.secondaryIdentities = identities.filter { $0 != primary }
            _ = try await profileRepository.updateStyleProfile(edited)
        } catch {
            logger.error("updateStyleProfile failed: \(error.localizedDescription)")
            styleDNAState = .failed(message: error.localizedDescription, previous: previous)
            return
        }

        await generate(previous: previous)
    }

    /// The result currently worth drawing, including the one being replaced.
    public var currentStyleDNA: StyleDNA? {
        switch styleDNAState {
        case .ready(let dna), .regenerating(previous: let dna): dna
        case .failed(_, let previous): previous
        case .idle, .loading, .guestPreview: nil
        }
    }

    /// Whether a generation is in flight, for disabling the controls that would
    /// start a second one.
    public var isWorkingOnStyleDNA: Bool {
        switch styleDNAState {
        case .loading, .regenerating: true
        case .idle, .ready, .failed, .guestPreview: false
        }
    }

    /// Leaves the flow. The forward button on §6.10 does only this.
    ///
    /// It still submits when the answers have not reached the server, because
    /// the alternative is a Finish button that silently drops seven screens of
    /// input when the generation step failed on a bad connection.
    public func finish() async {
        switch submission {
        case .succeeded, .savedLocally:
            isFinished = true
        case .submitting:
            return
        case .idle, .failed:
            await submit()
            switch submission {
            case .succeeded, .savedLocally:
                isFinished = true
            case .failed(let message):
                styleDNAState = .failed(message: message, previous: currentStyleDNA)
            case .idle, .submitting:
                break
            }
        }
    }

    private func generate(previous: StyleDNA?) async {
        do {
            let dna = try await profileRepository.generateStyleDNA()
            styleDNAState = .ready(dna)
        } catch {
            logger.error("generateStyleDNA failed: \(error.localizedDescription)")
            styleDNAState = .failed(message: error.localizedDescription, previous: previous)
        }
    }

    func currentUserID() async -> UUID? {
        if let guestID = await sessionStore.currentGuestUserID() { return guestID }
        return await MainActor.run { sessionStore.currentSession?.userID }
    }
}

// MARK: - The states this flow can be in
//
// Nested in an extension rather than in the class body above, for the same
// reason `AddItemState` lives in `OnboardingViewModel+FirstItems.swift`: these
// are declarations with no behaviour, they are long because each case carries
// an argument that needed explaining, and keeping them inline pushed the class
// past the point where its navigation logic could be read in one pass.
// Callers still spell them `OnboardingViewModel.SubmissionState` and
// `.StyleDNAState`.

public extension OnboardingViewModel {

    enum SubmissionState: Equatable {
        case idle
        case submitting
        /// Finished locally. A guest reaches this and stops here — his answers
        /// are saved and will be sent when he creates an account.
        case savedLocally
        case succeeded
        case failed(String)
    }

    /// The §6.10 result step's own state machine.
    ///
    /// Separate from `SubmissionState` because the two answer different
    /// questions and the result screen needs both: "have this man's answers
    /// reached the server" and "is there a Style DNA to draw". Collapsing them
    /// into one enum forced a `.submitting` case to mean two different things
    /// on one screen — saving answers, and regenerating from edited ones —
    /// which are visually different states (a full-screen wait versus the
    /// previous result held on screen behind a working indicator).
    ///
    /// `regenerating` and `failed` both carry the PREVIOUS result on purpose.
    /// Phase 2's exit criterion is that a user can regenerate and see the
    /// result change; a regenerate that blanks the screen while it works, or
    /// that drops what he already had when the network fails, fails that
    /// criterion in the direction the user notices most.
    enum StyleDNAState: Equatable {
        case idle
        /// Saving the answers, then generating. There is nothing to show yet.
        case loading
        case ready(StyleDNA)
        /// Working from edited inputs, with the previous result still on screen.
        case regenerating(previous: StyleDNA)
        case failed(message: String, previous: StyleDNA?)
        /// ADR 0011: a guest has no server profile, so there is no Style DNA to
        /// generate and no call to make. Not an error and not a loading state —
        /// a real, permanent outcome for this session that the screen names.
        case guestPreview
    }
}
