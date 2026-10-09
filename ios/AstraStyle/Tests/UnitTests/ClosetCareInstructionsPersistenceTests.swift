import Foundation
import SwiftData
import Testing
@testable import AstraStyle

@Suite("Durable user-entered closet care instructions")
@MainActor
struct ClosetCareInstructionsPersistenceTests {
    @Test("Opening a real V5 store with the current schema preserves existing closet and profile rows")
    func v5StoreUpgradesWithoutLosingExistingRows() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-closet-care-v5-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("v5.store")
        let ownerID = UUID()
        let item = ClosetItem(id: UUID(), userID: ownerID, name: "Existing jacket", category: .outerwear)

        let profileData = Data("{\"id\":\"\(ownerID.uuidString.lowercased())\"}".utf8)
        try createV5Store(at: storeURL, ownerID: ownerID, item: item, profileData: profileData)

        let upgraded = try AstraModelContainer.live(storeURL: storeURL)
        let itemID = item.id
        let itemDescriptor = FetchDescriptor<PersistedClosetItem>(predicate: #Predicate { $0.id == itemID })
        let profileDescriptor = FetchDescriptor<PersistedProfileSnapshot>(predicate: #Predicate { $0.ownerID == ownerID })
        #expect(try upgraded.mainContext.fetch(itemDescriptor).first?.name == "Existing jacket")
        #expect(try upgraded.mainContext.fetch(profileDescriptor).first?.profileData == profileData)

        let cache = SwiftDataClosetItemCache(modelContainer: upgraded)
        var edited = item
        edited.careInstructions = "Use a soft brush."
        await cache.upsert(edited)
        #expect(await cache.items(for: ownerID).first?.careInstructions == "Use a soft brush.")
    }

    private func createV5Store(at url: URL, ownerID: UUID, item: ClosetItem, profileData: Data) throws {
        let oldSchema = Schema(versionedSchema: AstraSchemaV5.self)
        let oldConfiguration = ModelConfiguration(schema: oldSchema, url: url)
        let oldContainer = try ModelContainer(for: oldSchema, configurations: [oldConfiguration])
        oldContainer.mainContext.insert(PersistenceMapping.persistedModel(from: item))
        let profileSnapshot = PersistedProfileSnapshot(ownerID: ownerID)
        profileSnapshot.profileFetched = true
        profileSnapshot.profileData = profileData
        oldContainer.mainContext.insert(profileSnapshot)
        try oldContainer.mainContext.save()
    }

    @Test("Care notes round-trip through the current disk cache and stay owner-scoped")
    func careInstructionsSurviveReopenAndRemainOwnerScoped() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-closet-care-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("closet.store")
        let ownerID = UUID()
        let otherOwnerID = UUID()
        var item = ClosetItem(id: UUID(), userID: ownerID, name: "Linen shirt", category: .top, material: ["Linen"])
        item.careInstructions = "Cold hand wash; dry flat."

        let firstContainer = try AstraModelContainer.live(storeURL: storeURL)
        let firstCache = SwiftDataClosetItemCache(modelContainer: firstContainer)
        await firstCache.upsert(item)

        let reopened = try AstraModelContainer.live(storeURL: storeURL)
        let reopenedCache = SwiftDataClosetItemCache(modelContainer: reopened)
        #expect(await reopenedCache.items(for: ownerID).first?.careInstructions == item.careInstructions)
        #expect(await reopenedCache.items(for: otherOwnerID).isEmpty)
    }

    @Test("Clearing care notes removes the sidecar value without losing the closet row")
    func clearingCareInstructionsRetainsItem() async throws {
        let container = AstraModelContainer.preview()
        let cache = SwiftDataClosetItemCache(modelContainer: container)
        let ownerID = UUID()
        let itemID = UUID()
        var item = ClosetItem(id: itemID, userID: ownerID, name: "Wool coat", category: .outerwear)
        item.careInstructions = "Dry clean only."
        await cache.upsert(item)
        item.careInstructions = nil
        await cache.upsert(item)

        let cached = await cache.items(for: ownerID)
        #expect(cached.count == 1)
        #expect(cached.first?.id == itemID)
        #expect(cached.first?.careInstructions == nil)
    }

    @Test("Account deletion purges only that owner's item and care sidecar rows")
    func ownerScopedPurgeRemovesCareNotes() async throws {
        let cache = SwiftDataClosetItemCache(modelContainer: AstraModelContainer.preview())
        let ownerID = UUID()
        let peerID = UUID()
        var owned = ClosetItem(id: UUID(), userID: ownerID, name: "Owner shirt", category: .top)
        owned.careInstructions = "Hand wash."
        let peer = ClosetItem(id: UUID(), userID: peerID, name: "Peer shirt", category: .top)
        await cache.upsert(owned)
        await cache.upsert(peer)

        try await cache.removeAll(for: ownerID)

        #expect(await cache.items(for: ownerID).isEmpty)
        #expect(await cache.items(for: peerID).map(\.id) == [peer.id])
    }
}
