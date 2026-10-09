//
//  OutfitOfflineDrainWiringTests.swift
//  AstraStyleTests
//
//  P1-CORE-06: before `LiveOutfitRepository+Offline.swift` existed,
//  `updateOutfit` and `recordWear` queued a `.outfit`/`.outfitWear`
//  mutation on failure and nothing in the app ever replayed it —
//  `LiveClosetRepository`'s drain skipped them correctly (via
//  `OfflineMutationNotHandled`), but nothing else picked them up, so the
//  backlog only ever grew. Mirrors
//  `Tests/UnitTests/OfflineDrainWiringTests.swift`'s coverage for the
//  closet, against `LiveOutfitRepository` and a stub `OutfitWriting`.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Offline queue wiring — a queued outfit write actually gets replayed")
struct OutfitOfflineDrainWiringTests {

    private actor FailingOfflineQueue: OfflineMutationQueue {
        func enqueue(_ mutation: OfflineMutation) async throws {
            throw AstraError.server("queue persistence failed")
        }
        func pendingMutations() async -> [OfflineMutation] { [] }
        func drain(apply: @Sendable (OfflineMutation) async throws -> Void) async {}
        func remove(id: UUID) async {}
        func clear() async {}
    }

    // MARK: - Doubles

    private actor StubOutfitWriter: OutfitWriting {
        private var shouldFail: Bool
        private(set) var updatedOutfitIDs: [UUID] = []
        private(set) var createdWearIDs: [UUID] = []
        private(set) var createdFeedbackIDs: [UUID] = []

        init(shouldFail: Bool) {
            self.shouldFail = shouldFail
        }

        func setShouldFail(_ value: Bool) {
            shouldFail = value
        }

        func updateOutfit(_ outfit: Outfit) async throws -> Outfit {
            if shouldFail { throw AstraError.network("offline") }
            updatedOutfitIDs.append(outfit.id)
            return outfit
        }

        func createWear(_ wear: OutfitWear) async throws -> OutfitWear {
            if shouldFail { throw AstraError.network("offline") }
            createdWearIDs.append(wear.id)
            return wear
        }

        /// Added when `P4-OUTFIT-14` gave `OutfitWriting` a third verb.
        ///
        /// Recorded and failable like the other two rather than left as a
        /// `fatalError`: this suite's whole subject is that a queued mutation
        /// this writer does not own is SKIPPED rather than dropped or replayed
        /// (`OfflineMutationNotHandled`), and a stub that trapped on the newest
        /// entity type would pass every existing test while making the one
        /// interesting case unwritable.
        func createFeedback(_ feedback: StyleFeedback) async throws -> StyleFeedback {
            if shouldFail { throw AstraError.network("offline") }
            createdFeedbackIDs.append(feedback.id)
            return feedback
        }
    }

    private func makeRepository(
        queue: OfflineMutationQueue,
        writer: some OutfitWriting,
        ownerID: UUID? = nil
    ) -> LiveOutfitRepository {
        LiveOutfitRepository(
            apiClient: AstraAPIClient(environment: .preview),
            offlineQueue: queue,
            supabase: AstraSupabaseClientFactory.previewClient,
            writer: writer,
            cache: InMemoryOutfitCache(),
            currentUserID: { ownerID }
        )
    }

    private func outfit(_ name: String, userID: UUID = UUID()) -> Outfit {
        Outfit(id: UUID(), userID: userID, name: name)
    }

    // MARK: - Tests

    @Test("A failed outfit update is queued and the local value is returned")
    func failedUpdateIsQueued() async throws {
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(queue: queue, writer: StubOutfitWriter(shouldFail: true))
        let garment = outfit("Weekend Layers")

        let returned = try await repository.updateOutfit(garment)

        #expect(returned.id == garment.id)
        let pending = await queue.pendingMutations()
        #expect(pending.count == 1)
        #expect(pending.first?.entity == .outfit)
        #expect(pending.first?.operation == .update)
    }

