import Foundation
import Testing
@testable import AstraStyle

@MainActor
extension ScannerReviewViewModelTests {
    @Test("A transient failure can retry its queued analysis without a connectivity transition")
    func queuedAnalysisHasExplicitRecovery() async throws {
        let jpeg = try #require(scannerReviewFixtureJPEG())
        let draft = CaptureDraft(prepared: try CapturePreparation.prepareForUpload(jpeg))
        let store = CaptureDraftStore()
        store.put(draft)
        let repository = ReviewMockClosetRepository()
        repository.analyzeError = .network("Transient connection loss")
        let queue = InMemoryPendingScanQueue()
        let model = makeModel(draftID: draft.id, store: store, repository: repository,
                              seams: ReviewTestSeams(pendingScanQueue: queue))
        await model.start()
        #expect(model.phase == .pendingAnalysis)
        repository.analyzeError = nil
        await model.retryPendingAnalysis()
        #expect(model.phase == .ready)
        #expect(repository.uploadCount == 1)
        #expect(await queue.pendingScans().isEmpty)
        #expect(!model.isRetryingPendingAnalysis)
    }
}
