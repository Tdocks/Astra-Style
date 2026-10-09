import Foundation
import Testing
@testable import AstraStyle

@Suite("Scanner real unlock-count follow-up")
@MainActor
struct ScannerUnlockCountFollowUpTests {
    private let factory = ScannerReviewViewModelTests()

    @Test("Unlock count failure leaves the saved item intact and offers a safe retry")
    func unlockCountFailureDoesNotFailClosetSave() async throws {
        let jpeg = try #require(scannerReviewFixtureJPEG())
        let draft = CaptureDraft(prepared: try CapturePreparation.prepareForUpload(jpeg))
        let store = CaptureDraftStore()
        store.put(draft)
        let repository = ReviewMockClosetRepository()
        repository.unlockCountError = AstraError.network("offline")
        let model = factory.makeModel(
            draftID: draft.id,
            store: store,
            repository: repository,
            seams: ReviewTestSeams(resolver: ReviewMockURLResolver(), userID: UUID())
        )
        await model.start()
        await model.save()
        try await waitUntilUnlockCountSettles(model)

        #expect(model.phase == .saved)
        #expect(model.savedItem != nil)
        #expect(model.unlockCountState == .unavailable)
        #expect(store.draft(id: draft.id) == nil)

        repository.unlockCountError = nil
        repository.unlockCountResult = .count(4)
        await model.retryScanUnlockCount()
        #expect(model.unlockCountState == .count(4))
        #expect(repository.unlockCountRequestedIDs.count == 2)
    }

    @Test("An unsupported category is shown as unmeasurable rather than zero")
    func unsupportedUnlockCountIsNotPresentedAsZero() async throws {
        let jpeg = try #require(scannerReviewFixtureJPEG())
        let draft = CaptureDraft(prepared: try CapturePreparation.prepareForUpload(jpeg))
        let store = CaptureDraftStore()
        store.put(draft)
        let repository = ReviewMockClosetRepository()
        repository.unlockCountResult = .unmeasurable
        let model = factory.makeModel(
            draftID: draft.id,
            store: store,
            repository: repository,
            seams: ReviewTestSeams(resolver: ReviewMockURLResolver(), userID: UUID())
        )
        await model.start()
        await model.save()
        try await waitUntilUnlockCountSettles(model)

        #expect(model.phase == .saved)
        #expect(model.unlockCountState == .unmeasurable)
        #expect(model.outfitsUnlockedCount == nil)
    }
}
