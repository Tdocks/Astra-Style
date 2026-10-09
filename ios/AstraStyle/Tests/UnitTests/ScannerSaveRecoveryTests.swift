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

@Suite("SwiftData schema migrations")
struct AstraModelContainerMigrationTests {
    private struct Fixture {
        let owner = UUID()
        let closetID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_725_000_000)
        let outfitPayload = Data("legacy-outfit-payload".utf8)
        let briefPayload = Data("legacy-weather-payload".utf8)
        let mutationPayload = Data("legacy-mutation-payload".utf8)
    }

    @Test("Versioned live schema upgrades each historical unversioned store and preserves rows")
    func historicalUnversionedStoresUpgradeWithoutLosingRows() throws {
        for (name, oldSchema) in legacySchemas() {
            let fixture = Fixture()
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let storeURL = directory.appendingPathComponent("legacy.store")
            try createLegacyStore(schema: oldSchema, storeURL: storeURL, name: name, fixture: fixture)

            // Reopening twice checks both migration and durable version metadata.
            for _ in 0..<2 {
                do {
                    let upgraded = try AstraModelContainer.live(storeURL: storeURL)
                    try expectLegacyRows(in: upgraded, storeName: name, fixture: fixture)
                }
            }
        }
    }

    private func legacySchemas() -> [(String, Schema)] {
        let schemas: [(String, Schema)] = [
            ("four-entities", Schema([
                PersistedClosetItem.self,
                PersistedOutfit.self,
                PersistedDailyBrief.self,
                PersistedOfflineMutation.self
            ])),
            ("five-entities", Schema([
                PersistedClosetItem.self,
                PersistedOutfit.self,
                PersistedDailyBrief.self,
                PersistedOfflineMutation.self,
                PersistedPendingScan.self
            ])),
            ("six-entities", Schema([
                PersistedClosetItem.self,
                PersistedOutfit.self,
                PersistedDailyBrief.self,
                PersistedOfflineMutation.self,
                PersistedPendingScan.self,
                PersistedScannerSave.self
            ]))
        ]
        return schemas
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createLegacyStore(schema: Schema, storeURL: URL, name: String, fixture: Fixture) throws {
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        insertCommonRows(into: context, fixture: fixture)
        if name != "four-entities" { context.insert(pendingScan(timestamp: fixture.timestamp)) }
        if name == "six-entities" { context.insert(scannerSave(fixture: fixture)) }
        try context.save()
    }

    private func insertCommonRows(into context: ModelContext, fixture: Fixture) {
        let timestamp = fixture.timestamp
        context.insert(PersistedClosetItem(
            id: fixture.closetID, userID: fixture.owner, name: "Legacy coat", brand: "Astra",
            categoryRaw: "outerwear", subcategory: "coat", primaryColor: "navy",
            secondaryColors: ["gray"], patternRaw: "solid", material: ["wool"], size: "M",
            fitRaw: "regular", conditionRaw: "good", seasonalityRaw: ["winter"],
            formalityScore: 3, warmthScore: 5, waterResistanceScore: 2,
            purchaseDate: timestamp, pricePaidMinorUnits: 12_500, currency: "USD",
            retailer: "Astra Shop", productURLString: "https://example.com/coat",
            wearCount: 7, lastWornAt: timestamp, laundryStateRaw: "clean",
            availabilityStateRaw: "available", archivedAt: nil,
            primaryImageStoragePath: "users/legacy/coat.jpg", createdAt: timestamp,
            updatedAt: timestamp, pendingSync: true
        ))
        context.insert(PersistedOutfit(
            id: UUID(), userID: fixture.owner, name: "Legacy outfit", itemDescription: "Coat and boots",
            occasionTags: ["work", "winter"], formalityScore: 3, compatibilityScore: 82,
            sourceRaw: "manual", heroImageURLString: "https://example.com/outfit.jpg",
            isFavorite: true, createdAt: timestamp, updatedAt: timestamp,
            encodedItems: fixture.outfitPayload, pendingSync: true
        ))
        context.insert(PersistedDailyBrief(
            id: UUID(), userID: fixture.owner, briefDate: timestamp, primaryOutfitID: nil,
            alternativeOutfitIDs: [UUID()], kyraMessage: "Legacy brief",
            encodedWeatherSnapshot: fixture.briefPayload, encodedScheduleSnapshot: nil, cachedAt: timestamp
        ))
        context.insert(PersistedOfflineMutation(
            id: UUID(), entityRaw: "closet_item", operationRaw: "update",
            payloadData: fixture.mutationPayload, enqueuedAt: timestamp, attemptCount: 3
        ))
    }

    private func pendingScan(timestamp: Date) -> PersistedPendingScan {
        PersistedPendingScan(
            id: UUID(), jpegData: Data([0xff, 0xd8, 0xff]),
            deviceHintsData: Data("legacy-hints".utf8), enqueuedAt: timestamp, attemptCount: 2
        )
    }

    private func scannerSave(fixture: Fixture) -> PersistedScannerSave {
        PersistedScannerSave(
            id: fixture.closetID, ownerID: fixture.owner,
            itemData: Data("legacy-item-json".utf8), imagesData: Data("legacy-images-json".utf8),
            createdAt: fixture.timestamp
        )
    }

    private func expectLegacyRows(
        in container: ModelContainer,
        storeName: String,
        fixture: Fixture
    ) throws {
        let context = ModelContext(container)
        let closetRows = try context.fetch(FetchDescriptor<PersistedClosetItem>())
        let outfitRows = try context.fetch(FetchDescriptor<PersistedOutfit>())
        let briefRows = try context.fetch(FetchDescriptor<PersistedDailyBrief>())
        let mutationRows = try context.fetch(FetchDescriptor<PersistedOfflineMutation>())
        expectCoreRows(closetRows, outfits: outfitRows, briefs: briefRows, mutations: mutationRows, fixture: fixture)
        try expectNewerRows(in: context, storeName: storeName, fixture: fixture)
    }

    private func expectCoreRows(
        _ closetRows: [PersistedClosetItem],
        outfits: [PersistedOutfit],
        briefs: [PersistedDailyBrief],
        mutations: [PersistedOfflineMutation],
        fixture: Fixture
    ) {
        let storeName = "historical unversioned store"
        #expect(closetRows.count == 1, "Closet row lost migrating \(storeName)")
        #expect(outfits.count == 1, "Outfit row lost migrating \(storeName)")
        #expect(briefs.count == 1, "Daily brief lost migrating \(storeName)")
        #expect(mutations.count == 1, "Offline mutation lost migrating \(storeName)")
        if let closet = closetRows.first {
            #expect(closet.id == fixture.closetID)
            #expect(closet.userID == fixture.owner)
            #expect(closet.name == "Legacy coat")
            #expect(closet.secondaryColors == ["gray"])
            #expect(closet.material == ["wool"])
            #expect(closet.purchaseDate == fixture.timestamp)
            #expect(closet.pricePaidMinorUnits == 12_500)
            #expect(closet.primaryImageStoragePath == "users/legacy/coat.jpg")
            #expect(closet.createdAt == fixture.timestamp && closet.updatedAt == fixture.timestamp)
            #expect(closet.pendingSync)
        }
        if let outfit = outfits.first {
            #expect(outfit.userID == fixture.owner)
            #expect(outfit.occasionTags == ["work", "winter"])
            #expect(outfit.encodedItems == fixture.outfitPayload)
            #expect(outfit.createdAt == fixture.timestamp && outfit.updatedAt == fixture.timestamp)
            #expect(outfit.pendingSync && outfit.isFavorite)
        }
        if let brief = briefs.first {
            #expect(brief.userID == fixture.owner)
            #expect(brief.encodedWeatherSnapshot == fixture.briefPayload)
            #expect(brief.encodedScheduleSnapshot == nil)
            #expect(brief.cachedAt == fixture.timestamp)
        }
        if let mutation = mutations.first {
            #expect(mutation.payloadData == fixture.mutationPayload)
            #expect(mutation.enqueuedAt == fixture.timestamp)
            #expect(mutation.attemptCount == 3)
        }
    }

    private func expectNewerRows(in context: ModelContext, storeName: String, fixture: Fixture) throws {
        let scanRows = try context.fetch(FetchDescriptor<PersistedPendingScan>())
        let saveRows = try context.fetch(FetchDescriptor<PersistedScannerSave>())
        #expect(scanRows.count == (storeName == "four-entities" ? 0 : 1))
        #expect(saveRows.count == (storeName == "six-entities" ? 1 : 0))
        if let scan = scanRows.first {
            #expect(scan.jpegData == Data([0xff, 0xd8, 0xff]))
            #expect(scan.deviceHintsData == Data("legacy-hints".utf8))
            #expect(scan.enqueuedAt == fixture.timestamp && scan.attemptCount == 2)
        }
        if let save = saveRows.first {
            #expect(save.id == fixture.closetID && save.ownerID == fixture.owner)
            #expect(save.itemData == Data("legacy-item-json".utf8))
            #expect(save.imagesData == Data("legacy-images-json".utf8))
            #expect(save.createdAt == fixture.timestamp)
        }
    }
}
