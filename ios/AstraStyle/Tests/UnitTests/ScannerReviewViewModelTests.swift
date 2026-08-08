//
//  ScannerReviewViewModelTests.swift
//  AstraStyleTests
//
//  Upload → analyze → edit → save for P3-SCAN-05 / P3-SCAN-09.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("ScannerReviewViewModel")
@MainActor
struct ScannerReviewViewModelTests {

    @Test("Happy path uploads, analyzes, seeds low-confidence brand, and saves corrected values")
    func happyPathSavesCorrections() async throws {
        let jpeg = try #require(fixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let draft = CaptureDraft(prepared: prepared)
        let store = CaptureDraftStore()
        store.put(draft)

        let repository = ReviewMockClosetRepository()
        let resolver = ReviewMockURLResolver()
        let userID = UUID()
        let model = makeModel(
            draftID: draft.id,
            store: store,
            repository: repository,
            seams: ReviewTestSeams(resolver: resolver, userID: userID)
        )

        await model.start()
        #expect(model.phase == .ready)
        #expect(repository.uploadCount == 1)
        #expect(repository.analyzeCount == 1)
        #expect(model.storagePath != nil)
        #expect(model.signedPreviewURL != nil)
        #expect(model.isLowConfidence(.brand))
        #expect(model.brand == "Uniqlo")

        model.brand = "Drake's"
        // Seed complementary partners so P3-SCAN-11 reports a real count.
        repository.seedItems = [
            ClosetItem(id: UUID(), userID: userID, name: "Chinos", category: .bottom),
            ClosetItem(id: UUID(), userID: userID, name: "Sneakers", category: .shoes)
        ]
        await model.save()

        #expect(model.phase == .saved)
        let saved = try #require(repository.lastCreated)
        #expect(saved.brand == "Drake's")
        #expect(saved.name == "Cotton Crewneck Sweater")
        #expect(repository.lastImages?.first?.storagePath == model.storagePath)
        #expect(store.draft(id: draft.id) == nil)
        #expect(model.outfitsUnlockedCount == 2)
    }

    /// `savedItem` exists so onboarding's first-items step can list a garment
    /// the scanner created — its list is what THAT step added, so it has to be
    /// told. What it must be told is the SERVER's garment: onboarding shows
    /// the name and category back to the user as confirmation the analysis got
    /// the right thing, and showing the draft instead would confirm nothing
    /// but that the app remembers what it sent.
    @Test("The garment handed to the caller is the repository's, not the draft")
    func savedItemIsTheRepositorysReturnValue() async throws {
        let jpeg = try #require(fixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let draft = CaptureDraft(prepared: prepared)
        let store = CaptureDraftStore()
        store.put(draft)

        let repository = ReviewMockClosetRepository()
        repository.normalizeCreated = { item in
            var normalized = item
            normalized.name = "Server's name for it"
            return normalized
        }
        let model = makeModel(
            draftID: draft.id,
            store: store,
            repository: repository,
            seams: ReviewTestSeams(resolver: ReviewMockURLResolver(), userID: UUID())
        )

        await model.start()
        // Nothing has been created, so there is nothing to hand anyone. A
        // caller that read this before `save()` would list a garment that does
        // not exist.
        #expect(model.savedItem == nil)

        model.name = "What the user typed"
        await model.save()

        #expect(model.phase == .saved)
        let handedOut = try #require(model.savedItem)
        #expect(handedOut.name == "Server's name for it")
        #expect(repository.lastCreated?.name == "What the user typed")
    }

    // MARK: - Abandoned captures
    //
    // `uploadCapturedImage` runs before the user has decided anything, so
    // every exit that is not a save strands an object in `user-content`
    // with nothing in Postgres referencing it. These assert on
    // `liveStoragePaths` — "nothing was left behind" — rather than on a
    // delete call count, which would pass just as well if the wrong path
    // were deleted.

    @Test("Leaving review without saving removes the uploaded capture")
    func abandonedCaptureIsDeleted() async throws {
        let jpeg = try #require(fixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let draft = CaptureDraft(prepared: prepared)
        let store = CaptureDraftStore()
        store.put(draft)

        let repository = ReviewMockClosetRepository()
        let model = makeModel(draftID: draft.id, store: store, repository: repository)

        await model.start()
        let uploaded = try #require(model.storagePath)

        await model.discardUnsavedUpload()

        #expect(repository.deletedPaths == [uploaded])
        #expect(repository.liveStoragePaths.isEmpty)
        #expect(model.storagePath == nil)
        // The draft must forget the path too, or a resumed review would
        // skip the upload and then analyze an object that is gone.
        #expect(store.draft(id: draft.id)?.storagePath == nil)
    }

