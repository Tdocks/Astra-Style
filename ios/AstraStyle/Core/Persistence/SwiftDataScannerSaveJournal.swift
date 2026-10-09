import Foundation
import SwiftData

@Model
public final class PersistedScannerSave {
    @Attribute(.unique) public var id: UUID
    public var ownerID: UUID
    public var itemData: Data
    public var imagesData: Data
    public var createdAt: Date

    public init(id: UUID, ownerID: UUID, itemData: Data, imagesData: Data, createdAt: Date) {
        self.id = id
        self.ownerID = ownerID
        self.itemData = itemData
        self.imagesData = imagesData
        self.createdAt = createdAt
    }
}

@ModelActor
public actor SwiftDataScannerSaveJournal: ScannerSaveJournaling {
    private var foregroundSaves: Set<String> = []
    private var recoverySaves: Set<String> = []

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
        guard record.id == record.item.id, record.ownerID == record.item.userID,
              ScannerSaveRecoveryService.hasValidImageIdentity(record.images, itemID: record.item.id) else {
            throw AstraError.validation("Scanner recovery record has mismatched ownership.")
        }
        let itemData = try Self.makeEncoder().encode(record.item)
        let imagesData = try Self.makeEncoder().encode(record.images)
        let recordID = record.id
        let descriptor = FetchDescriptor<PersistedScannerSave>(predicate: #Predicate { $0.id == recordID })
        let existing = try modelContext.fetch(descriptor).first
        if let existing {
            guard existing.ownerID == record.ownerID else {
                throw AstraError.auth("This scanner recovery record belongs to another account.")
            }
            let oldItem = existing.itemData
            let oldImages = existing.imagesData
            existing.itemData = itemData
            existing.imagesData = imagesData
            do {
                try modelContext.save()
            } catch {
                existing.itemData = oldItem
                existing.imagesData = oldImages
                throw error
            }
        } else {
            let row = PersistedScannerSave(
                id: record.id,
                ownerID: record.ownerID,
                itemData: itemData,
                imagesData: imagesData,
                createdAt: record.createdAt
            )
            modelContext.insert(row)
            do {
                try modelContext.save()
            } catch {
                modelContext.delete(row)
                throw error
            }
        }
    }

    public func pendingSaves(for ownerID: UUID) async throws -> [PendingScannerSave] {
        let descriptor = FetchDescriptor<PersistedScannerSave>(
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let rows = try modelContext.fetch(descriptor)
        var records: [PendingScannerSave] = []
        for row in rows {
            guard let item = try? Self.makeDecoder().decode(ClosetItem.self, from: row.itemData),
                  let images = try? Self.makeDecoder().decode([ClosetItemImage].self, from: row.imagesData),
                  row.id == item.id, row.ownerID == item.userID,
                  ScannerSaveRecoveryService.hasValidImageIdentity(images, itemID: item.id) else {
                throw AstraError.server("A saved scan recovery record couldn't be read. It has been kept for support.")
            }
            records.append(PendingScannerSave(id: row.id, ownerID: row.ownerID, item: item, images: images, createdAt: row.createdAt))
        }
        return records
    }

    public func remove(id: UUID, ownerID: UUID) async throws {
        let descriptor = FetchDescriptor<PersistedScannerSave>(
            predicate: #Predicate { $0.id == id && $0.ownerID == ownerID }
        )
        guard let row = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(row)
        do {
            try modelContext.save()
        } catch {
            modelContext.insert(row)
            throw error
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let seconds = ISO8601DateFormatter()
            seconds.formatOptions = [.withInternetDateTime]
            guard let date = seconds.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid saved scanner date.")
            }
            return date
        }
        return decoder
    }
}
