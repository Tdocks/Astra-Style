import Foundation
import Testing
@testable import AstraStyle

@Suite("ScannerBatchDurability")
@MainActor
struct ScannerBatchDurabilityTests {
    private let ownerID = testOwnerID()
    @Test("A completed batch reconstructs unsaved review drafts after relaunch")
    func completedBatchRestoresDraftsAfterRelaunch() async throws {
        let pendingStore = InMemoryScannerBatchPendingStore()
        let repository = BatchMockClosetRepository()
        let firstDraftStore = CaptureDraftStore()
        let first = makeModel(
            store: firstDraftStore,
            repository: repository,
            pendingStore: pendingStore,
            ownerID: ownerID
        )
        await first.importImages(payloads(2), selectedCount: 2)
        let completed = try #require(await pendingStore.load(ownerID: ownerID))
        #expect(completed.isComplete)
        #expect(completed.entries.allSatisfy { $0.analysis != nil })

        let relaunchedDraftStore = CaptureDraftStore()
        let relaunched = makeModel(
            store: relaunchedDraftStore,
            repository: repository,
            pendingStore: pendingStore,
            ownerID: ownerID
        )
        await relaunched.restorePendingBatch()

        let outcome = try #require(readyOutcome(relaunched))
        #expect(outcome.readyCount == 2)
        #expect(outcome.draftIDs.allSatisfy { relaunchedDraftStore.draft(id: $0)?.analysis != nil })
        #expect(repository.batchCallCount == 1)
    }

    @Test("A saved batch draft stays consumed after relaunch")
    func consumedDraftIsNotReofferedAfterRelaunch() async throws {
        let pendingStore = InMemoryScannerBatchPendingStore()
        let repository = BatchMockClosetRepository()
        let first = makeModel(
            store: CaptureDraftStore(),
            repository: repository,
            pendingStore: pendingStore,
            ownerID: ownerID
        )
        await first.importImages(payloads(2), selectedCount: 2)
        let originalIDs = try #require(readyOutcome(first)).draftIDs
        #expect(await first.markDraftConsumed(originalIDs[0], saved: true))

        let relaunchedDraftStore = CaptureDraftStore()
        let relaunched = makeModel(
            store: relaunchedDraftStore,
            repository: repository,
            pendingStore: pendingStore,
            ownerID: ownerID
        )
        await relaunched.restorePendingBatch()

        let outcome = try #require(readyOutcome(relaunched))
        #expect(outcome.draftIDs == [originalIDs[1]])
        #expect(relaunchedDraftStore.draft(id: originalIDs[0]) == nil)
        #expect(relaunchedDraftStore.draft(id: originalIDs[1]) != nil)
        #expect(repository.batchCallCount == 1)
    }

    @Test("Retry journal write failure preserves the earlier manifest and uploads")
    func retryPersistenceFailurePreservesAcceptedBatch() async throws {
        let pendingStore = FailAfterFirstSavePendingStore()
        let repository = BatchMockClosetRepository()
        repository.batchError = AstraError.network("response lost after enqueue")
        let model = makeModel(
            store: CaptureDraftStore(),
            repository: repository,
            pendingStore: pendingStore,
            ownerID: ownerID
        )
        await model.importImages(payloads(2), selectedCount: 2)
        let original = try #require(await pendingStore.load(ownerID: ownerID))
        let originalPaths = Set(original.entries.compactMap(\.storagePath))

        repository.batchError = nil
        await model.retryPendingBatch()

        let retained = try #require(await pendingStore.load(ownerID: ownerID))
        #expect(retained.idempotencyKey == original.idempotencyKey)
        #expect(retained.entries.map(\.storagePath) == original.entries.map(\.storagePath))
        #expect(repository.liveStoragePaths == originalPaths)
        #expect(repository.batchCallCount == 1)
        #expect(model.canRetryPendingBatch)
    }

}

private actor FailAfterFirstSavePendingStore: ScannerBatchPendingStoring {
    private var record: ScannerBatchPendingRecord?
    private var saves = 0

    func save(_ record: ScannerBatchPendingRecord) async throws {
        saves += 1
        guard saves == 1 else { throw AstraError.server("disk unavailable") }
        self.record = record
    }

    func load(ownerID: UUID) async throws -> ScannerBatchPendingRecord? {
        guard record?.ownerID == ownerID else { return nil }
        return record
    }

    func remove(ownerID: UUID) async throws {
        guard record?.ownerID == ownerID else { return }
        record = nil
    }
}
