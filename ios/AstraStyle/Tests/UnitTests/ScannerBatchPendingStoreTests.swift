import Foundation
import Testing
@testable import AstraStyle

@Suite("Scanner batch pending store")
struct ScannerBatchPendingStoreTests {
    private let ownerID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA") ?? UUID()

    @Test("only canonical owner-scoped batch paths can be restored")
    func validatesCanonicalOwnerPaths() {
        let imageID = UUID().uuidString.lowercased()
        #expect(isValidScannerBatchStoragePath(
            "users/\(ownerID.uuidString.lowercased())/closet/batch/\(imageID).jpg",
            ownerID: ownerID
        ))
        #expect(isValidScannerBatchStoragePath(
            "guest-local/\(ownerID.uuidString.lowercased())/\(imageID).png",
            ownerID: ownerID
        ))
        #expect(!isValidScannerBatchStoragePath(
            "users/\(UUID().uuidString.lowercased())/closet/batch/\(imageID).jpg",
            ownerID: ownerID
        ))
        #expect(!isValidScannerBatchStoragePath(
            "users/\(ownerID.uuidString.lowercased())/closet/batch/../\(imageID).jpg",
            ownerID: ownerID
        ))
    }

    @Test("a replacement keeps a readable owner manifest")
    func savesAndReopensManifest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanner-batch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileScannerBatchPendingStore(directoryURL: directory)
        let first = makeRecord(selected: 2)
        let updated = makeRecord(selected: 3)

        try await store.save(first)
        try await store.save(updated)

        let reopened = try await store.load(ownerID: ownerID)
        #expect(reopened?.idempotencyKey == updated.idempotencyKey)
        #expect(reopened?.selected == 3)
        try await store.remove(ownerID: ownerID)
        let removed = try await store.load(ownerID: ownerID)
        #expect(removed == nil)
    }

    private func makeRecord(selected: Int) -> ScannerBatchPendingRecord {
        let imageID = UUID()
        let path = "users/\(ownerID.uuidString.lowercased())/closet/batch/\(imageID.uuidString.lowercased()).jpg"
        return ScannerBatchPendingRecord(
            ownerID: ownerID,
            idempotencyKey: UUID().uuidString.lowercased(),
            entries: [ScannerBatchPendingEntry(
                id: imageID,
                data: Data([1, 2, 3]),
                pixelWidth: 10,
                pixelHeight: 20,
                originalByteCount: 30,
                deviceHints: nil,
                storagePath: path
            )],
            selected: selected,
            skippedOverLimit: 0,
            couldNotLoad: 0,
            unreadable: 0,
            uploadFailed: 0
        )
    }
}
