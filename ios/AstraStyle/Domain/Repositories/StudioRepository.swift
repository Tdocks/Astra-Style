//
//  StudioRepository.swift
//  AstraStyle
//
//  Owns `studio_generations` (spec §9) and the Style Studio generation
//  pipeline (spec §13, §14 `studio/generate` + `studio/status/:id`).
//

import Foundation

public protocol StudioRepository: Sendable {
    func fetchGenerations() async throws -> [StudioGeneration]
    func fetchGeneration(id: UUID) async throws -> StudioGeneration

    /// Enqueues a generation job. Calls `POST /studio/generate`.
    func startGeneration(_ request: StudioGenerationRequest) async throws -> StudioGeneration

    /// Polls job status. Calls `GET /studio/status/:id`. Callers are
    /// expected to poll this on an interval while `status` is
    /// `.queued`/`.generating` (spec §6.17 "Generation states").
    func fetchStatus(generationID: UUID) async throws -> StudioGeneration

    /// Retries a provider-side failure without consuming quota
    /// (spec §21 "Studio failed ... allow retry without consuming another
    /// credit when failure is provider-side").
    func retryGeneration(id: UUID) async throws -> StudioGeneration

    /// Deletes a generation and its stored images (spec §6.17 "Provide
    /// deletion controls", §29).
    func deleteGeneration(id: UUID) async throws
}
