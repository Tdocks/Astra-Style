import Foundation
import SwiftData
import Testing
@testable import AstraStyle

@MainActor
@Suite("Owner-scoped Monthly Review summary cache")
struct MonthlyReviewSummaryPersistenceTests {
    @Test("A V6 disk store upgrades to V7 and keeps older rows")
    func v6UpgradePreservesClosetAndCareRows() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-monthly-review-v6-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("v6.store")
        let owner = UUID()
        let closetItem = ClosetItem(id: UUID(), userID: owner, name: "Existing coat", category: .outerwear)
        try seedV6(at: url, ownerID: owner, item: closetItem)

        let upgraded = try AstraModelContainer.live(storeURL: url)
        let itemID = closetItem.id
        let itemDescriptor = FetchDescriptor<PersistedClosetItem>(predicate: #Predicate { $0.id == itemID })
        #expect(try upgraded.mainContext.fetch(itemDescriptor).first?.name == "Existing coat")
        let careDescriptor = FetchDescriptor<PersistedClosetCareInstructions>(predicate: #Predicate { $0.itemID == itemID })
        #expect(try upgraded.mainContext.fetch(careDescriptor).first?.instructions == "Brush gently.")

        let cache = SwiftDataMonthlyReviewSummaryCache(modelContainer: upgraded)
        let entry = summary(owner: owner, month: "2026-10", revision: "rev-a", message: "Keep using the navy coat.")
        try await cache.store(entry)
        #expect(try await cache.cached(ownerID: owner, monthKey: "2026-10", dataRevision: "rev-a") == entry)
        let reopened = try AstraModelContainer.live(storeURL: url)
        let reopenedCache = SwiftDataMonthlyReviewSummaryCache(modelContainer: reopened)
        #expect(try await reopenedCache.cached(ownerID: owner, monthKey: "2026-10", dataRevision: "rev-a") == entry)
    }

    @Test("Month and data revision are exact cache keys, and purge is owner-scoped")
    func revisionAndOwnerBoundaries() async throws {
        let cache = SwiftDataMonthlyReviewSummaryCache(modelContainer: AstraModelContainer.preview())
        let owner = UUID()
        let peer = UUID()
        let row = summary(owner: owner, month: "2026-10", revision: "rev-a", message: "Use the overshirt more often.")
        let peerRow = summary(owner: peer, month: "2026-10", revision: "rev-a", message: "Peer-only review.")
        try await cache.store(row)
        try await cache.store(peerRow)

        #expect(try await cache.cached(ownerID: owner, monthKey: "2026-10", dataRevision: "rev-a") == row)
        #expect(try await cache.cached(ownerID: owner, monthKey: "2026-10", dataRevision: "rev-b") == nil)
        #expect(try await cache.cached(ownerID: owner, monthKey: "2026-09", dataRevision: "rev-a") == nil)
        #expect(try await cache.cached(ownerID: peer, monthKey: "2026-10", dataRevision: "rev-a") == peerRow)

        try await cache.removeAll(ownerID: owner)
        #expect(try await cache.cached(ownerID: owner, monthKey: "2026-10", dataRevision: "rev-a") == nil)
        #expect(try await cache.cached(ownerID: peer, monthKey: "2026-10", dataRevision: "rev-a") == peerRow)
    }

    private func seedV6(at url: URL, ownerID: UUID, item: ClosetItem) throws {
        let schema = Schema(versionedSchema: AstraSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        container.mainContext.insert(PersistenceMapping.persistedModel(from: item))
        container.mainContext.insert(PersistedClosetCareInstructions(itemID: item.id, userID: ownerID, instructions: "Brush gently."))
        try container.mainContext.save()
    }

    private func summary(owner: UUID, month: String, revision: String, message: String) -> MonthlyReviewSummary {
        MonthlyReviewSummary(
            ownerID: owner,
            monthKey: month,
            dataRevision: revision,
            message: message,
            threadID: UUID(),
            savedAt: Date(timeIntervalSince1970: 1_791_234_567)
        )
    }
}
