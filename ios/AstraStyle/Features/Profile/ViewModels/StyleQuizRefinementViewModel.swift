import Foundation
import Observation

@MainActor
@Observable
final class StyleQuizRefinementViewModel {
    enum Phase: Sendable {
        case loading
        case ready
        case saving
        case saved
        case failed(String)
        case savedDNAUpdateFailed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var draft = OnboardingDraft()
    private(set) var engine = StyleQuizEngine(catalog: .bundled(), session: .fullRefinement)
    private let profileRepository: ProfileRepository
    private let currentOwnerID: @Sendable () async -> UUID?
    private var ownerID: UUID?
    private var profile: StyleProfile?
    private var didPersistAnswers = false

    init(
        profileRepository: ProfileRepository,
        currentOwnerID: @escaping @Sendable () async -> UUID?
    ) {
        self.profileRepository = profileRepository
        self.currentOwnerID = currentOwnerID
    }

    var canSave: Bool {
        engine.isFinished(given: draft.quizAnswers)
            && engine.answeredCount(given: draft.quizAnswers) == engine.comparisonCount
            && !engine.hasNothingToAsk
    }

    func choose(pairID: String, optionID: String) {
        guard case .ready = phase,
              let answers = engine.recording(
                pairID: pairID,
                optionID: optionID,
                into: draft.quizAnswers
              ) else { return }
        draft.quizAnswers = answers
    }

    func undoLastAnswer() {
        guard case .ready = phase else { return }
        draft.quizAnswers = engine.undoingLastAnswer(in: draft.quizAnswers)
    }

    func restartQuiz() {
        guard case .ready = phase else { return }
        draft.quizAnswers = []
    }

    func retryLoad() async {
        guard case .failed = phase else { return }
        phase = .loading
        await load()
    }

    func load() async {
        guard case .loading = phase else { return }
        do {
            guard let owner = await currentOwnerID() else {
                throw AstraError.auth("Sign in to refine your taste.")
            }
            let current = try await profileRepository.fetchCurrentProfile()
            guard await currentOwnerID() == owner, current.id == owner else {
                throw AstraError.auth("Your account changed. Reopen Profile to continue.")
            }
            let style = try await profileRepository.fetchStyleProfile()
            guard await currentOwnerID() == owner,
                  style == nil || style?.userID == owner else {
                throw AstraError.auth("Your account changed. Reopen Profile to continue.")
            }
            ownerID = owner
            profile = style ?? StyleProfile(userID: owner)
            engine = StyleQuizEngine(
                catalog: .bundled(for: current.wardrobeGraph),
                session: .fullRefinement
            )
            // Carry forward first-run answers that still belong to this exact
            // catalog. The refinement asks every remaining pair and replaces
            // the full record atomically only when all pairs have a choice.
            var carriedAnswers: [StylePreferenceQuizAnswer] = []
            for answer in style?.preferenceQuizAnswers ?? [] {
                if let updated = engine.recording(
                    pairID: answer.pairID,
                    optionID: answer.chosenOptionID,
                    into: carriedAnswers
                ) {
                    carriedAnswers = updated
                }
            }
            draft.quizAnswers = carriedAnswers
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func save() async {
        guard case .ready = phase, canSave, var updated = profile, let ownerID else { return }
        phase = .saving
        updated.preferenceQuizAnswers = draft.quizAnswers
        updated.preferenceVector = engine.vector(from: draft.quizAnswers)
        do {
            guard await currentOwnerID() == ownerID else {
                throw AstraError.auth("Your account changed. Reopen Profile to continue.")
            }
            _ = try await profileRepository.updateStyleProfile(updated)
            guard await currentOwnerID() == ownerID else {
                didPersistAnswers = true
                phase = .failed("Your answers were saved. Your account changed; reopen Profile to continue.")
                return
            }
            profile = updated
            didPersistAnswers = true
            do {
                _ = try await profileRepository.generateStyleDNA()
                guard await currentOwnerID() == ownerID else {
                    phase = .failed("Your account changed. Reopen Profile to continue.")
                    return
                }
                phase = .saved
            } catch {
                phase = .savedDNAUpdateFailed(error.localizedDescription)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// A DNA retry is deliberately separate from the profile write so a
    /// transient generation failure never duplicates or replaces quiz answers.
    func retryStyleDNA() async {
        guard case .savedDNAUpdateFailed = phase, didPersistAnswers, let ownerID else { return }
        guard await currentOwnerID() == ownerID else {
            phase = .savedDNAUpdateFailed("Your account changed. Reopen Profile to continue.")
            return
        }
        phase = .saving
        do {
            _ = try await profileRepository.generateStyleDNA()
            guard await currentOwnerID() == ownerID else {
                phase = .failed("Your account changed. Reopen Profile to continue.")
                return
            }
            phase = .saved
        } catch {
            phase = .savedDNAUpdateFailed(error.localizedDescription)
        }
    }
}
