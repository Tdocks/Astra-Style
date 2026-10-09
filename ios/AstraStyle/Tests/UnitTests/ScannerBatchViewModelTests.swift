//
//  ScannerBatchViewModelTests.swift
//  AstraStyleTests
//
//  P3-SCAN-08's client half. These are written against the contract
//  `ClosetRepository.batchAnalyzeItems` states — "one image failing must
//  cost the user that one image, not the other four" — rather than against
//  the view model's implementation.
//
//  The `prepare` seam is injected so a batch of twenty can be exercised
//  without twenty JPEG fixtures. What is being tested here is accounting,
//  ordering and cleanup; the image pipeline itself has its own suite.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("ScannerBatchViewModel")
@MainActor
struct ScannerBatchViewModelTests {

    private let ownerID = testOwnerID()

    @Test("A clean batch produces one pre-analysed draft per photo, in submission order")
    func cleanBatchProducesOrderedDrafts() async throws {
        let store = CaptureDraftStore()
        let repository = BatchMockClosetRepository()
        let model = makeModel(store: store, repository: repository)

        await model.importImages(payloads(3), selectedCount: 3)

        let outcome = try #require(readyOutcome(model))
        #expect(outcome.readyCount == 3)
        #expect(outcome.isCompletelyClean)
        #expect(repository.uploadCount == 3)
        #expect(repository.batchCallCount == 1)

        // Every draft must carry BOTH the analysis and the storage path.
        // Without the path the review screen cannot build a
        // `ClosetItemImage`, so a garment could be analysed — and paid for —
        // and then be unsaveable.
        for id in outcome.draftIDs {
            let draft = try #require(store.draft(id: id))
            #expect(draft.analysis != nil)
            #expect(draft.storagePath != nil)
        }
        #expect(outcome.draftIDs == repository.lastBatchRequestIDs)
    }

    @Test("The repository is told each image's storage path, so it does not upload twice")
    func batchReusesTheUploadedPaths() async throws {
        let repository = BatchMockClosetRepository()
        let model = makeModel(store: CaptureDraftStore(), repository: repository)

        await model.importImages(payloads(2), selectedCount: 2)

        #expect(repository.uploadCount == 2)
        #expect(repository.lastBatchStoragePaths.count == 2)
        #expect(repository.lastBatchStoragePaths.allSatisfy { $0?.isEmpty == false })
    }

    @Test("Photos past the server's per-batch limit are reported, never silently dropped")
    func overLimitSelectionIsReported() async throws {
        let repository = BatchMockClosetRepository()
        let model = makeModel(store: CaptureDraftStore(), repository: repository)
        let over = BatchScanLimits.maxItemsPerBatch + 5

        await model.importImages(payloads(over), selectedCount: over)

        let outcome = try #require(readyOutcome(model))
        #expect(outcome.selected == over)
        #expect(outcome.readyCount == BatchScanLimits.maxItemsPerBatch)
        #expect(outcome.skippedOverLimit == 5)
        #expect(!outcome.isCompletelyClean)
    }

    @Test("An undecodable photo costs that photo and nothing else")
    func oneUnreadablePhotoDoesNotFailTheBatch() async throws {
        let store = CaptureDraftStore()
        let repository = BatchMockClosetRepository()
        // The second payload is the one the pipeline refuses.
        let model = makeModel(store: store, repository: repository, unpreparable: [1])

        await model.importImages(payloads(3), selectedCount: 3)

        let outcome = try #require(readyOutcome(model))
        #expect(outcome.readyCount == 2)
        #expect(outcome.unreadable == 1)
        #expect(repository.uploadCount == 2)
    }

    @Test("A per-item analysis failure is counted by reason and its upload is not left behind")
    func perItemFailureIsCountedAndCleanedUp() async throws {
        let store = CaptureDraftStore()
        let repository = BatchMockClosetRepository()
        repository.failIndices = [0]
        repository.failureReason = .noGarmentDetected
        let model = makeModel(store: store, repository: repository)

        await model.importImages(payloads(3), selectedCount: 3)

        let outcome = try #require(readyOutcome(model))
        #expect(outcome.readyCount == 2)
        #expect(outcome.analysisFailures[.noGarmentDetected] == 1)
        // The object for the failed item has no draft pointing at it and
        // never will. Asserting the live set rather than a delete count
        // says "nothing was left behind" instead of "a delete happened".
        #expect(repository.liveStoragePaths.count == 2)
    }

