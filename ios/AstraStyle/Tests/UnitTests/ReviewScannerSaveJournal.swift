import Foundation
@testable import AstraStyle

actor ReviewScannerSaveJournal: ScannerSaveJournaling {
    private var records: [UUID: PendingScannerSave] = [:]
    private var foregroundSaves: Set<String> = []
    private var recoverySaves: Set<String> = []
    private let saveFails: Bool
    private let removeFails: Bool

    init(saveFails: Bool = false, removeFails: Bool = false) {
        self.saveFails = saveFails
        self.removeFails = removeFails
    }

    var pendingCount: Int { records.count }

    func beginForegroundSave(id: UUID, ownerID: UUID) async -> Bool {
        let lockKey = key(id: id, ownerID: ownerID)
        guard !foregroundSaves.contains(lockKey), !recoverySaves.contains(lockKey) else { return false }
        foregroundSaves.insert(lockKey)
        return true
    }

    func endForegroundSave(id: UUID, ownerID: UUID) async {
        foregroundSaves.remove(key(id: id, ownerID: ownerID))
    }

    func beginRecoverySave(id: UUID, ownerID: UUID) async -> Bool {
        let lockKey = key(id: id, ownerID: ownerID)
        guard !foregroundSaves.contains(lockKey), !recoverySaves.contains(lockKey) else { return false }
        recoverySaves.insert(lockKey)
        return true
    }

    func endRecoverySave(id: UUID, ownerID: UUID) async {
        recoverySaves.remove(key(id: id, ownerID: ownerID))
    }

    func save(_ record: PendingScannerSave) async throws {
        if saveFails { throw AstraError.server("injected journal write failure") }
        records[record.id] = record
    }

    func pendingSaves(for ownerID: UUID) async throws -> [PendingScannerSave] {
        records.values.filter { $0.ownerID == ownerID }
    }

    func remove(id: UUID, ownerID: UUID) async throws {
        if removeFails { throw AstraError.server("injected journal removal failure") }
        guard records[id]?.ownerID == ownerID else { return }
        records.removeValue(forKey: id)
    }

    private func key(id: UUID, ownerID: UUID) -> String { "\(ownerID.uuidString):\(id.uuidString)" }
}
