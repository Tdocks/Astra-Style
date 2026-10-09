import XCTest
@testable import AstraStyle

final class ClosetImageVariantPathTests: XCTestCase {
    func testThumbnailPathIsDeterministicForCaptureCutoutAndGuestLocalImages() {
        let owner = UUID().uuidString.lowercased()
        let id = UUID().uuidString.lowercased()
        XCTAssertEqual(
            ClosetImageVariantPaths.thumbnail(for: "users/\(owner)/closet/\(id).jpg"),
            "users/\(owner)/closet/\(id).thumb.jpg"
        )
    }

    func testThumbnailPathPreservesCanonicalOwnerPrefixAndSourceExtension() {
        let owner = UUID().uuidString.lowercased()
        let item = UUID().uuidString.lowercased()
        let image = UUID().uuidString.lowercased()
        let source = "users/\(owner)/closet/\(item)/\(image)-cutout.png"
        XCTAssertEqual(
            ClosetImageVariantPaths.thumbnail(for: source),
            "users/\(owner)/closet/\(item)/\(image)-cutout.thumb.png"
        )
    }

    func testInvalidOrNonImagePathsDoNotProduceVariantPaths() {
        XCTAssertNil(ClosetImageVariantPaths.thumbnail(for: "users/peer/closet/../image.jpg"))
        XCTAssertNil(ClosetImageVariantPaths.thumbnail(for: "users/peer/closet/image.gif"))
        XCTAssertNil(ClosetImageVariantPaths.thumbnail(for: "users/peer/closet/not-a-uuid.jpg"))
    }

    func testGridUsesPreferredSmallVariantAndNeverFallsBackToRemoteOriginal() {
        let owner = UUID()
        let sourceID = UUID().uuidString.lowercased()
        let cutoutID = UUID().uuidString.lowercased()
        let image = ClosetItemImage(
            id: UUID(),
            closetItemID: UUID(),
            imageType: .front,
            storagePath: "users/\(owner.uuidString.lowercased())/closet/\(sourceID).jpg",
            backgroundRemovedPath: "users/\(owner.uuidString.lowercased())/closet/\(cutoutID)-cutout.png",
            thumbnailStoragePath: "users/\(owner.uuidString.lowercased())/closet/\(sourceID).thumb.jpg",
            backgroundRemovedThumbnailPath: "users/\(owner.uuidString.lowercased())/closet/\(cutoutID)-cutout.thumb.png",
            isPrimary: true
        )
        XCTAssertEqual(image.gridThumbnailStoragePath(preferringCutout: true), image.backgroundRemovedThumbnailPath)
        XCTAssertEqual(image.gridThumbnailStoragePath(preferringCutout: false), image.thumbnailStoragePath)
    }

    func testLegacyGridImageWithoutVariantFallsBackToOriginalAtBoundedDecodeSize() {
        let image = ClosetItemImage(
            id: UUID(), closetItemID: UUID(), imageType: .front,
            storagePath: "users/\(UUID().uuidString.lowercased())/closet/\(UUID().uuidString.lowercased()).jpg",
            isPrimary: true
        )
        XCTAssertEqual(image.gridThumbnailStoragePath(preferringCutout: false), image.storagePath)
        XCTAssertNil(image.gridFallbackStoragePath(preferringCutout: false))
    }

    func testLegacyCutoutWithoutVariantRemainsThePreferredGridImage() {
        let image = ClosetItemImage(
            id: UUID(),
            closetItemID: UUID(),
            imageType: .front,
            storagePath: "users/\(UUID().uuidString.lowercased())/closet/\(UUID().uuidString.lowercased()).jpg",
            backgroundRemovedPath: "users/\(UUID().uuidString.lowercased())/closet/\(UUID().uuidString.lowercased())-cutout.png",
            isPrimary: true
        )
        XCTAssertEqual(image.gridThumbnailStoragePath(preferringCutout: true), image.backgroundRemovedPath)
        XCTAssertNil(image.gridFallbackStoragePath(preferringCutout: true))
    }

    func testVariantMetadataUsesTheDeployedSnakeCaseColumnNamesAndRoundTrips() throws {
        let owner = UUID().uuidString.lowercased()
        let id = UUID().uuidString.lowercased()
        let image = ClosetItemImage(
            id: UUID(),
            closetItemID: UUID(),
            imageType: .front,
            storagePath: "users/\(owner)/closet/\(id).jpg",
            backgroundRemovedPath: "users/\(owner)/closet/\(id)-cutout.png",
            thumbnailStoragePath: "users/\(owner)/closet/\(id).thumb.jpg",
            backgroundRemovedThumbnailPath: "users/\(owner)/closet/\(id)-cutout.thumb.png",
            isPrimary: true
        )

        let encoded = try JSONEncoder().encode(image)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["thumbnail_storage_path"] as? String, image.thumbnailStoragePath)
        XCTAssertEqual(
            object["background_removed_thumbnail_path"] as? String,
            image.backgroundRemovedThumbnailPath
        )
        XCTAssertEqual(try JSONDecoder().decode(ClosetItemImage.self, from: encoded), image)
    }
}
