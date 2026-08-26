//
//  PreferencesEditorViewModel.swift
//  AstraStyle
//
//  Post-onboarding editor for identity and visual quiz answers.
//

import Foundation
import Observation

@MainActor
@Observable
public final class PreferencesEditorViewModel {
    public enum Phase: Sendable {
        case loading
        case ready
        case saving
        case failed(AstraError)
    }

    public private(set) var phase: Phase = .loading
    public var draft = OnboardingDraft()
    public private(set) var quizEngine = StyleQuizEngine(catalog: .bundled())
    public private(set) var confirmation: String?

    private let profileRepository: ProfileRepository
    private var styleProfile: StyleProfile?
    private var lifestyleProfile: LifestyleProfile?

    public init(profileRepository: ProfileRepository) {
        self.profileRepository = profileRepository
    }

    public var isSaving: Bool {
        if case .saving = phase { return true }
        return false
    }

    public func load() async {
        guard case .loading = phase else { return }
        do {
            async let profileTask = profileRepository.fetchCurrentProfile()
            async let styleTask = profileRepository.fetchStyleProfile()
            async let lifestyleTask = profileRepository.fetchLifestyleProfile()
            let profile = try await profileTask
            let style = try await styleTask
            let lifestyle = try await lifestyleTask ?? LifestyleProfile(userID: profile.id)

            styleProfile = style ?? StyleProfile(userID: profile.id)
            lifestyleProfile = lifestyle

            if let style {
                draft.selectedIdentities = style.secondaryIdentities
                if let primary = style.primaryIdentity {
                    if !draft.selectedIdentities.contains(primary) {
                        draft.selectedIdentities.insert(primary, at: 0)
                    }
                    draft.primaryIdentity = primary
                }
                draft.goals = Set(style.styleGoals.compactMap(StyleGoal.init(rawValue:)))
            }
            draft.dressCode = lifestyle.dressCode
            draft.commonOccasions = lifestyle.commonOccasions
            draft.typicalWeek = lifestyle.typicalWeek
            draft.occupationCategory = lifestyle.occupationCategory

            quizEngine = StyleQuizEngine(catalog: .bundled(for: draft.wardrobeGraph ?? .menswear3Role))
            phase = .ready
        } catch {
            phase = .failed(asAstraError(error))
        }
    }

    public func retry() async {
        phase = .loading
        await load()
    }

    public func save() async {
        guard var styleProfile, var lifestyleProfile, !isSaving else { return }
        phase = .saving
        confirmation = nil

        styleProfile.primaryIdentity = draft.primaryIdentity
        styleProfile.secondaryIdentities = draft.selectedIdentities.filter { $0 != draft.primaryIdentity }
        styleProfile.styleGoals = draft.goals.map(\.rawValue).sorted()
        styleProfile.preferenceVector = quizEngine.vector(from: draft.quizAnswers)

        lifestyleProfile.dressCode = draft.dressCode
        lifestyleProfile.commonOccasions = draft.commonOccasions
        lifestyleProfile.typicalWeek = draft.typicalWeek
        lifestyleProfile.occupationCategory = draft.occupationCategory

        do {
            _ = try await profileRepository.updateStyleProfile(styleProfile)
            _ = try await profileRepository.updateLifestyleProfile(lifestyleProfile)
            self.styleProfile = styleProfile
            self.lifestyleProfile = lifestyleProfile
            do {
                _ = try await profileRepository.generateStyleDNA()
                confirmation = String(
                    localized: "Saved. Your Style DNA now uses these answers.",
                    comment: "Preferences save confirmation"
                )
            } catch {
                confirmation = String(
                    localized: "Saved. Style DNA will refresh the next time Kyra updates it.",
                    comment: "Preferences saved but DNA delayed"
                )
            }
            phase = .ready
        } catch {
            phase = .failed(asAstraError(error))
        }
    }

    private func asAstraError(_ error: Error) -> AstraError {
        if let error = error as? AstraError { return error }
        return AstraError(category: .unknown, message: error.localizedDescription)
    }
}