    @Test("An ambiguous batch failure retries the accepted job without reuploading")
    func ambiguousBatchFailureResumesSameJob() async throws {
        let repository = BatchMockClosetRepository()
        repository.batchError = AstraError.network("response lost after enqueue")
        let model = makeModel(store: CaptureDraftStore(), repository: repository)

        await model.importImages(payloads(3), selectedCount: 3)

        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
        #expect(model.canRetryPendingBatch)
        #expect(repository.uploadCount == 3)
        let acceptedPaths = repository.lastBatchStoragePaths
        let firstKey = try #require(repository.batchIdempotencyKeys.first)
        #expect(repository.liveStoragePaths.count == 3)

        repository.batchError = nil
        await model.retryPendingBatch()

        let outcome = try #require(readyOutcome(model))
        #expect(outcome.readyCount == 3)
        #expect(repository.uploadCount == 3)
        #expect(repository.batchCallCount == 2)
        #expect(repository.lastBatchStoragePaths == acceptedPaths)
        #expect(repository.batchIdempotencyKeys == [firstKey, firstKey])
        #expect(!model.canRetryPendingBatch)
    }

    @Test("A durable-record write failure cleans uploads before any enqueue")
    func failedPendingRecordWriteDoesNotEnqueueOrLeakUploads() async {
        let repository = BatchMockClosetRepository()
        let model = makeModel(
            store: CaptureDraftStore(),
            repository: repository,
            pendingStore: ThrowingSavePendingStore()
        )

        await model.importImages(payloads(2), selectedCount: 2)

        guard case .failed = model.phase else {
            Issue.record("expected a visible local persistence failure")
            return
        }
        #expect(repository.uploadCount == 2)
        #expect(repository.batchCallCount == 0)
        #expect(repository.liveStoragePaths.isEmpty)
        #expect(!model.canRetryPendingBatch)
    }

    @Test("Explicitly discarding an ambiguous batch cleans its retained uploads")
    func discardPendingBatchCleansUploads() async {
        let repository = BatchMockClosetRepository()
        repository.batchError = AstraError.network("enqueue result unknown")
        let model = makeModel(store: CaptureDraftStore(), repository: repository)

        await model.importImages(payloads(2), selectedCount: 2)
        #expect(model.canRetryPendingBatch)
        #expect(repository.liveStoragePaths.count == 2)

        await model.discardPendingBatch()

        #expect(repository.liveStoragePaths.isEmpty)
        #expect(!model.canRetryPendingBatch)
        #expect(model.phase == .idle)
    }

    @Test("An accepted batch restores after recreating the view model for the same owner")
    func pendingBatchRestoresForOwnerAfterRelaunch() async throws {
        let pendingStore = InMemoryScannerBatchPendingStore()
        let repository = BatchMockClosetRepository()
        repository.batchError = AstraError.network("response lost after enqueue")
        let first = makeModel(
            store: CaptureDraftStore(),
            repository: repository,
            pendingStore: pendingStore,
            ownerID: ownerID
        )
        await first.importImages(payloads(2), selectedCount: 2)
        let originalKey = try #require(repository.batchIdempotencyKeys.first)

        repository.batchError = nil
        let relaunched = makeModel(
            store: CaptureDraftStore(),
            repository: repository,
            pendingStore: pendingStore,
            ownerID: ownerID
        )
        await relaunched.restorePendingBatch()
        #expect(relaunched.canRetryPendingBatch)
        await relaunched.retryPendingBatch()

        #expect(readyOutcome(relaunched)?.readyCount == 2)
        #expect(repository.uploadCount == 2)
        #expect(repository.batchIdempotencyKeys == [originalKey, originalKey])
    }

    @Test("A different owner cannot restore another account's pending batch")
    func pendingBatchDoesNotCrossOwners() async throws {
        let pendingStore = InMemoryScannerBatchPendingStore()
        let repository = BatchMockClosetRepository()
        repository.batchError = AstraError.network("response lost after enqueue")
        let first = makeModel(
            store: CaptureDraftStore(),
            repository: repository,
            pendingStore: pendingStore,
            ownerID: ownerID
        )
        await first.importImages(payloads(1), selectedCount: 1)

        let otherOwner = makeModel(
            store: CaptureDraftStore(),
            repository: repository,
            pendingStore: pendingStore,
            ownerID: UUID()
        )
        await otherOwner.restorePendingBatch()
        #expect(!otherOwner.canRetryPendingBatch)
        #expect(otherOwner.phase == .idle)
    }

