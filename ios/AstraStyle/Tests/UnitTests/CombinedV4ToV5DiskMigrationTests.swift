import Foundation
import SwiftData
import Testing
@testable import AstraStyle

@Suite("Combined V4 to V5 disk migration")
struct CombinedV4ToV5DiskMigrationTests {
    private struct Fixture {
        let ownerID = UUID()
        let peerID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_760_000_000)
        let closetID = UUID()
        let outfitID = UUID()
        let briefID = UUID()
        let mutationID = UUID()
        let pendingScanID = UUID()
        let scannerSaveID = UUID()
        let candidate = ProductCandidate(
            id: UUID(), canonicalURL: URL(string: "https://shop.example/item") ?? URL(fileURLWithPath: "/"),
            retailer: "Fixture Shop", name: "Fixture coat", category: .outerwear, price: 100, currency: "USD"
        )
        let peerCandidate = ProductCandidate(
            id: UUID(), canonicalURL: URL(string: "https://shop.example/peer") ?? URL(fileURLWithPath: "/"),
            retailer: "Fixture Shop", name: "Peer coat", category: .outerwear, price: 100, currency: "USD"
        )
        let thread = KyraThread(id: UUID(), userID: UUID(), title: "Outfit help")
        let message = KyraMessage(
            id: UUID(), threadID: UUID(), role: .user, content: "What works with my coat?",
            createdAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        let peerThread = KyraThread(id: UUID(), userID: UUID(), title: "Peer thread")
    }

    @Test("V4 rows survive migration and both owner-scoped caches survive reopen")
    func migratesV4AndReopensAllCaches() async throws {
        let fixture = Fixture()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-v4-v5-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("migration.store")
        try seedV4Store(at: storeURL, fixture: fixture)

        let migrated = try AstraModelContainer.live(storeURL: storeURL)
        try await seedCaches(in: migrated, fixture: fixture)
        let reopened = try AstraModelContainer.live(storeURL: storeURL)
        try expectV4Rows(in: reopened, fixture: fixture)
        try await expectReopenedCaches(in: reopened, fixture: fixture)
        try await purgeOwnerCaches(in: reopened, fixture: fixture)
    }

    private func seedCaches(in container: ModelContainer, fixture: Fixture) async throws {
        let kyraCache = SwiftDataKyraHistoryCache(modelContainer: container)
        let shoppingCache = SwiftDataShoppingEvaluationCache(modelContainer: container)
        let thread = KyraThread(
            id: fixture.thread.id, userID: fixture.ownerID, title: fixture.thread.title,
            lastMessageAt: fixture.timestamp
        )
        let message = KyraMessage(
            id: UUID(), threadID: thread.id, role: .user,
            content: fixture.message.content, createdAt: fixture.timestamp
        )
        try await kyraCache.replaceThreads([thread], ownerID: fixture.ownerID)
        try await kyraCache.replaceMessages([message], threadID: thread.id, ownerID: fixture.ownerID)
        let peerThread = KyraThread(
            id: fixture.peerThread.id, userID: fixture.peerID, title: fixture.peerThread.title,
            lastMessageAt: fixture.timestamp
        )
        try await kyraCache.replaceThreads([peerThread], ownerID: fixture.peerID)
        try await shoppingCache.store(
            evaluation: makeEvaluation(ownerID: fixture.ownerID, candidateID: fixture.candidate.id, date: fixture.timestamp),
            candidate: fixture.candidate,
            ownerID: fixture.ownerID
        )
        try await shoppingCache.store(
            evaluation: makeEvaluation(ownerID: fixture.peerID, candidateID: fixture.peerCandidate.id, date: fixture.timestamp),
            candidate: fixture.peerCandidate,
            ownerID: fixture.peerID
        )
    }

    private func expectReopenedCaches(in container: ModelContainer, fixture: Fixture) async throws {
        let kyraCache = SwiftDataKyraHistoryCache(modelContainer: container)
        let shoppingCache = SwiftDataShoppingEvaluationCache(modelContainer: container)
        let thread = try #require(await kyraCache.cachedThreads(ownerID: fixture.ownerID)?.first)
        #expect(thread.id == fixture.thread.id)
        let messages = try #require(await kyraCache.cachedMessages(threadID: thread.id, ownerID: fixture.ownerID))
        #expect(messages.count == 1 && messages[0].content == fixture.message.content)
        #expect(try await kyraCache.cachedThreads(ownerID: UUID()) == nil)
        let decision = try #require(await shoppingCache.cachedDecision(candidateID: fixture.candidate.id, ownerID: fixture.ownerID))
        #expect(decision.evaluation.userID == fixture.ownerID)
        #expect(decision.candidate == fixture.candidate)
        #expect(try await shoppingCache.cachedDecision(candidateID: fixture.candidate.id, ownerID: fixture.peerID) == nil)
        #expect(try await shoppingCache.cachedRecentDecisions(ownerID: fixture.peerID, limit: 10).count == 1)
    }

    private func purgeOwnerCaches(in container: ModelContainer, fixture: Fixture) async throws {
        let kyraCache = SwiftDataKyraHistoryCache(modelContainer: container)
        let shoppingCache = SwiftDataShoppingEvaluationCache(modelContainer: container)
        try await kyraCache.removeAll(ownerID: fixture.ownerID)
        try await shoppingCache.removeAll(ownerID: fixture.ownerID)
        #expect(try await kyraCache.cachedThreads(ownerID: fixture.ownerID) == nil)
        #expect(try await shoppingCache.cachedRecentDecisions(ownerID: fixture.ownerID, limit: 10).isEmpty)
        #expect(try await kyraCache.cachedThreads(ownerID: fixture.peerID)?.first?.id == fixture.peerThread.id)
        #expect(try await shoppingCache.cachedRecentDecisions(ownerID: fixture.peerID, limit: 10).count == 1)
    }

