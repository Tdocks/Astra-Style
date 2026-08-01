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
            resolver: resolver,
            userID: userID
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
        await model.save()

        #expect(model.phase == .saved)
        let saved = try #require(repository.lastCreated)
        #expect(saved.brand == "Drake's")
        #expect(saved.name == "Cotton Crewneck Sweater")
        #expect(repository.lastImages?.first?.storagePath == model.storagePath)
        #expect(store.draft(id: draft.id) == nil)
    }

    @Test("Upload failure keeps the local draft and retry re-invokes upload")
    func uploadFailureIsRetryable() async throws {
        let jpeg = try #require(fixtureJPEG())
        let prepared = try CapturePreparation.prepareForUpload(jpeg)
        let draft = CaptureDraft(prepared: prepared)
        let store = CaptureDraftStore()
        store.put(draft)

        let repository = ReviewMockClosetRepository()
        repository.uploadShouldFail = true
        let model = makeModel(draftID: draft.id, store: store, repository: repository)

        await model.start()
        guard case .uploadFailed = model.phase else {
            Issue.record("Expected uploadFailed, got \(model.phase)")
            return
        }
        #expect(model.localPreviewData != nil)
        #expect(repository.analyzeCount == 0)

        repository.uploadShouldFail = false
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
        repository.analyzeShouldFail = true
        let model = makeModel(draftID: draft.id, store: store, repository: repository)

        await model.start()
        guard case .analyzeFailed = model.phase else {
            Issue.record("Expected analyzeFailed, got \(model.phase)")
            return
        }
        #expect(repository.uploadCount == 1)

        repository.analyzeShouldFail = false
        await model.retryAnalyze()
        #expect(model.phase == .ready)
        #expect(repository.uploadCount == 1)
        #expect(repository.analyzeCount == 2)
        #expect(repository.lastAnalyzeStoragePath != nil)
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
        resolver: ClosetImageURLResolving = ReviewMockURLResolver(),
        userID: UUID = UUID()
    ) -> ScannerReviewViewModel {
        ScannerReviewViewModel(
            draftID: draftID,
            dependencies: .init(
                draftStore: store,
                closetRepository: repository,
                imageURLResolver: resolver,
                currentUserID: { userID }
            )
        )
    }
}

// MARK: - Fixtures / doubles

private func fixtureJPEG() -> Data? {
    guard let image = ScannerImageFixtures.checkerboard(width: 640, height: 480, cell: 16) else {
        return nil
    }
    return ScannerImageFixtures.jpegData(from: image, includeMetadata: false)
}

private final class ReviewMockClosetRepository: ClosetRepository, @unchecked Sendable {
    var uploadCount = 0
    var analyzeCount = 0
    var uploadShouldFail = false
    var analyzeShouldFail = false
    var lastCreated: ClosetItem?
    var lastImages: [ClosetItemImage]?
    var lastAnalyzeStoragePath: String?
    private var uploadedPath: String?

    func fetchItems() async throws -> [ClosetItem] { [] }
    func fetchItem(id: UUID) async throws -> ClosetItem {
        throw AstraError.server("not found")
    }
    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] { [] }

    func uploadCapturedImage(_ data: Data) async throws -> String {
        uploadCount += 1
        _ = data
        if uploadShouldFail {
            throw AstraError.network("upload failed")
        }
        let path = "users/test/closet/\(UUID().uuidString.lowercased()).jpg"
        uploadedPath = path
        return path
    }

    func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        analyzeCount += 1
        lastAnalyzeStoragePath = request.storagePath
        if analyzeShouldFail {
            throw AstraError.provider("analyze failed")
        }
        return MockClosetRepository.cannedAnalysis
    }

    func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        ClosetItemAnalysisBatch(results: [])
    }

    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        lastCreated = item
        lastImages = images
        return item
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
