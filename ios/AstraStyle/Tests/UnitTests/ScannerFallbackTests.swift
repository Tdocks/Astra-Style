import Foundation
import Testing
@testable import AstraStyle

@Suite("Captured image upload format")
struct CapturedImageUploadFormatTests {
    @Test("Transparent PNG cutouts retain PNG metadata")
    func pngMetadata() throws {
        let format = try CapturedImageUploadFormat.detect(Data([137, 80, 78, 71, 13, 10, 26, 10]))
        #expect(format.fileExtension == "png")
        #expect(format.contentType == "image/png")
    }

    @Test("Prepared JPEG captures retain JPEG metadata")
    func jpegMetadata() throws {
        let format = try CapturedImageUploadFormat.detect(Data([255, 216, 255, 224]))
        #expect(format.fileExtension == "jpg")
        #expect(format.contentType == "image/jpeg")
    }

    @Test("Unsupported bytes are rejected")
    func unsupportedBytes() {
        #expect(throws: AstraError.self) {
            try CapturedImageUploadFormat.detect(Data([1, 2, 3]))
        }
    }
}

@Suite("Scanner fallback path contract")
struct ClosetCutoutPathTests {
    @Test("Fallback endpoint requires authentication and stable idempotency")
    func endpointContract() {
        #expect(AstraEndpoint.removeClosetBackground.path == "closet/remove-background")
        #expect(AstraEndpoint.removeClosetBackground.method == .post)
        #expect(AstraEndpoint.removeClosetBackground.requiresAuthentication)
        #expect(AstraEndpoint.removeClosetBackground.requiresIdempotencyKey)
    }
    @Test("Fallback accepts only a canonical owned source and deterministic output")
    func ownedPath() throws {
        let owner = UUID()
        let source = "users/\(owner.uuidString.lowercased())/closet/\(UUID().uuidString.lowercased()).jpg"
        #expect(try ClosetCutoutPath.expectedOutput(source: source, owner: owner) == String(source.dropLast(4)) + "-cutout.png")
        for path in [source + "/../other.jpg", source.replacingOccurrences(of: ".jpg", with: ".png"),
                     source.replacingOccurrences(of: owner.uuidString.lowercased(), with: UUID().uuidString.lowercased())] {
            #expect(throws: AstraError.self) { try ClosetCutoutPath.expectedOutput(source: path, owner: owner) }
        }
    }
}

@Suite("Scanner fallback invocation")
@MainActor
struct ScannerFallbackInvocationTests {
    @Test("Server fallback is used only for missing device cutouts and skips guest paths")
    func serverFallbackGating() async {
        let repository = ReviewMockClosetRepository()
        repository.fallbackPath = "users/test/closet/fixture-cutout.png"
        let model = makeModel(repository: repository)
        model.storagePath = "users/test/closet/fixture.jpg"
        let path = await model.persistCutoutOrFallback(nil)
        #expect(path == repository.fallbackPath)
        #expect(repository.fallbackCount == 1)
        model.storagePath = "guest-local/fixture.jpg"
        #expect(await model.persistCutoutOrFallback(nil) == nil)
        #expect(repository.fallbackCount == 1)
    }

    @Test("Usable device cutout upload failure does not invoke paid fallback")
    func deviceUploadFailureDoesNotProcessAgain() async {
        let repository = ReviewMockClosetRepository()
        repository.uploadError = .network("fixture upload failure")
        let model = makeModel(repository: repository)
        model.storagePath = "users/test/closet/fixture.jpg"
        #expect(await model.persistCutoutOrFallback(Data([1])) == nil)
        #expect(repository.uploadCount == 1)
        #expect(repository.fallbackCount == 0)
    }

    @Test("Successful cutout is reused and discarded with its unsaved capture")
    func reuseAndDiscard() async throws {
        let repository = ReviewMockClosetRepository()
        let model = makeModel(repository: repository)
        let source = "users/test/closet/source.jpg"
        model.storagePath = source
        let first = try #require(await model.persistCutoutOrFallback(Data([1])))
        #expect(await model.persistCutoutOrFallback(Data([1])) == first)
        #expect(repository.uploadCount == 1)
        await model.discardUnsavedUpload()
        #expect(Set(repository.deletedPaths) == Set([source, first]))
        #expect(repository.liveStoragePaths.isEmpty)
        await model.discardUnsavedUpload()
        #expect(repository.deletedPaths.count == 2)
    }

    @Test("Saved capture and cutout are retained on dismissal")
    func savedCutoutIsRetained() async throws {
        let repository = ReviewMockClosetRepository()
        let model = makeModel(repository: repository)
        model.storagePath = "users/test/closet/source.jpg"
        _ = try #require(await model.persistCutoutOrFallback(Data([1])))
        model.phase = .saved
        await model.discardUnsavedUpload()
        #expect(repository.deletedPaths.isEmpty)
    }

    @Test("A cutout completing after dismissal is removed instead of cached")
    func dismissalDuringUpload() async {
        let repository = ReviewMockClosetRepository()
        let model = makeModel(repository: repository)
        model.storagePath = "users/test/closet/source.jpg"
        repository.uploadHook = { await model.discardUnsavedUpload() }
        #expect(await model.persistCutoutOrFallback(Data([1])) == nil)
        #expect(repository.liveStoragePaths.isEmpty)
        #expect(repository.deletedPaths.count == 2)
        repository.uploadHook = nil
    }

    private func makeModel(repository: ClosetRepository) -> ScannerReviewViewModel {
        let owner = UUID()
        return ScannerReviewViewModel(draftID: UUID(), dependencies: .init(
            draftStore: CaptureDraftStore(), closetRepository: repository,
            imageURLResolver: ReviewMockURLResolver(), pendingScanQueue: InMemoryPendingScanQueue(),
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false), currentUserID: { owner }
        ))
    }
}