    @Test("A validation response after enqueue preserves uploads for safe retry")
    func validationResponsePreservesPossiblyAcceptedBatch() async {
        let repository = BatchMockClosetRepository()
        repository.batchError = AstraError.validation("invalid batch")
        let model = makeModel(store: CaptureDraftStore(), repository: repository)

        await model.importImages(payloads(2), selectedCount: 2)

        #expect(repository.liveStoragePaths.count == 2)
        #expect(model.canRetryPendingBatch)
    }

    @Test("Hitting the free-tier cap surfaces the cap, not a generic failure")
    func capReachedIsItsOwnPhase() async throws {
        let repository = BatchMockClosetRepository()
        repository.batchError = FreeTierClosetError.capReached(limit: 30)
        let model = makeModel(store: CaptureDraftStore(), repository: repository)

        await model.importImages(payloads(3), selectedCount: 3)

        #expect(model.phase == .capReached(limit: 30))
        #expect(repository.liveStoragePaths.isEmpty)
    }

    @Test("Photos the library refuses to hand over are counted, not silently dropped")
    func photosTheLibraryWouldNotVendAreCounted() async throws {
        // The real shape of this on a phone: the user picks fifteen, two of
        // them live in iCloud and are not on the device, `loadTransferable`
        // returns nil for those two, and the view passes thirteen payloads.
        // Before `selectedCount` existed the batch reported thirteen selected
        // and a perfectly clean run.
        let repository = BatchMockClosetRepository()
        let model = makeModel(store: CaptureDraftStore(), repository: repository)

        await model.importImages(payloads(13), selectedCount: 15)

        let outcome = try #require(readyOutcome(model))
        #expect(outcome.selected == 15)
        #expect(outcome.couldNotLoad == 2)
        #expect(outcome.readyCount == 13)
        #expect(outcome.lostCount == 2)
        #expect(!outcome.isCompletelyClean)
    }

    @Test("A selection the library could not vend AT ALL still reports the loss")
    func everyPhotoFailingToLoadStillReports() async throws {
        let repository = BatchMockClosetRepository()
        let model = makeModel(store: CaptureDraftStore(), repository: repository)

        await model.importImages([], selectedCount: 4)

        let outcome = try #require(readyOutcome(model))
        #expect(outcome.selected == 4)
        #expect(outcome.couldNotLoad == 4)
        #expect(outcome.readyCount == 0)
        #expect(repository.uploadCount == 0)
    }

    @Test("A failed upload is reported as a failed upload, not as a bad photograph")
    func uploadFailureIsNotBlamedOnThePhoto() async throws {
        // `.imageUnusable` renders as "too blurry or too dark to read". Saying
        // that about a photo the analyser never received is a fabricated
        // diagnosis, and it sends the user to retake a picture that was fine.
        let repository = BatchMockClosetRepository()
        repository.failUploadIndices = [1]
        let model = makeModel(store: CaptureDraftStore(), repository: repository)

        await model.importImages(payloads(3), selectedCount: 3)

        let outcome = try #require(readyOutcome(model))
        #expect(outcome.uploadFailed == 1)
        #expect(outcome.analysisFailures.isEmpty)
        #expect(outcome.readyCount == 2)
    }

    @Test("An empty selection does nothing at all")
    func emptySelectionIsANoOp() async {
        let repository = BatchMockClosetRepository()
        let model = makeModel(store: CaptureDraftStore(), repository: repository)

        await model.importImages([], selectedCount: 0)

        // Nothing picked is not a batch. Distinct from the case above, where
        // photos WERE picked and none of them could be loaded — that has a
        // loss to report and this does not.
        #expect(model.phase == .ready(ScannerBatchViewModel.Outcome()))
        #expect(repository.uploadCount == 0)
    }
}

private actor ThrowingSavePendingStore: ScannerBatchPendingStoring {
    func save(_ record: ScannerBatchPendingRecord) async throws {
        _ = record
        throw AstraError.server("disk unavailable")
    }

    func load(ownerID: UUID) async throws -> ScannerBatchPendingRecord? {
        _ = ownerID
        return nil
    }

    func remove(ownerID: UUID) async throws {
        _ = ownerID
    }
}

// MARK: - Helpers

