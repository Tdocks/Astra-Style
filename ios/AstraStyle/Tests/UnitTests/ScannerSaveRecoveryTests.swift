import Foundation
import SwiftData
import Testing
@testable import AstraStyle

@Suite("Scanner save journal recovery")
struct ScannerSaveRecoveryTests {
    private actor Remote: ScannerSaveRemoteWriting {
        var item: ClosetItem?
        var shouldFail = false
        private(set) var ensured: [ClosetItemImage] = []
        private(set) var lookupCount = 0

        init(item: ClosetItem? = nil) { self.item = item }
        func setFailure(_ value: Bool) { shouldFail = value }
        func remoteScannerItem(id: UUID) async throws -> ClosetItem? {
            lookupCount += 1
            try await Task.sleep(for: .milliseconds(20))
            if shouldFail { throw AstraError.network("offline") }
            return item?.id == id ? item : nil
        }
        func ensureScannerImages(_ images: [ClosetItemImage]) async throws {
            if shouldFail { throw AstraError.network("offline") }
            ensured.append(contentsOf: images)
        }
    }

    private actor ActiveOwner {
        private var value: UUID?
        init(_ value: UUID?) { self.value = value }
        func get() -> UUID? { value }
        func set(_ ownerID: UUID?) { value = ownerID }
    }

    private func item(owner: UUID, name: String = "Navy overshirt") -> ClosetItem {
        ClosetItem(id: UUID(), userID: owner, name: name, category: .top)
    }

    private func image(for item: ClosetItem, path: String? = nil) -> ClosetItemImage {
        let imagePath = path ?? "users/\(item.userID.uuidString.lowercased())/closet/\(UUID().uuidString.lowercased()).jpg"
        return ClosetItemImage(id: UUID(), closetItemID: item.id, imageType: .front, storagePath: imagePath, isPrimary: true)
    }

    @Test("Existing remote garment keeps newer fields and only ensures stable photo rows")
    func existingRemoteIsNotOverwritten() async throws {
        let owner = UUID()
        let local = item(owner: owner)
        let sameRemoteID = ClosetItem(id: local.id, userID: owner, name: "Newer remote name", category: .top)
        let photo = image(for: local)
        let journal = InMemoryScannerSaveJournal()
        let record = PendingScannerSave(ownerID: owner, item: local, images: [photo])
        try await journal.save(record)
        let remote = Remote(item: sameRemoteID)
        let base = MockClosetRepository(items: [])
        let capped = FreeTierCappedClosetRepository(base: base, isEntitledToPremium: { true })
        let service = ScannerSaveRecoveryService(journal: journal, repository: capped, remote: remote, currentUserID: { owner })

        await service.recover(ownerID: owner)

        #expect(await remote.ensured == [photo])
        #expect(try await journal.pendingSaves(for: owner).isEmpty)
        #expect(try await base.fetchItems().isEmpty, "Existing row reconciliation must not create or overwrite a garment")
    }

    @Test("Absent remote garment is retried through the cap wrapper")
    func absentRemoteUsesCappedRepository() async throws {
        let owner = UUID()
        let target = item(owner: owner)
        let existing = (0..<FreeTierLimits.maxClosetItems).map { index in
            ClosetItem(id: UUID(), userID: owner, name: "Existing \(index)", category: .top)
        }
        let journal = InMemoryScannerSaveJournal()
        try await journal.save(PendingScannerSave(ownerID: owner, item: target, images: [image(for: target)]))
        let remote = Remote()
        let base = MockClosetRepository(items: existing)
        let capped = FreeTierCappedClosetRepository(base: base, isEntitledToPremium: { false })
        let service = ScannerSaveRecoveryService(journal: journal, repository: capped, remote: remote, currentUserID: { owner })

        await service.recover(ownerID: owner)

        #expect(try await journal.pendingSaves(for: owner).count == 1)
        #expect(try await base.fetchItems().count == FreeTierLimits.maxClosetItems)
    }

    @Test("Another account cannot reconcile or clear this owner's journal")
    func peerOwnerIsIsolated() async throws {
        let owner = UUID()
        let peer = UUID()
        let target = item(owner: owner)
        let journal = InMemoryScannerSaveJournal()
        try await journal.save(PendingScannerSave(ownerID: owner, item: target, images: [image(for: target)]))
        let remote = Remote()
        let base = MockClosetRepository(items: [])
        let service = ScannerSaveRecoveryService(
            journal: journal, repository: base, remote: remote, currentUserID: { peer }
        )

        await service.recover(ownerID: owner)

        #expect(try await journal.pendingSaves(for: owner).count == 1)
        #expect(await remote.ensured.isEmpty)
        #expect(try await base.fetchItems().isEmpty)
    }