    /// The one case where deleting would be actively destructive: after a
    /// save, that path *is* the garment's `ClosetItemImage.storagePath`.
    /// The scanner's dismissal calls this on every exit including the one
    /// straight after a successful save, so the guard is load-bearing.
    @Test("A saved capture is never deleted")
    func savedCaptureSurvivesDiscard() async throws {
        let jpeg = try #require(fixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let draft = CaptureDraft(prepared: prepared)
        let store = CaptureDraftStore()
        store.put(draft)

        let repository = ReviewMockClosetRepository()
        let model = makeModel(draftID: draft.id, store: store, repository: repository)

        await model.start()
        let uploaded = try #require(model.storagePath)
        await model.save()
        #expect(model.phase == .saved)

        await model.discardUnsavedUpload()

        #expect(repository.deletedPaths.isEmpty)
        #expect(repository.liveStoragePaths == [uploaded])
        #expect(repository.lastImages?.first?.storagePath == uploaded)
    }

    @Test("Discarding twice cannot ask the server to delete the same object twice")
    func discardIsIdempotent() async throws {
        let jpeg = try #require(fixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let draft = CaptureDraft(prepared: prepared)
        let store = CaptureDraftStore()
        store.put(draft)

        let repository = ReviewMockClosetRepository()
        let model = makeModel(draftID: draft.id, store: store, repository: repository)

        await model.start()
        await model.discardUnsavedUpload()
        await model.discardUnsavedUpload()

        #expect(repository.deletedPaths.count == 1)
    }

    /// A cleanup that cannot reach the network must not trap the user on a
    /// screen he is trying to leave. The object leaks, which is logged and
    /// is the same outcome as before this existed — the point is that the
    /// dismissal still happens.
    @Test("A failed cleanup does not throw at the caller")
    func failedCleanupIsSwallowed() async throws {
        let jpeg = try #require(fixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let draft = CaptureDraft(prepared: prepared)
        let store = CaptureDraftStore()
        store.put(draft)

        let repository = ReviewMockClosetRepository()
        let model = makeModel(draftID: draft.id, store: store, repository: repository)

        await model.start()
        repository.deleteError = AstraError.network("offline")

        await model.discardUnsavedUpload()

        #expect(model.storagePath == nil)
        #expect(repository.liveStoragePaths.count == 1)
    }

    /// Nothing was uploaded, so there is nothing to clean up — and calling
    /// the repository anyway would fail on a path that never existed.
    @Test("Discarding before an upload succeeded touches nothing")
    func discardBeforeUploadIsANoOp() async throws {
        let jpeg = try #require(fixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let draft = CaptureDraft(prepared: prepared)
        let store = CaptureDraftStore()
        store.put(draft)

        let repository = ReviewMockClosetRepository()
        repository.uploadError = AstraError.server("upload failed")
        let model = makeModel(draftID: draft.id, store: store, repository: repository)

        await model.start()
        await model.discardUnsavedUpload()

        #expect(repository.deletedPaths.isEmpty)
    }

    @Test("Non-network upload failure keeps the local draft and retry re-invokes upload")
    func uploadFailureIsRetryable() async throws {
        let jpeg = try #require(fixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let draft = CaptureDraft(prepared: prepared)
        let store = CaptureDraftStore()
        store.put(draft)

        let repository = ReviewMockClosetRepository()
        repository.uploadError = AstraError.server("upload failed")
        let model = makeModel(draftID: draft.id, store: store, repository: repository)

        await model.start()
        guard case .uploadFailed = model.phase else {
            Issue.record("Expected uploadFailed, got \(model.phase)")
            return
        }
        #expect(model.localPreviewData != nil)
        #expect(repository.analyzeCount == 0)

        repository.uploadError = nil
        await model.retryUpload()
        #expect(model.phase == .ready)
        #expect(repository.uploadCount == 2)
        #expect(repository.analyzeCount == 1)
    }

