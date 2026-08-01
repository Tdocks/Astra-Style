//
//  PendingScanQueue.swift
//  AstraStyle
//
//  Scanner-specific offline queue. Unlike `OfflineMutationQueue`, this holds
//  the JPEG bytes captured before a closet item exists, so a dropped network
//  connection cannot discard the only copy of the scan.
//

import Foundation

public struct PendingScan: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var jpegData: Data
    public var deviceHints: GarmentDeviceHints?
    public var enqueuedAt: Date
    public var attemptCount: Int

    public init(
        id: UUID = UUID(),
        jpegData: Data,
        deviceHints: GarmentDeviceHints? = nil,
        enqueuedAt: Date = .now,
        attemptCount: Int = 0
    ) {
        self.id = id
        self.jpegData = jpegData
        self.deviceHints = deviceHints
        self.enqueuedAt = enqueuedAt
        self.attemptCount = attemptCount
    }
}

public protocol PendingScanQueue: Sendable {
    func enqueue(_ scan: PendingScan) async
    func pendingScans() async -> [PendingScan]
    func remove(id: UUID) async
    func incrementAttemptCount(id: UUID) async
    func clear() async
}