    @Test("Network uncertainty retains the journal for another attempt")
    func uncertainRemoteReadRetainsJournal() async throws {
        let owner = UUID()
        let target = item(owner: owner)
        let journal = InMemoryScannerSaveJournal()
        try await journal.save(PendingScannerSave(ownerID: owner, item: target, images: [image(for: target)]))
        let remote = Remote()
        await remote.setFailure(true)
        let base = MockClosetRepository(items: [])
        let service = ScannerSaveRecoveryService(journal: journal, repository: base, remote: remote, currentUserID: { owner })

        await service.recover(ownerID: owner)

        #expect(try await journal.pendingSaves(for: owner).count == 1)
        #expect(try await base.fetchItems().isEmpty)
    }

    @Test("A remote row owned by another account is never used to clear the journal")
    func peerRemoteRowIsRejected() async throws {
        let owner = UUID()
        let target = item(owner: owner)
        let peerRow = ClosetItem(id: target.id, userID: UUID(), name: "Peer row", category: .top)
        let journal = InMemoryScannerSaveJournal()
        try await journal.save(PendingScannerSave(ownerID: owner, item: target, images: [image(for: target)]))
        let remote = Remote(item: peerRow)
        let base = MockClosetRepository(items: [])
        let service = ScannerSaveRecoveryService(journal: journal, repository: base, remote: remote, currentUserID: { owner })

        await service.recover(ownerID: owner)

        #expect(try await journal.pendingSaves(for: owner).count == 1)
        #expect(await remote.ensured.isEmpty)
        #expect(try await base.fetchItems().isEmpty)
    }

    @Test("Recovery skips a save currently owned by the foreground flow")
    func activeForegroundSaveIsNotReplayed() async throws {
        let owner = UUID()
        let target = item(owner: owner)
        let journal = InMemoryScannerSaveJournal()
        let record = PendingScannerSave(ownerID: owner, item: target, images: [image(for: target)])
        #expect(await journal.beginForegroundSave(id: record.id, ownerID: owner))
        try await journal.save(record)
        let remote = Remote()
        let base = MockClosetRepository(items: [])
        let service = ScannerSaveRecoveryService(journal: journal, repository: base, remote: remote, currentUserID: { owner })

        await service.recover(ownerID: owner)

        #expect(await remote.lookupCount == 0)
        #expect(try await journal.pendingSaves(for: owner).count == 1)
        await journal.endForegroundSave(id: record.id, ownerID: owner)
        await service.recover(ownerID: owner)
        #expect(try await journal.pendingSaves(for: owner).isEmpty)
    }

    @Test("Malformed image ownership is retained without making a remote request")
    func malformedImageOwnerIsRejected() async throws {
        let owner = UUID()
        let target = item(owner: owner)
        let otherItem = item(owner: owner)
        let journal = InMemoryScannerSaveJournal()
        try await journal.save(PendingScannerSave(ownerID: owner, item: target, images: [image(for: otherItem)]))
        let remote = Remote()
        let base = MockClosetRepository(items: [])
        let service = ScannerSaveRecoveryService(journal: journal, repository: base, remote: remote, currentUserID: { owner })

        await service.recover(ownerID: owner)

        #expect(await remote.lookupCount == 0)
        #expect(try await journal.pendingSaves(for: owner).count == 1)
    }

    @Test("An empty image list is invalid and cannot create a photo-less garment")
    func emptyImageRecordIsRejected() async throws {
        let owner = UUID()
        let target = item(owner: owner)
        let journal = InMemoryScannerSaveJournal()
        try await journal.save(PendingScannerSave(ownerID: owner, item: target, images: []))
        let remote = Remote()
        let base = MockClosetRepository(items: [])
        let service = ScannerSaveRecoveryService(journal: journal, repository: base, remote: remote, currentUserID: { owner })

        await service.recover(ownerID: owner)

        #expect(await remote.lookupCount == 0)
        #expect(try await journal.pendingSaves(for: owner).count == 1)
        #expect(try await base.fetchItems().isEmpty)
    }

