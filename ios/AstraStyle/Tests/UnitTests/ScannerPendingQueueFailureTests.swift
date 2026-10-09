import Foundation
import Testing
@testable import AstraStyle

@Suite("Scanner pending queue persistence")
@MainActor
struct ScannerPendingQueueFailureTests {
    @Test("A failed durable enqueue stays visible and can be retried")
    func failedEnqueueCanBeRetried() async throws {
        let jpeg = try #require(scannerReviewFixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let draftID = UUID()
        let draft = CaptureDraft(id: draftID, prepared: prepared)
        let store = CaptureDraftStore()
        store.put(draft)
        let queue = FailingPendingScanQueue()
        let model = makeModel(draftID: draftID, store: store, queue: queue)

        await model.enqueuePendingAnalysis(data: prepared.data, deviceHints: nil)

        guard case .queueFailed = model.phase else {
            Issue.record("Expected visible queue failure, got \(model.phase)")
            return
        }
        #expect(model.localPreviewData == prepared.data)
        #expect(await queue.pendingScans().isEmpty)

        await queue.setFailEnqueue(false)
        await model.retryQueuePersistence()

        #expect(model.phase == .pendingAnalysis)
        let scans = await queue.pendingScans()
        #expect(scans.count == 1)
        #expect(scans.first?.id == draftID)
        #expect(scans.first?.jpegData == prepared.data)
    }

    private func makeModel(
        draftID: UUID,
        store: CaptureDraftStore,
        queue: PendingScanQueue
    ) -> ScannerReviewViewModel {
        ScannerReviewViewModel(
            draftID: draftID,
            dependencies: .init(
                draftStore: store,
                closetRepository: ReviewMockClosetRepository(),
                imageURLResolver: ReviewMockURLResolver(),
                pendingScanQueue: queue,
                currentUserID: { nil }
            )
        )
    }
}

private actor FailingPendingScanQueue: PendingScanQueue {
    private var scans: [PendingScan] = []
    private var failEnqueue = true

    func enqueue(_ scan: PendingScan) async throws {
        guard !failEnqueue else {
            throw AstraError.server("Couldn't keep this scan on your device. Try again before leaving.")
        }
        scans.removeAll { $0.id == scan.id }
        scans.append(scan)
    }

    func pendingScans() async -> [PendingScan] { scans }

    func remove(id: UUID) async { scans.removeAll { $0.id == id } }

    func incrementAttemptCount(id: UUID) async {
        guard let index = scans.firstIndex(where: { $0.id == id }) else { return }
        scans[index].attemptCount += 1
    }

    func clear() async { scans.removeAll() }

    func setFailEnqueue(_ fail: Bool) { failEnqueue = fail }
}