@MainActor
func makeModel(
    store: CaptureDraftStore,
    repository: ClosetRepository,
    pendingStore: any ScannerBatchPendingStoring = InMemoryScannerBatchPendingStore(),
    ownerID: UUID = testOwnerID(),
    unpreparable: Set<Int> = []
) -> ScannerBatchViewModel {
    // Payload byte 0 is the index, so the `prepare` seam can refuse a
    // specific photo without the test needing a real undecodable JPEG.
    ScannerBatchViewModel(dependencies: .init(
        draftStore: store,
        closetRepository: repository,
        currentOwnerID: { ownerID },
        pendingStore: pendingStore,
        prepare: { data in
            let index = Int(data.first ?? 0)
            if unpreparable.contains(index) {
                throw CapturePreparation.Failure.undecodableImage
            }
            return CapturePreparation.Prepared(
                data: data,
                pixelWidth: 1024,
                pixelHeight: 768,
                originalByteCount: data.count * 4
            )
        },
        deviceHints: { _ in nil }
    ))
}

func testOwnerID() -> UUID {
    UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA") ?? UUID()
}

func payloads(_ count: Int) -> [Data] {
    (0..<count).map { Data([UInt8($0 % 256), 0xFF, 0xD8]) }
}

@MainActor
func readyOutcome(_ model: ScannerBatchViewModel) -> ScannerBatchViewModel.Outcome? {
    guard case .ready(let outcome) = model.phase else { return nil }
    return outcome
}

final class BatchMockClosetRepository: ClosetRepository, @unchecked Sendable {
    var uploadCount = 0
    var batchCallCount = 0
    var batchError: Error?
    private(set) var batchIdempotencyKeys: [String] = []
    /// Positions within the submitted batch that come back failed.
    var failIndices: Set<Int> = []
    /// Submission positions whose UPLOAD throws, as distinct from whose
    /// analysis comes back failed.
    var failUploadIndices: Set<Int> = []
    var failureReason: ClosetItemAnalysisFailureReason = .unknown
    private(set) var liveStoragePaths: Set<String> = []
    private(set) var lastBatchRequestIDs: [UUID] = []
    private(set) var lastBatchStoragePaths: [String?] = []

    func uploadCapturedImage(_ data: Data) async throws -> String {
        if failUploadIndices.contains(uploadCount) {
            uploadCount += 1
            throw AstraError.network("upload failed")
        }
        uploadCount += 1
        _ = data
        let path = "users/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/closet/\(UUID().uuidString.lowercased()).jpg"
        liveStoragePaths.insert(path)
        return path
    }

    func uploadClosetCaptureImage(_ data: Data, requestID: UUID) async throws -> String {
        let path = "users/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/closet/batch/\(requestID.uuidString.lowercased()).jpg"
        if failUploadIndices.contains(uploadCount) {
            uploadCount += 1
            throw AstraError.network("upload failed")
        }
        if !liveStoragePaths.contains(path) { uploadCount += 1 }
        _ = data
        liveStoragePaths.insert(path)
        return path
    }

    func deleteCapturedImage(atPath storagePath: String) async throws {
        liveStoragePaths.remove(storagePath)
    }

    func cancelBatchAnalysis(idempotencyKey: String) async throws {
        _ = idempotencyKey
    }

    func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        try await batchAnalyzeItems(requests, idempotencyKey: UUID().uuidString)
    }

    func batchAnalyzeItems(
        _ requests: [ClosetItemAnalysisRequest],
        idempotencyKey: String
    ) async throws -> ClosetItemAnalysisBatch {
        batchCallCount += 1
        batchIdempotencyKeys.append(idempotencyKey)
        lastBatchStoragePaths = requests.map(\.storagePath)
        if let batchError {
            lastBatchRequestIDs = []
            throw batchError
        }
        var succeeded: [UUID] = []
        let results = requests.enumerated().map { index, request in
            if failIndices.contains(index) {
                return ClosetItemAnalysisBatchItem(
                    id: request.id,
                    outcome: .failed(ClosetItemAnalysisFailure(reason: failureReason, message: nil))
                )
            }
            succeeded.append(request.id)
            return ClosetItemAnalysisBatchItem(
                id: request.id,
                outcome: .analyzed(MockClosetRepository.cannedAnalysis)
            )
        }
        lastBatchRequestIDs = succeeded
        return ClosetItemAnalysisBatch(results: results)
    }

    func fetchItems() async throws -> [ClosetItem] { [] }
    func fetchItem(id: UUID) async throws -> ClosetItem { throw AstraError.server("n/a") }
    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] { [] }
    func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        MockClosetRepository.cannedAnalysis
    }
    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem { item }
    func updateItem(_ item: ClosetItem) async throws -> ClosetItem { item }
    func archiveItem(id: UUID) async throws {}
    func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem {
        throw AstraError.unimplemented("n/a")
    }
    func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        throw AstraError.unimplemented("n/a")
    }
    func fetchWardrobeScore() async throws -> WardrobeScore {
        throw AstraError.unimplemented("n/a")
    }
}
