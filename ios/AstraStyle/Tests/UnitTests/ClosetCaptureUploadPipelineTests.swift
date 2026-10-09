import Foundation
import XCTest
@testable import AstraStyle

final class ClosetCaptureUploadPipelineTests: XCTestCase {
    func testPairedUploadWritesBothOwnerObjectsAndReturnsOriginalPath() async throws {
        let owner = UUID()
        let sourcePath = Self.sourcePath(owner: owner)
        let probe = UploadTransportProbe(ownerIDs: [owner, owner, owner])

        let result = try await ClosetCaptureUploadPipeline.upload(
            Self.request(sourcePath: sourcePath, ownerID: owner),
            transport: probe.transport
        )

        let uploaded = await probe.uploadedPaths
        let removed = await probe.removedPathBatches
        XCTAssertEqual(result, sourcePath)
        XCTAssertEqual(uploaded, [sourcePath, try XCTUnwrap(ClosetImageVariantPaths.thumbnail(for: sourcePath))])
        XCTAssertTrue(removed.isEmpty)
    }

    func testThumbnailUploadFailureCompensatesBothUniqueOwnerObjects() async throws {
        let owner = UUID()
        let sourcePath = Self.sourcePath(owner: owner)
        let transportProbe = UploadTransportProbe(ownerIDs: [owner, owner], failThumbnailUpload: true)
        let transport = transportProbe.transport

        do {
            _ = try await ClosetCaptureUploadPipeline.upload(
                Self.request(sourcePath: sourcePath, ownerID: owner),
                transport: transport
            )
            XCTFail("Expected the thumbnail transport failure to remain visible")
        } catch {
            XCTAssertEqual((error as? AstraError)?.category, .network)
        }

        let uploaded = await transportProbe.uploadedPaths
        let removed = await transportProbe.removedPathBatches
        XCTAssertEqual(uploaded, [sourcePath, try XCTUnwrap(ClosetImageVariantPaths.thumbnail(for: sourcePath))])
        XCTAssertEqual(removed, [[sourcePath, try XCTUnwrap(ClosetImageVariantPaths.thumbnail(for: sourcePath))]])
    }

    func testAccountSwitchAfterSourceUploadPreventsThumbnailWriteAndCompensatesPair() async throws {
        let owner = UUID()
        let peer = UUID()
        let sourcePath = Self.sourcePath(owner: owner)
        let transportProbe = UploadTransportProbe(ownerIDs: [owner, peer])
        let transport = transportProbe.transport

        do {
            _ = try await ClosetCaptureUploadPipeline.upload(
                Self.request(sourcePath: sourcePath, ownerID: owner),
                transport: transport
            )
            XCTFail("Expected an account-switch error")
        } catch {
            XCTAssertEqual((error as? AstraError)?.category, .auth)
        }

        let uploaded = await transportProbe.uploadedPaths
        let removed = await transportProbe.removedPathBatches
        XCTAssertEqual(uploaded, [sourcePath])
        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed.first?.count, 2)
        XCTAssertTrue(removed.first?.contains(sourcePath) == true)
    }

    func testPeerPathIsRejectedBeforeAnyTransportCall() async throws {
        let owner = UUID()
        let peer = UUID()
        let sourcePath = Self.sourcePath(owner: peer)
        let transportProbe = UploadTransportProbe(ownerIDs: [owner])

        do {
            _ = try await ClosetCaptureUploadPipeline.upload(
                Self.request(sourcePath: sourcePath, ownerID: owner),
                transport: transportProbe.transport
            )
            XCTFail("Expected a cross-owner path to be rejected")
        } catch {
            XCTAssertEqual((error as? AstraError)?.category, .auth)
        }

        let uploaded = await transportProbe.uploadedPaths
        let removed = await transportProbe.removedPathBatches
        XCTAssertTrue(uploaded.isEmpty)
        XCTAssertTrue(removed.isEmpty)
    }

    private static func sourcePath(owner: UUID) -> String {
        "users/\(owner.uuidString.lowercased())/closet/\(UUID().uuidString.lowercased()).jpg"
    }

    private static func request(sourcePath: String, ownerID: UUID) -> ClosetCaptureUploadRequest {
        ClosetCaptureUploadRequest(
            sourceData: Data([1, 2, 3]),
            thumbnailData: Data([4, 5]),
            contentType: "image/jpeg",
            sourcePath: sourcePath,
            ownerID: ownerID
        )
    }
}

private actor UploadTransportProbe {
    private let ownerIDs: [UUID]
    private let failThumbnailUpload: Bool
    private var ownerReadCount = 0
    private(set) var uploadedPaths: [String] = []
    private(set) var removedPathBatches: [[String]] = []

    init(ownerIDs: [UUID], failThumbnailUpload: Bool = false) {
        self.ownerIDs = ownerIDs
        self.failThumbnailUpload = failThumbnailUpload
    }

    nonisolated var transport: ClosetCaptureUploadTransport {
        ClosetCaptureUploadTransport(
            currentOwnerID: { await self.currentOwnerID() },
            uploadObject: { path, _, _ in try await self.upload(path) },
            removeObjects: { paths in await self.remove(paths) }
        )
    }

    private func currentOwnerID() -> UUID? {
        defer { ownerReadCount += 1 }
        return ownerIDs[min(ownerReadCount, ownerIDs.count - 1)]
    }

    private func upload(_ path: String) throws {
        uploadedPaths.append(path)
        if failThumbnailUpload, path.contains(".thumb.") {
            throw AstraError.network("Synthetic thumbnail upload failed.")
        }
    }

    private func remove(_ paths: [String]) {
        removedPathBatches.append(paths)
    }
}