    @Test("Failed durable enqueue surfaces outfit update and wear actions")
    func failedQueuePersistenceSurfacesOutfitMutations() async throws {
        let ownerID = UUID()
        let repository = makeRepository(
            queue: FailingOfflineQueue(), writer: StubOutfitWriter(shouldFail: true), ownerID: ownerID
        )
        let look = outfit("Unqueued layers", userID: ownerID)
        let expectedError = AstraError.server("queue persistence failed")

        await #expect(throws: expectedError) { _ = try await repository.updateOutfit(look) }
        await #expect(throws: expectedError) {
            try await repository.recordWear(outfitID: look.id, wornAt: .now, occasion: nil, rating: nil, feedback: nil)
        }
    }

    @Test("A later successful call replays the whole backlog, oldest first")
    func successfulWriteDrainsTheBacklog() async throws {
        let ownerID = UUID()
        let writer = StubOutfitWriter(shouldFail: true)
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(queue: queue, writer: writer, ownerID: ownerID)

        let first = outfit("Rainy Commute", userID: ownerID)
        _ = try await repository.updateOutfit(first)
        _ = try await repository.recordWear(outfitID: UUID(), wornAt: .now, occasion: nil, rating: nil, feedback: nil)
        #expect(await queue.pendingMutations().count == 2)

        await writer.setShouldFail(false)
        let third = outfit("Studio Session", userID: ownerID)
        _ = try await repository.updateOutfit(third)

        #expect(await queue.pendingMutations().isEmpty)
        // `third` replays first (it's the live call that triggers the
        // drain), then the backlog in the order it was enqueued.
        #expect(await writer.updatedOutfitIDs == [third.id, first.id])
        #expect(await writer.createdWearIDs.count == 1)
    }

    @Test("A successful read drains too — a returning user's backlog flushes without a write")
    func successfulReadDrains() async throws {
        let ownerID = UUID()
        let writer = StubOutfitWriter(shouldFail: true)
        let queue = InMemoryOfflineMutationQueue()
        let repository = LiveOutfitRepository(
            apiClient: AstraAPIClient(environment: .preview),
            offlineQueue: queue,
            supabase: AstraSupabaseClientFactory.previewClient,
            writer: writer,
            cache: InMemoryOutfitCache(),
            currentUserID: { ownerID },
            activeOutfitsFetcher: { [] }
        )

        let garment = outfit("Off-Duty", userID: ownerID)
        _ = try await repository.updateOutfit(garment)
        #expect(await queue.pendingMutations().count == 1)

        await writer.setShouldFail(false)
        _ = try await repository.fetchOutfits()

        #expect(await queue.pendingMutations().isEmpty)
        #expect(await writer.updatedOutfitIDs == [garment.id])
    }

    @Test("A replay that fails increments attemptCount and leaves the queue intact")
    func failedReplayCountsAnAttempt() async throws {
        let ownerID = UUID()
        let writer = StubOutfitWriter(shouldFail: true)
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(queue: queue, writer: writer, ownerID: ownerID)

        let garment = outfit("Museum Day", userID: ownerID)
        _ = try await repository.updateOutfit(garment)
        #expect(await queue.pendingMutations().first?.attemptCount == 0)

        await repository.drainPendingMutations()
        #expect(await queue.pendingMutations().first?.attemptCount == 1)

        await repository.drainPendingMutations()
        let pending = await queue.pendingMutations()
        #expect(pending.count == 1)
        #expect(pending.first?.attemptCount == 2)
    }

    @Test("A closet mutation is skipped, not dropped, and does not block the outfit backlog")
    func foreignMutationIsSkippedNotDiscarded() async throws {
        let ownerID = UUID()
        // The foreign mutation is FIRST on purpose: under a plain
        // stop-at-first-failure drain it would wedge the queue and the
        // outfit write behind it would never replay.
        let writer = StubOutfitWriter(shouldFail: true)
        let queue = InMemoryOfflineMutationQueue(seed: [
            OfflineMutation(entity: .closetItem, operation: .update, payloadData: Data("{}".utf8))
        ])
        let repository = makeRepository(queue: queue, writer: writer, ownerID: ownerID)

        let garment = outfit("Layover Look", userID: ownerID)
        _ = try await repository.updateOutfit(garment)
        await writer.setShouldFail(false)
        await repository.drainPendingMutations()

        let pending = await queue.pendingMutations()
        #expect(pending.count == 1, "The closet mutation must survive for the repository that owns it")
        #expect(pending.first?.entity == .closetItem)
        #expect(pending.first?.attemptCount == 0, "Skipping is not an attempt")
        #expect(await writer.updatedOutfitIDs == [garment.id], "The outfit write behind it must still replay")
    }

    @Test("Two concurrent drains do not replay the same mutation twice")
    func concurrentDrainsDoNotDoubleApply() async throws {
        let ownerID = UUID()
        let writer = StubOutfitWriter(shouldFail: true)
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(queue: queue, writer: writer, ownerID: ownerID)

        let garment = outfit("Fireside", userID: ownerID)
        _ = try await repository.updateOutfit(garment)
        await writer.setShouldFail(false)

        async let firstDrain: Void = repository.drainPendingMutations()
        async let secondDrain: Void = repository.drainPendingMutations()
        _ = await (firstDrain, secondDrain)

        #expect(await writer.updatedOutfitIDs == [garment.id])
        #expect(await queue.pendingMutations().isEmpty)
    }

    @Test("Foreign outfit, wear, and feedback records stay queued and never reach the writer")
    func foreignOwnerMutationsAreSkipped() async throws {
        let currentOwner = UUID()
        let otherOwner = UUID()
        let outfit = Outfit(id: UUID(), userID: otherOwner, name: "Other account")
        let wear = OutfitWear(id: UUID(), outfitID: outfit.id, userID: otherOwner, wornAt: .now)
        let feedback = StyleFeedback(
            id: UUID(), userID: otherOwner, targetType: .closetItem, targetID: UUID(), signal: .like
        )
        let queue = InMemoryOfflineMutationQueue(seed: [
            OfflineMutation(entity: .outfit, operation: .update, payloadData: try JSONEncoder.astraDefault.encode(outfit)),
            OfflineMutation(entity: .outfitWear, operation: .create, payloadData: try JSONEncoder.astraDefault.encode(wear)),
            OfflineMutation(entity: .styleFeedback, operation: .create, payloadData: try JSONEncoder.astraDefault.encode(feedback))
        ])
        let writer = StubOutfitWriter(shouldFail: false)
        let repository = makeRepository(queue: queue, writer: writer, ownerID: currentOwner)

        await repository.drainPendingMutations()

        let pending = await queue.pendingMutations()
        #expect(pending.count == 3)
        #expect(pending.allSatisfy { $0.attemptCount == 0 })
        #expect(await writer.updatedOutfitIDs.isEmpty)
        #expect(await writer.createdWearIDs.isEmpty)
        #expect(await writer.createdFeedbackIDs.isEmpty)
    }

    @Test("An owned style feedback record replays under the matching owner")
    func ownedFeedbackReplays() async throws {
        let ownerID = UUID()
        let feedback = StyleFeedback(
            id: UUID(), userID: ownerID, targetType: .closetItem, targetID: UUID(), signal: .like
        )
        let queue = InMemoryOfflineMutationQueue(seed: [
            OfflineMutation(entity: .styleFeedback, operation: .create, payloadData: try JSONEncoder.astraDefault.encode(feedback))
        ])
        let writer = StubOutfitWriter(shouldFail: false)
        let repository = makeRepository(queue: queue, writer: writer, ownerID: ownerID)

        await repository.drainPendingMutations()

        #expect(await queue.pendingMutations().isEmpty)
        #expect(await writer.createdFeedbackIDs == [feedback.id])
    }

    @Test("Offline wear and feedback require a real active owner")
    func offlineWritesDoNotInventOwners() async {
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(queue: queue, writer: StubOutfitWriter(shouldFail: true))

        await #expect(throws: AstraError.self) {
            try await repository.recordWear(outfitID: UUID(), wornAt: .now, occasion: nil, rating: nil, feedback: nil)
        }
        await #expect(throws: AstraError.self) {
            try await repository.recordFeedback(
                targetType: .closetItem, targetID: UUID(), signal: .like, reasonTags: [], freeText: nil
            )
        }
        #expect(await queue.pendingMutations().isEmpty)
    }
}
