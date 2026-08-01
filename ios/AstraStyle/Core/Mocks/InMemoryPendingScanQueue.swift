//
//  InMemoryPendingScanQueue.swift
//  AstraStyle
//
//  In-memory pending scan queue for previews and unit tests.
//

import Foundation

public actor InMemoryPendingScanQueue: PendingScanQueue {
    private var scans: [PendingScan]

    public init(seed: [PendingScan] = []) {
        scans = seed.sorted { $0.enqueuedAt < $1.enqueuedAt }
    }

    public func enqueue(_ scan: PendingScan) async {
        scans.removeAll { $0.id == scan.id }
        scans.append(scan)
        scans.sort { $0.enqueuedAt < $1.enqueuedAt }
    }

    public func pendingScans() async -> [PendingScan] {
        scans
    }

    public func remove(id: UUID) async {
        scans.removeAll { $0.id == id }
    }

    public func incrementAttemptCount(id: UUID) async {
        guard let index = scans.firstIndex(where: { $0.id == id }) else { return }
        scans[index].attemptCount += 1
    }

    public func clear() async {
        scans.removeAll()
    }
}