    private func seedV4Store(at storeURL: URL, fixture: Fixture) throws {
        let ownerID = fixture.ownerID
        let timestamp = fixture.timestamp
        let schema = Schema(versionedSchema: AstraSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(PersistedClosetItem(
            id: fixture.closetID, userID: ownerID, name: "V4 coat", brand: "Astra",
            categoryRaw: "outerwear", subcategory: "coat", primaryColor: "navy",
            secondaryColors: [], patternRaw: "solid", material: ["wool"], size: "M",
            fitRaw: "regular", conditionRaw: "good", seasonalityRaw: ["winter"],
            formalityScore: 3, warmthScore: 5, waterResistanceScore: 2,
            purchaseDate: timestamp, pricePaidMinorUnits: 12500, currency: "USD",
            retailer: "Astra", productURLString: "https://example.com/coat", wearCount: 2,
            lastWornAt: timestamp, laundryStateRaw: "clean", availabilityStateRaw: "available",
            archivedAt: nil, primaryImageStoragePath: "users/fixture/coat.jpg",
            createdAt: timestamp, updatedAt: timestamp, pendingSync: true
        ))
        context.insert(PersistedOutfit(
            id: fixture.outfitID, userID: ownerID, name: "V4 outfit", itemDescription: "Coat and boots",
            occasionTags: ["work"], formalityScore: 3, compatibilityScore: 81,
            sourceRaw: "manual", heroImageURLString: nil, isFavorite: true,
            createdAt: timestamp, updatedAt: timestamp, encodedItems: Data("v4-outfit".utf8), pendingSync: true
        ))
        context.insert(PersistedDailyBrief(
            id: fixture.briefID, userID: ownerID, briefDate: timestamp, primaryOutfitID: fixture.outfitID,
            alternativeOutfitIDs: [], kyraMessage: "V4 brief",
            encodedWeatherSnapshot: Data("v4-weather".utf8), encodedScheduleSnapshot: nil, cachedAt: timestamp
        ))
        context.insert(PersistedOfflineMutation(
            id: fixture.mutationID, entityRaw: "closet_item", operationRaw: "update",
            payloadData: Data("v4-mutation".utf8), enqueuedAt: timestamp, attemptCount: 2
        ))
        context.insert(PersistedPendingScan(
            id: fixture.pendingScanID, jpegData: Data([0xff, 0xd8, 0xff]),
            deviceHintsData: Data("v4-hints".utf8), enqueuedAt: timestamp, attemptCount: 1
        ))
        context.insert(PersistedScannerSave(
            id: fixture.scannerSaveID, ownerID: ownerID,
            itemData: Data("v4-item".utf8), imagesData: Data("v4-images".utf8), createdAt: timestamp
        ))
        let profile = PersistedProfileSnapshot(ownerID: ownerID, cachedAt: timestamp)
        profile.profileFetched = true
        profile.profileData = Data("v4-profile".utf8)
        context.insert(profile)
        try context.save()
    }

    private func expectV4Rows(in container: ModelContainer, fixture: Fixture) throws {
        let ownerID = fixture.ownerID
        let timestamp = fixture.timestamp
        let context = ModelContext(container)
        let closet = try #require(context.fetch(FetchDescriptor<PersistedClosetItem>()).first)
        let outfit = try #require(context.fetch(FetchDescriptor<PersistedOutfit>()).first)
        let brief = try #require(context.fetch(FetchDescriptor<PersistedDailyBrief>()).first)
        let mutation = try #require(context.fetch(FetchDescriptor<PersistedOfflineMutation>()).first)
        let scan = try #require(context.fetch(FetchDescriptor<PersistedPendingScan>()).first)
        let save = try #require(context.fetch(FetchDescriptor<PersistedScannerSave>()).first)
        let profile = try #require(context.fetch(FetchDescriptor<PersistedProfileSnapshot>()).first)
        #expect(closet.id == fixture.closetID && closet.userID == ownerID && closet.pendingSync)
        #expect(closet.name == "V4 coat" && closet.primaryImageStoragePath == "users/fixture/coat.jpg")
        #expect(outfit.id == fixture.outfitID && outfit.userID == ownerID && outfit.encodedItems == Data("v4-outfit".utf8))
        #expect(brief.id == fixture.briefID && brief.primaryOutfitID == fixture.outfitID && brief.encodedWeatherSnapshot == Data("v4-weather".utf8))
        #expect(mutation.id == fixture.mutationID && mutation.payloadData == Data("v4-mutation".utf8) && mutation.attemptCount == 2)
        #expect(scan.id == fixture.pendingScanID && scan.jpegData == Data([0xff, 0xd8, 0xff]) && scan.enqueuedAt == timestamp)
        #expect(save.id == fixture.scannerSaveID && save.ownerID == ownerID && save.itemData == Data("v4-item".utf8))
        #expect(profile.ownerID == ownerID && profile.profileFetched && profile.profileData == Data("v4-profile".utf8))
    }

    private func makeEvaluation(ownerID: UUID, candidateID: UUID, date: Date) -> ProductEvaluation {
        ProductEvaluation(
            userID: ownerID, productCandidateID: candidateID, compatibilityScore: 80,
            redundancyScore: 20, outfitsUnlocked: 4, verdict: .consider,
            reasoning: "Fixture decision", createdAt: date
        )
    }
}
