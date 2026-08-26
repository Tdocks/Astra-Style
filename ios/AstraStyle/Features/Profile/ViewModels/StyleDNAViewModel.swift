//
//  StyleDNAViewModel.swift
//  AstraStyle
//
//  Post-onboarding Style DNA reader. Same honest sparse treatment as §6.10.
//

import Foundation
import Observation

@MainActor
@Observable
public final class StyleDNAViewModel {
    public enum Phase: Sendable {
        case loading
        case ready(StyleDNA)
        case regenerating(StyleDNA)
        case failed(String, previous: StyleDNA?)
    }

    public private(set) var phase: Phase = .loading

    private let profileRepository: ProfileRepository

    public init(profileRepository: ProfileRepository) {
        self.profileRepository = profileRepository
    }

    public var isWorking: Bool {
        switch phase {
        case .loading, .regenerating: true
        case .ready, .failed: false
        }
    }

    public func load() async {
        guard case .loading = phase else { return }
        await regenerate(previous: nil)
    }

    public func retry() async {
        let previous: StyleDNA?
        if case .failed(_, let cached) = phase {
            previous = cached
        } else {
            previous = nil
        }
        phase = previous.map { .regenerating($0) } ?? .loading
        await regenerate(previous: previous)
    }

    public func regenerate() async {
        let previous: StyleDNA?
        if case .ready(let dna) = phase {
            previous = dna
        } else if case .failed(_, let cached) = phase {
            previous = cached
        } else {
            previous = nil
        }
        phase = previous.map { .regenerating($0) } ?? .loading
        await regenerate(previous: previous)
    }

    private func regenerate(previous: StyleDNA?) async {
        do {
            let dna = try await profileRepository.generateStyleDNA()
            phase = .ready(dna)
        } catch let error as AstraError {
            phase = .failed(error.message, previous: previous)
        } catch {
            phase = .failed(error.localizedDescription, previous: previous)
        }
    }
}