    @Test("Analyze failure after a successful upload retries analyze without a second upload")
    func analyzeRetrySkipsReupload() async throws {
        let jpeg = try #require(fixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let draft = CaptureDraft(prepared: prepared)
        let store = CaptureDraftStore()
        store.put(draft)

        let repository = ReviewMockClosetRepository()
        repository.analyzeError = AstraError.provider("analyze failed")
        let model = makeModel(draftID: draft.id, store: store, repository: repository)

        await model.start()
        guard case .analyzeFailed = model.phase else {
            Issue.record("Expected analyzeFailed, got \(model.phase)")
            return
        }
        #expect(repository.uploadCount == 1)

        repository.analyzeError = nil
        await model.retryAnalyze()
        #expect(model.phase == .ready)
        #expect(repository.uploadCount == 1)
        #expect(repository.analyzeCount == 2)
        #expect(repository.lastAnalyzeStoragePath != nil)
    }

    @Test("Offline start queues the JPEG locally without uploading")
    func offlineStartQueuesPendingScan() async throws {
        let jpeg = try #require(fixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let hints = GarmentDeviceHints(
            dominantColorsRGB: ["#112233"],
            detectedText: ["SIZE M"],
            approximateCategory: .top
        )
        let draft = CaptureDraft(prepared: prepared, deviceHints: hints)
        let store = CaptureDraftStore()
        store.put(draft)

        let repository = ReviewMockClosetRepository()
        let queue = InMemoryPendingScanQueue()
        let monitor = FlippingNetworkMonitor(isOnline: false)
        let model = makeModel(
            draftID: draft.id,
            store: store,
            repository: repository,
            seams: ReviewTestSeams(pendingScanQueue: queue, networkMonitor: monitor)
        )

        await model.start()

        #expect(model.phase == .pendingAnalysis)
        #expect(model.canSave == false)
        #expect(model.localPreviewData == prepared.data)
        #expect(repository.uploadCount == 0)
        #expect(repository.analyzeCount == 0)

        let pending = await queue.pendingScans()
        #expect(pending.count == 1)
        #expect(pending.first?.id == draft.id)
        #expect(pending.first?.jpegData == prepared.data)
        #expect(pending.first?.deviceHints == hints)
        #expect(pending.first?.attemptCount == 0)
    }

    @Test("Queued offline scan uploads and analyzes automatically when connectivity returns")
    func queuedScanAnalyzesOnReconnect() async throws {
        let jpeg = try #require(fixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let draft = CaptureDraft(prepared: prepared)
        let store = CaptureDraftStore()
        store.put(draft)

        let repository = ReviewMockClosetRepository()
        let queue = InMemoryPendingScanQueue()
        let monitor = FlippingNetworkMonitor(isOnline: false)
        let model = makeModel(
            draftID: draft.id,
            store: store,
            repository: repository,
            seams: ReviewTestSeams(pendingScanQueue: queue, networkMonitor: monitor)
        )

        await model.start()
        #expect(model.phase == .pendingAnalysis)

        monitor.setOnline(true)
        try await waitUntilReady(model)

        #expect(model.phase == .ready)
        #expect(repository.uploadCount == 1)
        #expect(repository.analyzeCount == 1)
        #expect(await queue.pendingScans().isEmpty)
        #expect(store.draft(id: draft.id)?.analysis == MockClosetRepository.cannedAnalysis)
        #expect(model.canSave)
    }

    @Test("Missing draft surfaces missingDraft rather than crashing")
    func missingDraftFailsClosed() async {
        let model = makeModel(
            draftID: UUID(),
            store: CaptureDraftStore(),
            repository: ReviewMockClosetRepository()
        )
        await model.start()
        #expect(model.phase == .missingDraft)
    }

    private func makeModel(
        draftID: UUID,
        store: CaptureDraftStore,
        repository: ClosetRepository,
        seams: ReviewTestSeams = ReviewTestSeams()
    ) -> ScannerReviewViewModel {
        ScannerReviewViewModel(
            draftID: draftID,
            dependencies: .init(
                draftStore: store,
                closetRepository: repository,
                imageURLResolver: seams.resolver,
                pendingScanQueue: seams.pendingScanQueue,
                networkMonitor: seams.networkMonitor,
                currentUserID: { seams.userID }
            )
        )
    }
}

/// Optional test doubles for `makeModel`, bundled so the factory stays
/// under SwiftLint's `function_parameter_count` (5).
private struct ReviewTestSeams {
    var resolver: ClosetImageURLResolving = ReviewMockURLResolver()
    var pendingScanQueue: PendingScanQueue = InMemoryPendingScanQueue()
    var networkMonitor: NetworkReachabilityMonitoring = StaticNetworkReachabilityMonitor(offline: false)
    var userID = UUID()
}

// MARK: - Fixtures / doubles

