//
//  SwiftDataOfflineMutationQueue.swift
//  AstraStyle
//
//  Production `OfflineMutationQueue` conformance (spec §7 "Local edits
//  queue for sync"). Implemented as a `@ModelActor` so every access to the
//  underlying `ModelContext` is serialized on its own executor —
//  `ModelContext` itself is not `Sendable`, so this is the supported
//  SwiftData pattern for touching persistence from arbitrary
//  `async`/concurrent call sites (e.g. a repository's catch block running
//  on whatever task happened to make the failed network call).
//

import Foundation
import SwiftData

@Model
public final class PersistedOfflineMutation {
    @Attribute(.unique) public var id: UUID
    public var entityRaw: String
    public var operationRaw: String
    public var payloadData: Data
    public var enqueuedAt: Date
    public var attemptCount: Int

    public init(id: UUID, entityRaw: String, operationRaw: String, payloadData: Data, enqueuedAt: Date, attemptCount: Int) {
        self.id = id
        self.entityRaw = entityRaw
        self.operationRaw = operationRaw
        self.payloadData = payloadData
        self.enqueuedAt = enqueuedAt
        self.attemptCount = attemptCount
    }
}

extension OfflineMutation {
    fileprivate init?(persisted: PersistedOfflineMutation) {
        guard
            let entity = Entity(rawValue: persisted.entityRaw),
            let operation = Operation(rawValue: persisted.operationRaw)
        else {
            return nil
        }
        self.init(
            id: persisted.id,
            entity: entity,
            operation: operation,
            payloadData: persisted.payloadData,
            enqueuedAt: persisted.enqueuedAt,
            attemptCount: persisted.attemptCount
        )
    }
}

@ModelActor
public actor SwiftDataOfflineMutationQueue: OfflineMutationQueue {

    public func enqueue(_ mutation: OfflineMutation) async {
        let row = PersistedOfflineMutation(
            id: mutation.id,
            entityRaw: mutation.entity.rawValue,
            operationRaw: mutation.operation.rawValue,
            payloadData: mutation.payloadData,
            enqueuedAt: mutation.enqueuedAt,
            attemptCount: mutation.attemptCount
        )
        modelContext.insert(row)
        try? modelContext.save()
    }

    public func pendingMutations() async -> [OfflineMutation] {
        let descriptor = FetchDescriptor<PersistedOfflineMutation>(
            sortBy: [SortDescriptor(\.enqueuedAt, order: .forward)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.compactMap(OfflineMutation.init(persisted:))
    }

    public func drain(apply: @Sendable (OfflineMutation) async throws -> Void) async {
        for mutation in await pendingMutations() {
            do {
                try await apply(mutation)
                await remove(id: mutation.id)
            } catch {
                // Preserve FIFO ordering: stop at the first failure rather
                // than skipping ahead, so a later mutation for the same
                // entity never applies before an earlier one it depends on.
                return
            }
        }
    }

    public func remove(id: UUID) async {
        let descriptor = FetchDescriptor<PersistedOfflineMutation>(predicate: #Predicate { $0.id == id })
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(row)
        try? modelContext.save()
    }

    public func clear() async {
        let descriptor = FetchDescriptor<PersistedOfflineMutation>()
        guard let rows = try? modelContext.fetch(descriptor) else { return }
        for row in rows {
            modelContext.delete(row)
        }
        try? modelContext.save()
    }
}
