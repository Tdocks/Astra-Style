//
//  AppearanceEditorViewModel.swift
//  AstraStyle
//
//  Post-onboarding editor for §6.7. Release first-run deliberately defers
//  appearance (ADR 0015), so Profile is the required second chance to supply
//  or correct it.
//

import Foundation
import Observation

@MainActor
@Observable
public final class AppearanceEditorViewModel {
    public enum Phase: Sendable {
        case loading
        case ready
        case saving
        case failed(AstraError)
    }

    public private(set) var phase: Phase = .loading
    public var appearance = AppearanceProfile()
    public private(set) var confirmation: String?

    private let profileRepository: ProfileRepository
    private var bodyProfile: BodyProfile?

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
            async let bodyTask = profileRepository.fetchBodyProfile()
            let profile = try await profileTask
            let body = try await bodyTask ?? BodyProfile(userID: profile.id)
            bodyProfile = body
            appearance = body.appearance
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
        guard var bodyProfile, !isSaving else { return }
        phase = .saving
        confirmation = nil
        bodyProfile.appearance = appearance
        do {
            let stored = try await profileRepository.updateBodyProfile(bodyProfile)
            self.bodyProfile = stored
            appearance = stored.appearance
            do {
                _ = try await profileRepository.generateStyleDNA()
                confirmation = String(
                    localized: "Saved. Your Style DNA now uses these details.",
                    comment: "Appearance editor save confirmation"
                )
            } catch {
                // The structured answer is already safely stored. Do not tell
                // the user it failed; name the narrower refresh delay.
                confirmation = String(
                    localized: "Saved. Style DNA will refresh the next time Kyra updates it.",
                    comment: "Appearance saved but Style DNA refresh delayed"
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