private func fixtureJPEG() -> Data? {
    guard let image = ScannerImageFixtures.checkerboard(width: 640, height: 480, cell: 16) else {
        return nil
    }
    return ScannerImageFixtures.jpegData(from: image, includeMetadata: false)
}

@MainActor
private func waitUntilReady(_ model: ScannerReviewViewModel) async throws {
    for _ in 0..<40 {
        if model.phase == .ready { return }
        try await Task.sleep(for: .milliseconds(25))
    }
    Issue.record("Expected ready, got \(model.phase)")
}

private final class ReviewMockClosetRepository: ClosetRepository, @unchecked Sendable {
    var uploadCount = 0
    var analyzeCount = 0
    var uploadError: AstraError?
    var analyzeError: AstraError?
    var lastCreated: ClosetItem?
    var lastImages: [ClosetItemImage]?
    var lastAnalyzeStoragePath: String?
    var seedItems: [ClosetItem] = []
    private var uploadedPath: String?
    /// Paths handed out and not yet deleted — the stand-in for objects
    /// still sitting in `user-content`. Asserting `liveStoragePaths` is
    /// empty says "nothing was left behind", which is the property that
    /// matters; a delete *call count* would pass just as well if the
    /// wrong path were deleted.
    private(set) var liveStoragePaths: Set<String> = []
    private(set) var deletedPaths: [String] = []
    var deleteError: AstraError?

    func fetchItems() async throws -> [ClosetItem] {
        var items = seedItems
        if let lastCreated {
            items.append(lastCreated)
        }
        return items
    }
    func fetchItem(id: UUID) async throws -> ClosetItem {
        throw AstraError.server("not found")
    }
    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] { [] }

    func uploadCapturedImage(_ data: Data) async throws -> String {
        uploadCount += 1
        _ = data
        if let uploadError {
            throw uploadError
        }
        let path = "users/test/closet/\(UUID().uuidString.lowercased()).jpg"
        uploadedPath = path
        liveStoragePaths.insert(path)
        return path
    }

    func deleteCapturedImage(atPath storagePath: String) async throws {
        deletedPaths.append(storagePath)
        if let deleteError {
            throw deleteError
        }
        liveStoragePaths.remove(storagePath)
    }

    func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        analyzeCount += 1
        lastAnalyzeStoragePath = request.storagePath
        if let analyzeError {
            throw analyzeError
        }
        return MockClosetRepository.cannedAnalysis
    }

    func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        ClosetItemAnalysisBatch(results: [])
    }

    /// Stands in for the server rewriting the row on the way back — a
    /// canonicalised name, a trimmed colour, a category it disagreed with.
    /// Nil by default, so every existing test still sees what it sent.
    var normalizeCreated: (@Sendable (ClosetItem) -> ClosetItem)?

    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        lastCreated = item
        lastImages = images
        return normalizeCreated?(item) ?? item
    }

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

private final class FlippingNetworkMonitor: NetworkReachabilityMonitoring, @unchecked Sendable {
    private struct State {
        var isOnline: Bool
        var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    }

    private let lock = NSLock()
    private var state: State

    init(isOnline: Bool) {
        state = State(isOnline: isOnline)
    }

    func isOffline() async -> Bool {
        !currentOnlineState()
    }

    func connectivityUpdates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            let isOnline = withState { state in
                state.continuations[id] = continuation
                return state.isOnline
            }
            continuation.yield(isOnline)
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    func setOnline(_ isOnline: Bool) {
        let continuations = withState { state in
            state.isOnline = isOnline
            return Array(state.continuations.values)
        }
        for continuation in continuations {
            continuation.yield(isOnline)
        }
    }

    private func currentOnlineState() -> Bool {
        withState { $0.isOnline }
    }

    private func removeContinuation(id: UUID) {
        // No `_ =`: the closure returns Void, so discarding it is redundant and
        // the compiler says so — and the CI warning gate greps the whole
        // `ios/AstraStyle/` tree, tests included.
        withState { state in
            state.continuations[id] = nil
        }
    }

    private func withState<Value>(_ body: (inout State) -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}

private struct ReviewMockURLResolver: ClosetImageURLResolving {
    func resolve(storagePath: String) async throws -> URL {
        guard let encoded = storagePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://example.test/sign/\(encoded)") else {
            throw AstraError.server("Couldn't load that photo.")
        }
        return url
    }

    func resolve(storagePaths: [String]) async throws -> [String: URL] {
        var map: [String: URL] = [:]
        for path in storagePaths {
            map[path] = try await resolve(storagePath: path)
        }
        return map
    }
}
