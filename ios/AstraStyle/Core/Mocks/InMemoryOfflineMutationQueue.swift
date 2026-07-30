//
//  InMemoryOfflineMutationQueue.swift
//  AstraStyle
//
//  In-memory `OfflineMutationQueue` conformance used by
//  `AppContainer.preview()` and available to unit tests that want to
//  exercise queue ordering without SwiftData (spec §22 "Unit tests:
//  Offline queue").
//

import Foundation

public actor InMemoryOfflineMutationQueue: OfflineMutationQueue {
    private var mutations: [OfflineMutation] = []

    public init(seed: [OfflineMutation] = []) {
        mutations = seed
    }

    public func enqueue(_ mutation: OfflineMutation) async {
        mutations.append(mutation)
    }

    public func pendingMutations() async -> [OfflineMutation] {
        mutations
    }

    public func drain(apply: @Sendable (OfflineMutation) async throws -> Void) async {
        var skipped: Set<UUID> = []
        while let next = mutations.first(where: { !skipped.contains($0.id) }) {
            do {
                try await apply(next)
                // By id, not `removeFirst()`: `apply` suspends, and this actor
                // can accept an `enqueue`/`remove` in the meantime, so the
                // element at index 0 on resume is not guaranteed to be the one
                // that was just applied.
                mutations.removeAll { $0.id == next.id }
            } catch is OfflineMutationNotHandled {
                skipped.insert(next.id)
            } catch {
                if let index = mutations.firstIndex(where: { $0.id == next.id }) {
                    mutations[index].attemptCount += 1
                }
                return
            }
        }
    }

    public func remove(id: UUID) async {
        mutations.removeAll { $0.id == id }
    }

    public func clear() async {
        mutations.removeAll()
    }
}
