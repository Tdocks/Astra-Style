import Foundation
import XCTest
@testable import AstraStyle

@MainActor
final class ClosetGridImageResolutionTests: XCTestCase {
    func testKnownVariantAndOriginalAreSignedOnceButOnlyVariantIsPrefetched() async throws {
        let item = try XCTUnwrap(SampleData.closetItems.first)
        let image = makeImage(item: item, includesThumbnail: true)
        let resolver = RecordingResolver()
        let viewModel = ClosetViewModel(
            closetRepository: MockClosetRepository(items: [item], imagesByItemID: [item.id: [image]]),
            imageURLResolver: resolver
        )
        await viewModel.onAppear()

        viewModel.imageNeeded(for: item)
        await viewModel.awaitPendingImageResolution()

        let requested = await resolver.lastPaths
        let prefetched = await resolver.lastPrefetchPaths
        XCTAssertEqual(Set(requested), Set([try XCTUnwrap(image.thumbnailStoragePath), image.storagePath]))
        XCTAssertEqual(prefetched, Set([try XCTUnwrap(image.thumbnailStoragePath)]))
        XCTAssertTrue(viewModel.imageURL(for: item)?.path().hasSuffix(try XCTUnwrap(image.thumbnailStoragePath)) == true)
        XCTAssertTrue(viewModel.imageFallbackURL(for: item)?.path().hasSuffix(image.storagePath) == true)
        let callCount = await resolver.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testBatchSigningMissingVariantPromotesOriginalWithoutRetrying() async throws {
        let item = try XCTUnwrap(SampleData.closetItems.first)
        let image = makeImage(item: item, includesThumbnail: true)
        let missingPath = try XCTUnwrap(image.thumbnailStoragePath)
        let resolver = RecordingResolver(missingPaths: [missingPath])
        let viewModel = ClosetViewModel(
            closetRepository: MockClosetRepository(items: [item], imagesByItemID: [item.id: [image]]),
            imageURLResolver: resolver
        )
        await viewModel.onAppear()

        viewModel.imageNeeded(for: item)
        await viewModel.awaitPendingImageResolution()

        XCTAssertTrue(viewModel.imageURL(for: item)?.path().hasSuffix(image.storagePath) == true)
        XCTAssertNil(viewModel.imageFallbackURL(for: item))
        let callCount = await resolver.callCount
        let prefetchPaths = await resolver.lastPrefetchPaths
        XCTAssertEqual(callCount, 1)
        XCTAssertFalse(prefetchPaths.contains(image.storagePath))
    }

    func testLegacyRowResolvesOriginalAndKeepsPhotoVisibleForBoundedDecode() async throws {
        let item = try XCTUnwrap(SampleData.closetItems.first)
        let image = makeImage(item: item, includesThumbnail: false)
        let resolver = RecordingResolver()
        let viewModel = ClosetViewModel(
            closetRepository: MockClosetRepository(items: [item], imagesByItemID: [item.id: [image]]),
            imageURLResolver: resolver
        )
        await viewModel.onAppear()

        viewModel.imageNeeded(for: item)
        await viewModel.awaitPendingImageResolution()

        XCTAssertTrue(viewModel.imageURL(for: item)?.path().hasSuffix(image.storagePath) == true)
        XCTAssertNil(viewModel.imageFallbackURL(for: item))
        let prefetchPaths = await resolver.lastPrefetchPaths
        XCTAssertEqual(prefetchPaths, Set([image.storagePath]))
    }

    private func makeImage(item: ClosetItem, includesThumbnail: Bool) -> ClosetItemImage {
        let imageID = UUID().uuidString.lowercased()
        let prefix = "users/\(item.userID.uuidString.lowercased())/closet/"
        let sourcePath = "\(prefix)\(imageID).jpg"
        return ClosetItemImage(
            id: UUID(),
            closetItemID: item.id,
            imageType: .front,
            storagePath: sourcePath,
            thumbnailStoragePath: includesThumbnail ? "\(prefix)\(imageID).thumb.jpg" : nil,
            isPrimary: true
        )
    }
}

private actor RecordingResolver: ClosetImageURLResolving {
    private let missingPaths: Set<String>
    private(set) var callCount = 0
    private(set) var lastPaths: [String] = []
    private(set) var lastPrefetchPaths: Set<String> = []

    init(missingPaths: Set<String> = []) {
        self.missingPaths = missingPaths
    }

    func resolve(storagePath: String) async throws -> URL {
        guard let url = Self.url(for: storagePath) else {
            throw AstraError.server("Couldn't resolve the synthetic closet image.")
        }
        return url
    }

    func resolve(storagePaths: [String]) async throws -> [String: URL] {
        try await resolve(storagePaths: storagePaths, prefetching: Set(storagePaths))
    }

    func resolve(storagePaths: [String], prefetching pathsToPrefetch: Set<String>) async throws -> [String: URL] {
        callCount += 1
        lastPaths = storagePaths
        lastPrefetchPaths = pathsToPrefetch
        return storagePaths.reduce(into: [:]) { result, path in
            if !missingPaths.contains(path), let url = Self.url(for: path) {
                result[path] = url
            }
        }
    }

    private static func url(for path: String) -> URL? {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://images.astrastyle.invalid/\(encoded)")
    }
}
