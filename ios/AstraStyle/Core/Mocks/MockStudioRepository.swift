//
//  MockStudioRepository.swift
//  AstraStyle
//
//  In-memory `StudioRepository` for previews/tests (spec §31). Simulates
//  the queued -> generating -> complete lifecycle from spec §6.17 without
//  ever calling a real image provider.
//

import Foundation

public actor MockStudioRepository: StudioRepository {
    private var generations: [UUID: StudioGeneration] = [:]

    public init() {}

    public func fetchGenerations() async throws -> [StudioGeneration] {
        Array(generations.values).sorted { $0.createdAt > $1.createdAt }
    }

    public func fetchGeneration(id: UUID) async throws -> StudioGeneration {
        guard let generation = generations[id] else { throw AstraError.server("That generation couldn't be found.") }
        return generation
    }

    public func startGeneration(_ request: StudioGenerationRequest) async throws -> StudioGeneration {
        guard request.hasUserConsent else {
            throw AstraError.validation("Please confirm you have permission to use this photo before generating a preview.")
        }
        let generation = StudioGeneration(
            id: UUID(),
            userID: SampleData.userID,
            referenceImagePath: request.referenceImagePath,
            outfitID: request.outfitID,
            status: .queued,
            provider: "preview-provider"
        )
        generations[generation.id] = generation
        return generation
    }

    public func fetchStatus(generationID: UUID) async throws -> StudioGeneration {
        guard var generation = generations[generationID] else { throw AstraError.server("That generation couldn't be found.") }
        // Advance the simulated pipeline one step each time status is
        // polled, so a preview driving a polling loop sees real state
        // transitions.
        switch generation.status {
        case .queued:
            generation.status = .generating
        case .generating:
            generation.status = .complete
            generation.resultImagePath = "preview/studio-result-\(generationID.uuidString).jpg"
        case .complete, .failed:
            break
        }
        generations[generationID] = generation
        return generation
    }

    public func retryGeneration(id: UUID) async throws -> StudioGeneration {
        guard var generation = generations[id] else { throw AstraError.server("That generation couldn't be found.") }
        generation.status = .queued
        generation.errorMessage = nil
        generations[id] = generation
        return generation
    }

    public func deleteGeneration(id: UUID) async throws {
        generations[id] = nil
    }
}
