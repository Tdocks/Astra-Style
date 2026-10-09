//
//  StudioRepository.swift
//  AstraStyle
//
//  Owns `studio_generations` (spec §9) and the Style Studio generation
//  pipeline (spec §13, §14 `studio/generate` + `studio/status/:id`).
//

import Foundation

public protocol StudioRepository: Sendable {
    func fetchQuota() async throws -> StudioQuota
    func fetchGenerations() async throws -> [StudioGeneration]
    /// Loads a page of visible generations. Implementations should use stable
    /// ordering and exclude soft-deleted rows.
    func fetchGenerations(offset: Int, limit: Int) async throws -> [StudioGeneration]
    func fetchGeneration(id: UUID) async throws -> StudioGeneration
    func updateImageDescription(id: UUID, description: String) async throws -> StudioGeneration

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
    /// Accepted file removals that the server is still retrying.
    func fetchPendingImageDeletionCount() async throws -> Int

    func fetchLookbooks(offset: Int, limit: Int) async throws -> [StudioLookbook]
    func createLookbook(name: String) async throws -> StudioLookbook
    func renameLookbook(id: UUID, name: String) async throws
    func deleteLookbook(id: UUID) async throws
    func fetchSavedLookbookIDs(generationID: UUID) async throws -> Set<UUID>
    func fetchLookbookGenerations(lookbookID: UUID, offset: Int, limit: Int) async throws -> [StudioGeneration]
    func saveGeneration(id: UUID, to lookbookID: UUID) async throws
    func removeGeneration(id: UUID, from lookbookID: UUID) async throws
}

public extension StudioRepository {
    func fetchQuota() async throws -> StudioQuota { throw AstraError.server("Couldn't load your preview allowance.") }
    func updateImageDescription(id: UUID, description: String) async throws -> StudioGeneration {
        throw AstraError.server("Image descriptions are unavailable.")
    }
    func fetchPendingImageDeletionCount() async throws -> Int { 0 }
    // Existing narrow test doubles need only implement their tested operations.
    // Live and offline repositories implement the complete collection contract.
    func fetchLookbooks(offset: Int, limit: Int) async throws -> [StudioLookbook] { throw AstraError.server("Collections are unavailable.") }
    func createLookbook(name: String) async throws -> StudioLookbook { throw AstraError.server("Collections are unavailable.") }
    func renameLookbook(id: UUID, name: String) async throws { throw AstraError.server("Collections are unavailable.") }
    func deleteLookbook(id: UUID) async throws { throw AstraError.server("Collections are unavailable.") }
    func fetchSavedLookbookIDs(generationID: UUID) async throws -> Set<UUID> { throw AstraError.server("Collections are unavailable.") }
    func fetchLookbookGenerations(lookbookID: UUID, offset: Int, limit: Int) async throws -> [StudioGeneration] { throw AstraError.server("Collections are unavailable.") }
    func saveGeneration(id: UUID, to lookbookID: UUID) async throws { throw AstraError.server("Collections are unavailable.") }
    func removeGeneration(id: UUID, from lookbookID: UUID) async throws { throw AstraError.server("Collections are unavailable.") }
    /// Compatibility implementation for in-memory repositories. The live
    /// repository overrides this with a server-side range query.
    func fetchGenerations(offset: Int, limit: Int) async throws -> [StudioGeneration] {
        let all = try await fetchGenerations().filter { !$0.isDeleted }
        guard offset < all.count else { return [] }
        return Array(all.dropFirst(offset).prefix(limit))
    }
}

public struct StudioQuota: Decodable, Sendable, Equatable {
    public let premium: Bool
    public let limit: Int
    public let used: Int
    public let remaining: Int
    public let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case premium, limit, used, remaining
        case resetsAt = "resets_at"
    }

    public init(premium: Bool, limit: Int, used: Int, remaining: Int, resetsAt: Date?) {
        self.premium = premium
        self.limit = limit
        self.used = used
        self.remaining = remaining
        self.resetsAt = resetsAt
    }

    public var summary: String {
        if let resetsAt {
            return "\(remaining) of \(limit) previews remaining. Resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))."
        }
        return remaining > 0 ? "Your free preview is available." : "Your free preview has been used. Premium includes a monthly preview allowance."
    }
}
