import Foundation
import OSLog

/// A write-ahead record for a scanner save whose database outcome may be
/// unknown after process termination. Photo bytes remain in Storage or in
/// the existing owner-scoped guest file; only stable metadata is journaled.
public struct PendingScannerSave: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let ownerID: UUID
    public var item: ClosetItem
    public var images: [ClosetItemImage]
    public let createdAt: Date

    public init(id: UUID? = nil, ownerID: UUID, item: ClosetItem, images: [ClosetItemImage], createdAt: Date = .now) {
        self.id = id ?? item.id
        self.ownerID = ownerID
        self.item = item
        self.images = images
        self.createdAt = createdAt
    }
}

public protocol ScannerSaveJournaling: Sendable {
    func beginForegroundSave(id: UUID, ownerID: UUID) async -> Bool
    func endForegroundSave(id: UUID, ownerID: UUID) async
    func beginRecoverySave(id: UUID, ownerID: UUID) async -> Bool
    func endRecoverySave(id: UUID, ownerID: UUID) async
    func save(_ record: PendingScannerSave) async throws
    func pendingSaves(for ownerID: UUID) async throws -> [PendingScannerSave]
    func remove(id: UUID, ownerID: UUID) async throws
}

/// Direct remote operations used to distinguish a committed write from a
/// cached row while reconciling an ambiguous scanner save.
public protocol ScannerSaveRemoteWriting: Sendable {
    func remoteScannerItem(id: UUID) async throws -> ClosetItem?
    func ensureScannerImages(_ images: [ClosetItemImage]) async throws
}

/// Reconciles only the active owner's journal. An absent remote row is
/// retried through the wrapped ClosetRepository so free-tier caps still run.
public actor ScannerSaveRecoveryService {
    private static let logger = Logger(subsystem: "com.astrastyle.app", category: "scannerSaveRecovery")
    private let journal: ScannerSaveJournaling
    private let repository: ClosetRepository
    private let remote: ScannerSaveRemoteWriting
    private let currentUserID: @Sendable () async -> UUID?
    private let hasDurableQueuedCreate: @Sendable (UUID, UUID) async -> Bool
    private var isRecovering = false
    private var activeOwnerID: UUID?
    private var queuedOwners: Set<UUID> = []

    public init(
        journal: ScannerSaveJournaling,
        repository: ClosetRepository,
        remote: ScannerSaveRemoteWriting,
        currentUserID: @escaping @Sendable () async -> UUID?,
        hasDurableQueuedCreate: @escaping @Sendable (UUID, UUID) async -> Bool = { _, _ in false }
    ) {
        self.journal = journal
        self.repository = repository
        self.remote = remote
        self.currentUserID = currentUserID
        self.hasDurableQueuedCreate = hasDurableQueuedCreate
    }

    public func recover(ownerID: UUID) async {
        if isRecovering {
            if activeOwnerID != ownerID { queuedOwners.insert(ownerID) }
            return
        }
        isRecovering = true
        var nextOwner: UUID? = ownerID
        while let currentOwner = nextOwner {
            activeOwnerID = currentOwner
            await recoverOwner(currentOwner)
            nextOwner = queuedOwners.sorted { $0.uuidString < $1.uuidString }.first
            if let nextOwner { queuedOwners.remove(nextOwner) }
        }
        activeOwnerID = nil
        isRecovering = false
    }

    private func recoverOwner(_ ownerID: UUID) async {
        guard await currentUserID() == ownerID else { return }
        let records: [PendingScannerSave]
        do {
            records = try await journal.pendingSaves(for: ownerID)
        } catch {
            Self.logger.error("Could not read pending scanner save records.")
            return
        }
        await reconcile(records, ownerID: ownerID)
    }

    private func reconcile(_ records: [PendingScannerSave], ownerID: UUID) async {
        for record in records {
            guard await currentUserID() == ownerID else { return }
            await reconcile(record, ownerID: ownerID)
        }
    }

    private func reconcile(_ record: PendingScannerSave, ownerID: UUID) async {
        guard await journal.beginRecoverySave(id: record.id, ownerID: ownerID) else { return }
        await reconcileClaimedRecord(record, ownerID: ownerID)
        await journal.endRecoverySave(id: record.id, ownerID: ownerID)
    }

    private func reconcileClaimedRecord(_ record: PendingScannerSave, ownerID: UUID) async {
        guard isValid(record, ownerID: ownerID) else {
            Self.logger.error("A pending scanner save failed owner or photo validation.")
            return
        }
        if await hasDurableQueuedCreate(ownerID, record.item.id) {
            guard await currentUserID() == ownerID else { return }
            try? await journal.remove(id: record.id, ownerID: ownerID)
            return
        }
        do {
            try await reconcileRemote(record, ownerID: ownerID)
            guard await currentUserID() == ownerID else { return }
            try await journal.remove(id: record.id, ownerID: ownerID)
        } catch {
            // Retain uncertain reads, writes, and image upserts for retry.
        }
    }

    private func isValid(_ record: PendingScannerSave, ownerID: UUID) -> Bool {
        guard record.id == record.item.id, record.ownerID == ownerID, record.item.userID == ownerID,
              Self.hasValidImageIdentity(record.images, itemID: record.item.id) else { return false }
        return (try? validatePhotoOwnership(record)) != nil
    }

    static func hasValidImageIdentity(_ images: [ClosetItemImage], itemID: UUID) -> Bool {
        !images.isEmpty && Set(images.map(\.id)).count == images.count &&
            images.allSatisfy { $0.closetItemID == itemID } &&
            images.filter(\.isPrimary).count == 1 && images.contains { $0.imageType == .front }
    }

    private func reconcileRemote(_ record: PendingScannerSave, ownerID: UUID) async throws {
        if let remoteItem = try await remote.remoteScannerItem(id: record.item.id) {
            guard remoteItem.userID == ownerID, await currentUserID() == ownerID else {
                throw AstraError.auth("The pending scan belongs to another account or the active account changed.")
            }
            try await remote.ensureScannerImages(record.images)
        } else {
            guard await currentUserID() == ownerID else {
                throw AstraError.auth("The active account changed while recovering a saved scan.")
            }
            _ = try await repository.createItem(record.item, images: record.images)
        }
    }

    private func validatePhotoOwnership(_ record: PendingScannerSave) throws {
        let remotePrefix = "users/\(record.ownerID.uuidString.lowercased())/closet/"
        for path in record.images.flatMap({ [$0.storagePath, $0.backgroundRemovedPath].compactMap { $0 } }) {
            if GuestLocalImageStore.isLocal(path) {
                let expectedPrefix = GuestLocalImageStore.pathPrefix + record.ownerID.uuidString.lowercased() + "/"
                guard path.hasPrefix(expectedPrefix),
                      let url = GuestLocalImageStore.fileURL(for: path),
                      FileManager.default.fileExists(atPath: url.path) else {
                    throw AstraError.auth("A saved scan photo is unavailable for this account.")
                }
            } else if !path.hasPrefix(remotePrefix) || !ClosetImageByteCache.isOwnedClosetImagePath(path, ownerID: record.ownerID) {
                throw AstraError.auth("A saved scan photo belongs to a different account.")
            }
        }
    }
}

