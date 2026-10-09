import Foundation
import SwiftData
import Testing
@testable import AstraStyle

@Suite("Kyra history cache disk persistence")
struct KyraHistoryDiskPersistenceTests {
    @Test("confirmed transcript history survives closing and reopening the local store")
    func diskReopen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-kyra-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("kyra.store")
        let ownerID = UUID()
        let thread = KyraThread(id: UUID(), userID: ownerID, title: "Daily outfit")
        let message = KyraMessage(
            id: UUID(), threadID: thread.id, role: .user,
            content: "What should I wear today?", createdAt: Date(timeIntervalSince1970: 1_760_000_000)
        )

        try await write(thread: thread, message: message, ownerID: ownerID, storeURL: storeURL)

        let reopened = try AstraModelContainer.live(storeURL: storeURL)
        let cache = SwiftDataKyraHistoryCache(modelContainer: reopened)
        #expect(try await cache.cachedThreads(ownerID: ownerID)?.first?.id == thread.id)
        #expect(try await cache.cachedMessages(threadID: thread.id, ownerID: ownerID) == [message])
        #expect(try await cache.cachedThreads(ownerID: UUID()) == nil)
    }

    private func write(thread: KyraThread, message: KyraMessage, ownerID: UUID, storeURL: URL) async throws {
        let container = try AstraModelContainer.live(storeURL: storeURL)
        let cache = SwiftDataKyraHistoryCache(modelContainer: container)
        try await cache.replaceThreads([thread], ownerID: ownerID)
        try await cache.replaceMessages([message], threadID: thread.id, ownerID: ownerID)
    }
}