    @Test("A recovery record without a primary front image is retained")
    func missingPrimaryFrontImageIsRejected() async throws {
        let owner = UUID()
        let target = item(owner: owner)
        let nonPrimary = ClosetItemImage(
            id: UUID(), closetItemID: target.id, imageType: .front,
            storagePath: "users/\(owner.uuidString.lowercased())/closet/source.jpg", isPrimary: false
        )
        let journal = InMemoryScannerSaveJournal()
        try await journal.save(PendingScannerSave(ownerID: owner, item: target, images: [nonPrimary]))
        let remote = Remote()
        let base = MockClosetRepository(items: [])
        let service = ScannerSaveRecoveryService(journal: journal, repository: base, remote: remote, currentUserID: { owner })

        await service.recover(ownerID: owner)

        #expect(await remote.lookupCount == 0)
        #expect(try await journal.pendingSaves(for: owner).count == 1)
        #expect(try await base.fetchItems().isEmpty)
    }

    @Test("Concurrent recovery passes do not replay the same journal record twice")
    func concurrentRecoveryIsSerialized() async throws {
        let owner = UUID()
        let target = item(owner: owner)
        let journal = InMemoryScannerSaveJournal()
        try await journal.save(PendingScannerSave(ownerID: owner, item: target, images: [image(for: target)]))
        let remote = Remote()
        let base = MockClosetRepository(items: [])
        let service = ScannerSaveRecoveryService(journal: journal, repository: base, remote: remote, currentUserID: { owner })

        async let first: Void = service.recover(ownerID: owner)
        async let second: Void = service.recover(ownerID: owner)
        _ = await (first, second)

        #expect(await remote.lookupCount == 1)
        #expect(try await journal.pendingSaves(for: owner).isEmpty)
        #expect(try await base.fetchItem(id: target.id).userID == owner)
    }

    @Test("A new owner's recovery is queued behind an older owner's active pass")
    func recoveryQueuesChangedOwner() async throws {
        let firstOwner = UUID()
        let secondOwner = UUID()
        let firstItem = item(owner: firstOwner)
        let secondItem = item(owner: secondOwner)
        let journal = InMemoryScannerSaveJournal()
        try await journal.save(PendingScannerSave(ownerID: firstOwner, item: firstItem, images: [image(for: firstItem)]))
        try await journal.save(PendingScannerSave(ownerID: secondOwner, item: secondItem, images: [image(for: secondItem)]))
        let remote = Remote()
        let base = MockClosetRepository(items: [])
        let activeOwner = ActiveOwner(firstOwner)
        let service = ScannerSaveRecoveryService(
            journal: journal, repository: base, remote: remote, currentUserID: { await activeOwner.get() }
        )

        let firstPass = Task { await service.recover(ownerID: firstOwner) }
        for _ in 0..<20 where await remote.lookupCount == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }
        await activeOwner.set(secondOwner)
        await service.recover(ownerID: secondOwner)
        await firstPass.value

        #expect(await remote.lookupCount == 2)
        #expect(try await journal.pendingSaves(for: firstOwner).count == 1)
        #expect(try await journal.pendingSaves(for: secondOwner).isEmpty)
        #expect(try await base.fetchItem(id: secondItem.id).userID == secondOwner)
    }

    @Test("Recovery holds an exclusive claim against a foreground retry")
    func recoveryClaimExcludesForegroundSave() async throws {
        let owner = UUID()
        let target = item(owner: owner)
        let journal = InMemoryScannerSaveJournal()
        try await journal.save(PendingScannerSave(ownerID: owner, item: target, images: [image(for: target)]))
        let remote = Remote()
        let base = MockClosetRepository(items: [])
        let service = ScannerSaveRecoveryService(journal: journal, repository: base, remote: remote, currentUserID: { owner })

        let recovery = Task { await service.recover(ownerID: owner) }
        for _ in 0..<20 where await remote.lookupCount == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(await journal.beginForegroundSave(id: target.id, ownerID: owner) == false)
        await recovery.value
        #expect(try await journal.pendingSaves(for: owner).isEmpty)
    }

    @Test("A saved journal survives opening a second SwiftData container on the same store")
    func swiftDataJournalPersistsAcrossContainerReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("scanner-journal.store")
        let owner = UUID()
        let target = item(owner: owner)
        let record = PendingScannerSave(ownerID: owner, item: target, images: [image(for: target)])
        do {
            let config = ModelConfiguration(schema: AstraModelContainer.schema, url: url)
            let container = try ModelContainer(for: AstraModelContainer.schema, configurations: [config])
            try await SwiftDataScannerSaveJournal(modelContainer: container).save(record)
        }
        let reopenedConfig = ModelConfiguration(schema: AstraModelContainer.schema, url: url)
        let reopened = try ModelContainer(for: AstraModelContainer.schema, configurations: [reopenedConfig])
        let records = try await SwiftDataScannerSaveJournal(modelContainer: reopened).pendingSaves(for: owner)
        #expect(records == [record])
    }
}