public actor InMemoryScannerSaveJournal: ScannerSaveJournaling {
    private var records: [UUID: PendingScannerSave] = [:]
    private var foregroundSaves: Set<String> = []
    private var recoverySaves: Set<String> = []

    public init() {}

    public func beginForegroundSave(id: UUID, ownerID: UUID) async -> Bool {
        let key = key(id: id, ownerID: ownerID)
        guard !foregroundSaves.contains(key), !recoverySaves.contains(key) else { return false }
        foregroundSaves.insert(key)
        return true
    }

    public func endForegroundSave(id: UUID, ownerID: UUID) async {
        foregroundSaves.remove(key(id: id, ownerID: ownerID))
    }

    public func beginRecoverySave(id: UUID, ownerID: UUID) async -> Bool {
        let key = key(id: id, ownerID: ownerID)
        guard !foregroundSaves.contains(key), !recoverySaves.contains(key) else { return false }
        recoverySaves.insert(key)
        return true
    }

    public func endRecoverySave(id: UUID, ownerID: UUID) async {
        recoverySaves.remove(key(id: id, ownerID: ownerID))
    }

    private func key(id: UUID, ownerID: UUID) -> String { "\(ownerID.uuidString):\(id.uuidString)" }

    public func save(_ record: PendingScannerSave) async throws {
        records[record.id] = record
    }

    public func pendingSaves(for ownerID: UUID) async throws -> [PendingScannerSave] {
        records.values.filter { $0.ownerID == ownerID }.sorted { $0.createdAt < $1.createdAt }
    }

    public func remove(id: UUID, ownerID: UUID) async throws {
        guard records[id]?.ownerID == ownerID else { return }
        records.removeValue(forKey: id)
    }
}
