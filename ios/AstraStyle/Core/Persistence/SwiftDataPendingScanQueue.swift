//
//  SwiftDataPendingScanQueue.swift
//  AstraStyle
//
//  Durable scanner queue for JPEGs captured while offline.
//

import Foundation
import SwiftData

@Model
public final class PersistedPendingScan {
    @Attribute(.unique) public var id: UUID
    public var jpegData: Data
    public var deviceHintsData: Data?
    public var enqueuedAt: Date
    public var attemptCount: Int

    public init(
        id: UUID,
        jpegData: Data,
        deviceHintsData: Data?,
        enqueuedAt: Date,
        attemptCount: Int
    ) {
        self.id = id
        self.jpegData = jpegData
        self.deviceHintsData = deviceHintsData
        self.enqueuedAt = enqueuedAt
        self.attemptCount = attemptCount
    }
}

extension PendingScan {
    fileprivate init?(persisted: PersistedPendingScan) {
        let hints = persisted.deviceHintsData.flatMap { data in
            try? JSONDecoder.astraDefault.decode(GarmentDeviceHints.self, from: data)
        }
        self.init(
            id: persisted.id,
            jpegData: persisted.jpegData,
            deviceHints: hints,
            enqueuedAt: persisted.enqueuedAt,
            attemptCount: persisted.attemptCount
        )
    }
}

@ModelActor
public actor SwiftDataPendingScanQueue: PendingScanQueue {
    public func enqueue(_ scan: PendingScan) async {
        let scanID = scan.id
        let descriptor = FetchDescriptor<PersistedPendingScan>(predicate: #Predicate { $0.id == scanID })
        let encodedHints = encodeDeviceHints(scan.deviceHints)
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.jpegData = scan.jpegData
            existing.deviceHintsData = encodedHints
            existing.enqueuedAt = scan.enqueuedAt
            existing.attemptCount = scan.attemptCount
        } else {
            modelContext.insert(
                PersistedPendingScan(
                    id: scan.id,
                    jpegData: scan.jpegData,
                    deviceHintsData: encodedHints,
                    enqueuedAt: scan.enqueuedAt,
                    attemptCount: scan.attemptCount
                )
            )
        }
        try? modelContext.save()
    }

    public func pendingScans() async -> [PendingScan] {
        let descriptor = FetchDescriptor<PersistedPendingScan>(
            sortBy: [SortDescriptor(\.enqueuedAt, order: .forward)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.compactMap(PendingScan.init(persisted:))
    }

    public func remove(id: UUID) async {
        let descriptor = FetchDescriptor<PersistedPendingScan>(predicate: #Predicate { $0.id == id })
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(row)
        try? modelContext.save()
    }

    public func incrementAttemptCount(id: UUID) async {
        let descriptor = FetchDescriptor<PersistedPendingScan>(predicate: #Predicate { $0.id == id })
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        row.attemptCount += 1
        try? modelContext.save()
    }

    public func clear() async {
        let descriptor = FetchDescriptor<PersistedPendingScan>()
        guard let rows = try? modelContext.fetch(descriptor) else { return }
        for row in rows {
            modelContext.delete(row)
        }
        try? modelContext.save()
    }

    private func encodeDeviceHints(_ hints: GarmentDeviceHints?) -> Data? {
        guard let hints else { return nil }
        return try? JSONEncoder.astraDefault.encode(hints)
    }
}
