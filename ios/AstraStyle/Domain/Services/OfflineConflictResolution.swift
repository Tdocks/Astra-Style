//
//  OfflineConflictResolution.swift
//  AstraStyle
//
//  ADR 0005 conflict policy for draining the offline mutation queue
//  (ticket P3-INFRA-01):
//
//  * Field edits (`.update`): last-write-wins by `updated_at`. When remote
//    is newer the local mutation is discarded — but never silently; the
//    drain path must record a resolvable conflict state / log entry.
//  * Destructive ops (`.delete` / archive): never auto-applied over a
//    newer remote write. Surface a conflict for the user to resolve
//    rather than letting a stale pull erase "I archived this."
//  * `.create` has no remote conflict of this shape. If a row already
//    exists for the create id, the drain path prefers `update` (see
//    `LiveClosetRepository+Offline`).
//

import Foundation
import OSLog

/// Pure last-write-wins / destructive-conflict decisions for closet offline
/// replay. Side-effect free so unit tests can pin the rule without a network.
public enum OfflineConflictResolution {

    public enum Decision: Sendable, Equatable {
        /// Replay the local mutation against the backend.
        case apply
        /// Drop the local mutation; remote already won. Callers must still
        /// record resolvable state so the discard is not silent.
        case discardLocal(reason: String)
        /// Do not apply. Record a conflict the user (or a later pass) must
        /// resolve — used for destructive ops when remote is newer.
        case surfaceConflict(reason: String)
    }

    /// Compares `local.updatedAt` to `remote?.updatedAt` under ADR 0005.
    ///
    /// Ties (`local == remote`) favour apply: the queued write is the
    /// device's intent and remote is not strictly newer.
    public static func resolve(
        local: ClosetItem,
        remote: ClosetItem?,
        operation: OfflineMutation.Operation
    ) -> Decision {
        switch operation {
        case .create:
            return .apply
        case .update:
            return resolveUpdate(local: local, remote: remote)
        case .delete:
            return resolveDelete(local: local, remote: remote)
        }
    }

    private static func resolveUpdate(local: ClosetItem, remote: ClosetItem?) -> Decision {
        guard let remote else {
            return .surfaceConflict(
                reason: "Remote closet item is missing; local update was not applied over a deleted row."
            )
        }
        if local.updatedAt >= remote.updatedAt {
            return .apply
        }
        return .discardLocal(
            reason: "Remote closet item is newer (updated_at); local field edit lost last-write-wins."
        )
    }

    private static func resolveDelete(local: ClosetItem, remote: ClosetItem?) -> Decision {
        guard let remote else {
            return .discardLocal(
                reason: "Remote closet item is already absent; local archive is a no-op."
            )
        }
        if local.updatedAt >= remote.updatedAt {
            return .apply
        }
        return .surfaceConflict(
            reason: "Remote closet item is newer (updated_at); local archive/delete was not auto-applied."
        )
    }
}

/// A recorded offline sync conflict — the resolvable log/state required when
/// a local mutation is discarded or blocked rather than applied.
public struct OfflineSyncConflict: Identifiable, Sendable, Equatable, Hashable {
    public enum Disposition: String, Sendable, Equatable, Hashable {
        /// Local field edit lost to a newer remote write (LWW).
        case discardedLocal
        /// Destructive local op blocked because remote is newer.
        case needsResolution
    }

    public let id: UUID
    public let mutationID: UUID
    public let itemID: UUID
    public let operation: OfflineMutation.Operation
    public let disposition: Disposition
    public let reason: String
    public let localUpdatedAt: Date
    public let remoteUpdatedAt: Date?
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        mutationID: UUID,
        itemID: UUID,
        operation: OfflineMutation.Operation,
        disposition: Disposition,
        reason: String,
        localUpdatedAt: Date,
        remoteUpdatedAt: Date?,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.mutationID = mutationID
        self.itemID = itemID
        self.operation = operation
        self.disposition = disposition
        self.reason = reason
        self.localUpdatedAt = localUpdatedAt
        self.remoteUpdatedAt = remoteUpdatedAt
        self.recordedAt = recordedAt
    }
}

/// Typed error wrapping a surfaced destructive conflict. Available to callers
/// inspecting recorded conflicts; drain removes the mutation after recording
/// rather than failing the whole backlog on it.
public struct OfflineSyncConflictError: Error, Sendable, Equatable {
    public let conflict: OfflineSyncConflict

    public init(conflict: OfflineSyncConflict) {
        self.conflict = conflict
    }
}

/// Stores conflicts produced while draining so discards are never silent.
public protocol OfflineConflictRecording: Sendable {
    func record(_ conflict: OfflineSyncConflict) async
    func recordedConflicts() async -> [OfflineSyncConflict]
}

public actor InMemoryOfflineConflictRecorder: OfflineConflictRecording {
    private var conflicts: [OfflineSyncConflict] = []

    public init() {}

    public func record(_ conflict: OfflineSyncConflict) async {
        conflicts.append(conflict)
    }

    public func recordedConflicts() async -> [OfflineSyncConflict] {
        conflicts
    }
}

enum OfflineConflictLog {
    static let logger = Logger(subsystem: "com.astrastyle.app", category: "offlineSync")

    static func log(_ conflict: OfflineSyncConflict) {
        logger.warning("""
            Offline sync conflict item=\(conflict.itemID.uuidString, privacy: .public) \
            op=\(conflict.operation.rawValue, privacy: .public) \
            disposition=\(conflict.disposition.rawValue, privacy: .public) \
            reason=\(conflict.reason, privacy: .public)
            """)
    }
}
