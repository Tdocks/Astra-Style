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
        while let next = mutations.first {
            do {
                try await apply(next)
                mutations.removeFirst()
            } catch {
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
