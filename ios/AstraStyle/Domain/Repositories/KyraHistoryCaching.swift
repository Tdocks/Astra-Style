import Foundation

/// Persistent offline read cache for server-confirmed Kyra history. There is
/// intentionally no send/outbox method: generative turns are never replayed
/// in the background, so returning online cannot duplicate a paid request.
public protocol KyraHistoryCaching: Sendable {
    func cachedThreads(ownerID: UUID) async throws -> [KyraThread]?
    func replaceThreads(_ threads: [KyraThread], ownerID: UUID) async throws
    func cachedMessages(threadID: UUID, ownerID: UUID) async throws -> [KyraMessage]?
    func replaceMessages(_ messages: [KyraMessage], threadID: UUID, ownerID: UUID) async throws
    func removeAll(ownerID: UUID) async throws
}

public protocol KyraHistoryCachePurging: Sendable {
    func purgeCachedKyraHistory(ownerID: UUID) async throws
}
