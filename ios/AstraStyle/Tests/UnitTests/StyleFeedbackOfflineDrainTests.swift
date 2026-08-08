//
//  StyleFeedbackOfflineDrainTests.swift
//  AstraStyleTests
//
//  P4-OUTFIT-14: `.styleFeedback` is a new `OfflineMutation.Entity` case
//  added alongside `.outfit`/`.outfitWear`. Mirrors
//  `OutfitOfflineDrainWiringTests.swift`'s coverage for the other two
//  cases — a queued `style_feedback` write must actually be replayed by
//  `LiveOutfitRepository+Offline.swift`, not just enqueued and forgotten
//  (the same P1-CORE-06 class of bug that test file exists to catch).
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Offline queue wiring — a queued style_feedback write actually gets replayed")
struct StyleFeedbackOfflineDrainTests {

    private actor StubOutfitWriter: OutfitWriting {
        private var shouldFail: Bool
        private(set) var createdFeedbackIDs: [UUID] = []

        init(shouldFail: Bool) {
            self.shouldFail = shouldFail
        }

        func setShouldFail(_ value: Bool) {
            shouldFail = value
        }

        func updateOutfit(_ outfit: Outfit) async throws -> Outfit { outfit }
        func createWear(_ wear: OutfitWear) async throws -> OutfitWear { wear }

        func createFeedback(_ feedback: StyleFeedback) async throws -> StyleFeedback {
            if shouldFail { throw AstraError.network("offline") }
            createdFeedbackIDs.append(feedback.id)
            return feedback
        }
    }

    private func makeRepository(
        queue: InMemoryOfflineMutationQueue,
        writer: some OutfitWriting
    ) -> LiveOutfitRepository {
        LiveOutfitRepository(
            apiClient: AstraAPIClient(environment: .preview),
            offlineQueue: queue,
            supabase: AstraSupabaseClientFactory.previewClient,
            writer: writer,
            cache: InMemoryOutfitCache()
        )
    }

    @Test("A failed recordFeedback call is queued and the local value is returned")
    func failedFeedbackIsQueued() async throws {
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(queue: queue, writer: StubOutfitWriter(shouldFail: true))
        let outfitID = UUID()

        let returned = try await repository.recordFeedback(targetType: .outfit, targetID: outfitID, signal: .skipped)

        #expect(returned.targetID == outfitID)
        #expect(returned.signal == .skipped)
        let pending = await queue.pendingMutations()
        #expect(pending.count == 1)
        #expect(pending.first?.entity == .styleFeedback)
        #expect(pending.first?.operation == .create)
    }

    @Test("A later successful drain replays the queued style_feedback write")
    func successfulDrainReplaysQueuedFeedback() async throws {
        let writer = StubOutfitWriter(shouldFail: true)
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(queue: queue, writer: writer)
        let outfitID = UUID()

        _ = try await repository.recordFeedback(targetType: .outfit, targetID: outfitID, signal: .dislike)
        #expect(await queue.pendingMutations().count == 1)

        await writer.setShouldFail(false)
        await repository.drainPendingMutations()

        #expect(await queue.pendingMutations().isEmpty)
        #expect(await writer.createdFeedbackIDs.count == 1)
    }

    @Test("A closet mutation ahead of a queued style_feedback write is skipped, not dropped")
    func foreignMutationIsSkippedNotDiscarded() async throws {
        let writer = StubOutfitWriter(shouldFail: true)
        let queue = InMemoryOfflineMutationQueue(seed: [
            OfflineMutation(entity: .closetItem, operation: .update, payloadData: Data("{}".utf8))
        ])
        let repository = makeRepository(queue: queue, writer: writer)

        _ = try await repository.recordFeedback(targetType: .outfit, targetID: UUID(), signal: .skipped)
        await writer.setShouldFail(false)
        await repository.drainPendingMutations()

        let pending = await queue.pendingMutations()
        #expect(pending.count == 1, "The closet mutation must survive for the repository that owns it")
        #expect(pending.first?.entity == .closetItem)
        #expect(await writer.createdFeedbackIDs.count == 1, "The style_feedback write behind it must still replay")
    }
}
