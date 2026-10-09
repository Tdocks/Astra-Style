import Foundation
import SwiftData
import Testing
@testable import AstraStyle

@Suite("Kyra history cache")
struct KyraHistoryCacheTests {
    @Test("thread and message snapshots are scoped to their owner")
    func ownerIsolation() async throws {
        let cache = makeCache()
        let ownerA = UUID()
        let ownerB = UUID()
        let threadA = KyraThread(id: UUID(), userID: ownerA, title: "A", lastMessageAt: .now)
        let threadB = KyraThread(id: UUID(), userID: ownerB, title: "B", lastMessageAt: .now)
        try await cache.replaceThreads([threadA], ownerID: ownerA)
        try await cache.replaceThreads([threadB], ownerID: ownerB)
        try await cache.replaceMessages([message(threadID: threadA.id, text: "private A")], threadID: threadA.id, ownerID: ownerA)

        #expect(try await cache.cachedThreads(ownerID: ownerA)?.map(\.id) == [threadA.id])
        #expect(try await cache.cachedThreads(ownerID: ownerB)?.map(\.id) == [threadB.id])
        #expect(try await cache.cachedMessages(threadID: threadA.id, ownerID: ownerA)?.first?.content == "private A")
        #expect(try await cache.cachedMessages(threadID: threadA.id, ownerID: ownerB) == nil)
    }

    @Test("an empty successful snapshot is different from a cache miss")
    func emptySnapshots() async throws {
        let cache = makeCache()
        let owner = UUID()
        #expect(try await cache.cachedThreads(ownerID: owner) == nil)
        try await cache.replaceThreads([], ownerID: owner)
        #expect(try await cache.cachedThreads(ownerID: owner) == [])
    }

    @Test("refresh removes server-deleted threads and their cached messages")
    func replacementRemovesStaleRows() async throws {
        let cache = makeCache()
        let owner = UUID()
        let stale = KyraThread(id: UUID(), userID: owner)
        let current = KyraThread(id: UUID(), userID: owner)
        try await cache.replaceThreads([stale], ownerID: owner)
        try await cache.replaceMessages([message(threadID: stale.id, text: "old")], threadID: stale.id, ownerID: owner)
        try await cache.replaceThreads([current], ownerID: owner)

        #expect(try await cache.cachedThreads(ownerID: owner)?.map(\.id) == [current.id])
        #expect(try await cache.cachedMessages(threadID: stale.id, ownerID: owner) == nil)
    }

    @Test("account purge removes only that owner's local history")
    func purgeIsOwnerScoped() async throws {
        let cache = makeCache()
        let ownerA = UUID()
        let ownerB = UUID()
        let threadA = KyraThread(id: UUID(), userID: ownerA)
        let threadB = KyraThread(id: UUID(), userID: ownerB)
        try await cache.replaceThreads([threadA], ownerID: ownerA)
        try await cache.replaceThreads([threadB], ownerID: ownerB)
        try await cache.replaceMessages([message(threadID: threadA.id, text: "A")], threadID: threadA.id, ownerID: ownerA)
        try await cache.replaceMessages([message(threadID: threadB.id, text: "B")], threadID: threadB.id, ownerID: ownerB)

        try await cache.removeAll(ownerID: ownerA)
        #expect(try await cache.cachedThreads(ownerID: ownerA) == nil)
        #expect(try await cache.cachedMessages(threadID: threadA.id, ownerID: ownerA) == nil)
        #expect(try await cache.cachedThreads(ownerID: ownerB)?.map(\.id) == [threadB.id])
        #expect(try await cache.cachedMessages(threadID: threadB.id, ownerID: ownerB)?.first?.content == "B")
    }

    @Test("cached structured data omits private signed image URLs but preserves product links")
    func privateURLsAreNotPersisted() async throws {
        let container = AstraModelContainer.preview()
        let cache = SwiftDataKyraHistoryCache(modelContainer: container)
        let owner = UUID()
        let thread = UUID()
        try await cache.replaceThreads([KyraThread(id: thread, userID: owner)], ownerID: owner)
        let privateURL = "https://project.supabase.co/storage/v1/object/sign/user-content/users/\(owner)/closet/item/photo.jpg?token=secret"
        let message = KyraMessage(
            id: UUID(),
            threadID: thread,
            role: .assistant,
            content: "Photo: \(privateURL) — product link https://shop.example/item",
            structuredPayload: KyraStructuredResponse(
                message: "Comparison \(privateURL)",
                intent: .general,
                cards: [.comparisonTable(ComparisonTable(
                    title: "Look",
                    columnHeaders: ["Item"],
                    rows: [[privateURL]]
                ))],
                confidence: 0.9
            ),
            modelMetadata: .object([
                "model_identifier": .string("gpt-5.6-terra"),
                "signed_image_url": .string(privateURL)
            ])
        )
        try await cache.replaceMessages([message], threadID: thread, ownerID: owner)

        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<PersistedKyraMessage>())
        #expect(rows.count == 1)
        let storedObject = try JSONSerialization.jsonObject(with: rows[0].encodedMessage)
        let normalizedJSON = try JSONSerialization.data(withJSONObject: storedObject, options: [.withoutEscapingSlashes])
        let stored = String(data: normalizedJSON, encoding: .utf8) ?? ""
        #expect(!stored.contains("/storage/v1/object/sign/"))
        #expect(!stored.contains("token=secret"))
        #expect(!stored.contains("storage%2fv1%2fobject%2fsign"))
        #expect(stored.contains("https://shop.example/item"))
        let cached = try #require(await cache.cachedMessages(threadID: thread, ownerID: owner)?.first)
        #expect(!cached.content.contains("/storage/v1/object/sign/"))
        #expect(cached.content.contains("https://shop.example/item"))
    }

    @Test("only connectivity failures allow cache fallback")
    func fallbackClassification() {
        #expect(LiveKyraRepository.shouldFallbackToHistoryCache(for: URLError(.notConnectedToInternet)))
        #expect(!LiveKyraRepository.shouldFallbackToHistoryCache(for: URLError(.cancelled)))
        #expect(!LiveKyraRepository.shouldFallbackToHistoryCache(for: AstraError.auth("expired")))
        #expect(!LiveKyraRepository.shouldFallbackToHistoryCache(for: AstraError.server("server error")))
    }

    @Test("a cached thread read fails if the active account changed while it was loading")
    func changedOwnerInvalidatesRead() {
        do {
            try LiveKyraRepository.validateActiveOwner(expected: UUID(), actual: UUID())
            Issue.record("expected an account-change error")
        } catch let error as AstraError {
            #expect(error.category == .auth)
        } catch {
            Issue.record("expected an authentication error")
        }
    }

    private func makeCache() -> SwiftDataKyraHistoryCache {
        SwiftDataKyraHistoryCache(modelContainer: AstraModelContainer.preview())
    }

    private func message(threadID: UUID, text: String) -> KyraMessage {
        KyraMessage(id: UUID(), threadID: threadID, role: .user, content: text)
    }
}
