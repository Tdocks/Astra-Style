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
    private var lookbooks: [UUID: StudioLookbook] = [:]
    private var savedGenerationIDs: [UUID: [UUID]] = [:]
    private var collectionSaveFailures = 0
    private let quotaExhausted: Bool
    private let monthlyQuotaExhausted: Bool
    private var failFirstGeneration: Bool
    private var retryCount = 0
    private var pendingDeletionCount = 0

    public func setPendingImageDeletionCount(_ count: Int) { pendingDeletionCount = max(0, count) }
    public func fetchPendingImageDeletionCount() async throws -> Int { pendingDeletionCount }

    public init(quotaExhausted: Bool = false, monthlyQuotaExhausted: Bool = false, failFirstGeneration: Bool = false, pendingImageDeletionCount: Int = 0, referencePhotoPath: String? = nil, chatPreviewID: UUID? = nil) {
        self.quotaExhausted = quotaExhausted
        self.monthlyQuotaExhausted = monthlyQuotaExhausted
        self.failFirstGeneration = failFirstGeneration
        self.pendingDeletionCount = max(0, pendingImageDeletionCount)
        if let chatPreviewID {
            generations[chatPreviewID] = StudioGeneration(
                id: chatPreviewID, userID: SampleData.userID, referenceImagePath: "", status: .queued
            )
        }
        if let referencePhotoPath {
            var source = referencePhotoPath
            for _ in 0..<3 {
                let id = UUID()
                let result = "users/\(SampleData.userID.uuidString.lowercased())/studio/\(id.uuidString.lowercased())/result.png"
                generations[id] = StudioGeneration(id: id, userID: SampleData.userID, referenceImagePath: source,
                    status: .complete, resultImagePath: result)
                source = result
            }
        }
    }

    public func seed(_ generation: StudioGeneration) {
        generations[generation.id] = generation
    }

    public func updateImageDescription(id: UUID, description: String) async throws -> StudioGeneration {
        guard var generation = generations[id], generation.userID == SampleData.userID,
              generation.status == .complete, !generation.isDeleted else {
            throw AstraError.validation("That estimate is no longer available.")
        }
        generation.altDescription = try StudioGeneration.validatedDescription(description)
        generations[id] = generation
        return generation
    }

    public func fetchLookbooks(offset: Int, limit: Int) async throws -> [StudioLookbook] {
        guard offset >= 0, (1...100).contains(limit) else { throw AstraError.validation("That collection page is invalid.") }
        return Array(lookbooks.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt
        }.dropFirst(offset).prefix(limit))
    }

    public func createLookbook(name: String) async throws -> StudioLookbook {
        let row = StudioLookbook(id: UUID(), userID: SampleData.userID, name: try StudioLookbook.validatedName(name))
        lookbooks[row.id] = row
        return row
    }

    public func renameLookbook(id: UUID, name: String) async throws {
        guard var row = lookbooks[id] else { throw AstraError.validation("That collection is unavailable.") }
        row.name = try StudioLookbook.validatedName(name)
        lookbooks[id] = row
    }

    public func deleteLookbook(id: UUID) async throws {
        lookbooks[id] = nil
        savedGenerationIDs[id] = nil
    }

    public func fetchSavedLookbookIDs(generationID: UUID) async throws -> Set<UUID> {
        guard let generation = generations[generationID], !generation.isDeleted else { return [] }
        return Set(savedGenerationIDs.filter { $0.value.contains(generationID) }.map(\.key))
    }

    public func fetchLookbookGenerations(lookbookID: UUID, offset: Int, limit: Int) async throws -> [StudioGeneration] {
        guard lookbooks[lookbookID] != nil else { throw AstraError.validation("That collection is unavailable.") }
        guard offset >= 0, (1...100).contains(limit) else { throw AstraError.validation("That collection page is invalid.") }
        return Array((savedGenerationIDs[lookbookID] ?? []).compactMap { generations[$0] }
            .filter { $0.status == .complete && !$0.isDeleted }.dropFirst(offset).prefix(limit))
    }

    public func saveGeneration(id: UUID, to lookbookID: UUID) async throws {
        guard lookbooks[lookbookID] != nil, let generation = generations[id],
              generation.status == .complete, !generation.isDeleted, generation.resultImagePath != nil,
              generation.userID == SampleData.userID else {
            throw AstraError.validation("Choose an available completed estimate.")
        }
        if collectionSaveFailures > 0 {
            collectionSaveFailures -= 1
            throw AstraError.network("Couldn't save this look. Try again.")
        }
        if !(savedGenerationIDs[lookbookID] ?? []).contains(id) {
            savedGenerationIDs[lookbookID, default: []].insert(id, at: 0)
        }
    }

    public func removeGeneration(id: UUID, from lookbookID: UUID) async throws {
        savedGenerationIDs[lookbookID]?.removeAll { $0 == id }
    }

    public func failNextCollectionSave() { collectionSaveFailures += 1 }

    public func fetchQuota() async throws -> StudioQuota {
        let used = monthlyQuotaExhausted ? 20 : generations.count
        return StudioQuota(premium: true, limit: 20, used: used, remaining: max(0, 20 - used), resetsAt: Calendar.current.date(byAdding: .month, value: 1, to: .now))
    }

    public func fetchGenerations() async throws -> [StudioGeneration] {
        Array(generations.values).sorted { $0.createdAt > $1.createdAt }
    }

    public func fetchGeneration(id: UUID) async throws -> StudioGeneration {
        guard let generation = generations[id] else { throw AstraError.server("That generation couldn't be found.") }
        return generation
    }

    public func startGeneration(_ request: StudioGenerationRequest) async throws -> StudioGeneration {
        guard request.inspirationMode != nil || request.hasUserConsent else {
            throw AstraError.validation("Please confirm you have permission to use this photo before generating a preview.")
        }
        guard request.inspirationMode != nil || request.consentTermsVersion == StudioConsentTerms.currentVersion else {
            throw AstraError.validation("Those consent terms are out of date. Read them again before generating.")
        }
        if monthlyQuotaExhausted {
            throw AstraError.rateLimited("You've used your monthly preview allowance. It resets on the first day of next month (UTC).")
        }
        if quotaExhausted {
            throw AstraError.rateLimited("You've used your free visual estimate. Upgrade to Astra Style Premium for more.")
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
        if failFirstGeneration {
            failFirstGeneration = false
            generation.status = .failed
            generation.errorMessage = "The preview service could not finish."
            generation.promptPayload = .object(["is_retryable_failure": .bool(true)])
            generations[generationID] = generation
            return generation
        }
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
        retryCount += 1
        generation.status = .queued
        generation.errorMessage = nil
        generation.promptPayload = .object(["is_retryable_failure": .bool(false)])
        generations[id] = generation
        return generation
    }

    public func retryCountValue() -> Int {
        retryCount
    }

    public func deleteGeneration(id: UUID) async throws {
        guard let generation = generations[id] else { return }
        guard generation.status == .complete || generation.status == .failed else {
            throw AstraError.validation("Wait for this estimate to finish before deleting it.")
        }
        if let path = generation.resultImagePath,
           generations.values.contains(where: { $0.id != id && !$0.isDeleted && $0.referenceImagePath == path }) {
            throw AstraError.validation("Another variation uses this image. Delete its newer variations first, then try again.")
        }
        generations[id] = nil
        for key in savedGenerationIDs.keys { savedGenerationIDs[key]?.removeAll { $0 == id } }
    }
}
