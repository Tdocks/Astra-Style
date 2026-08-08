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

    @Test("A clean batch produces one pre-analysed draft per photo, in submission order")
    func cleanBatchProducesOrderedDrafts() async throws {
        let store = CaptureDraftStore()
        let repository = BatchMockClosetRepository()
        let model = makeModel(store: store, repository: repository)

        await model.importImages(payloads(3))

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

        await model.importImages(payloads(2))

        #expect(repository.uploadCount == 2)
        #expect(repository.lastBatchStoragePaths.count == 2)
        #expect(repository.lastBatchStoragePaths.allSatisfy { $0?.isEmpty == false })
    }

    @Test("Photos past the server's per-batch limit are reported, never silently dropped")
    func overLimitSelectionIsReported() async throws {
        let repository = BatchMockClosetRepository()
        let model = makeModel(store: CaptureDraftStore(), repository: repository)
        let over = BatchScanLimits.maxItemsPerBatch + 5

        await model.importImages(payloads(over))

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

        await model.importImages(payloads(3))

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

        await model.importImages(payloads(3))

        let outcome = try #require(readyOutcome(model))
        #expect(outcome.readyCount == 2)
        #expect(outcome.analysisFailures[.noGarmentDetected] == 1)
        // The object for the failed item has no draft pointing at it and
        // never will. Asserting the live set rather than a delete count
        // says "nothing was left behind" instead of "a delete happened".
        #expect(repository.liveStoragePaths.count == 2)
    }

    @Test("A batch that throws leaves nothing in storage")
    func wholeBatchFailureCleansUpEveryUpload() async throws {
        let repository = BatchMockClosetRepository()
        repository.batchError = AstraError.network("offline")
        let model = makeModel(store: CaptureDraftStore(), repository: repository)

        await model.importImages(payloads(4))

        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
        #expect(repository.uploadCount == 4)
        #expect(repository.liveStoragePaths.isEmpty)
    }

    @Test("Hitting the free-tier cap surfaces the cap, not a generic failure")
    func capReachedIsItsOwnPhase() async throws {
        let repository = BatchMockClosetRepository()
        repository.batchError = FreeTierClosetError.capReached(limit: 30)
        let model = makeModel(store: CaptureDraftStore(), repository: repository)

        await model.importImages(payloads(3))

        #expect(model.phase == .capReached(limit: 30))
        #expect(repository.liveStoragePaths.isEmpty)
    }

    @Test("An empty selection does nothing at all")
    func emptySelectionIsANoOp() async {
        let repository = BatchMockClosetRepository()
        let model = makeModel(store: CaptureDraftStore(), repository: repository)

        await model.importImages([])

        #expect(model.phase == .idle)
        #expect(repository.uploadCount == 0)
    }
}

// MARK: - Helpers

@MainActor
private func makeModel(
    store: CaptureDraftStore,
    repository: ClosetRepository,
    unpreparable: Set<Int> = []
) -> ScannerBatchViewModel {
    // Payload byte 0 is the index, so the `prepare` seam can refuse a
    // specific photo without the test needing a real undecodable JPEG.
    ScannerBatchViewModel(dependencies: .init(
        draftStore: store,
        closetRepository: repository,
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

private func payloads(_ count: Int) -> [Data] {
    (0..<count).map { Data([UInt8($0 % 256), 0xFF, 0xD8]) }
}

@MainActor
private func readyOutcome(_ model: ScannerBatchViewModel) -> ScannerBatchViewModel.Outcome? {
    guard case .ready(let outcome) = model.phase else { return nil }
    return outcome
}

private final class BatchMockClosetRepository: ClosetRepository, @unchecked Sendable {
    var uploadCount = 0
    var batchCallCount = 0
    var batchError: Error?
    /// Positions within the submitted batch that come back failed.
    var failIndices: Set<Int> = []
    var failureReason: ClosetItemAnalysisFailureReason = .unknown
    private(set) var liveStoragePaths: Set<String> = []
    private(set) var lastBatchRequestIDs: [UUID] = []
    private(set) var lastBatchStoragePaths: [String?] = []

    func uploadCapturedImage(_ data: Data) async throws -> String {
        uploadCount += 1
        _ = data
        let path = "users/test/closet/\(UUID().uuidString.lowercased()).jpg"
        liveStoragePaths.insert(path)
        return path
    }

    func deleteCapturedImage(atPath storagePath: String) async throws {
        liveStoragePaths.remove(storagePath)
    }

    func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        batchCallCount += 1
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
