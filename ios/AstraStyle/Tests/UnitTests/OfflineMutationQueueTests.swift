//
//  OfflineMutationQueueTests.swift
//  AstraStyleTests
//
//  Spec §22 "Unit tests: Offline queue". Exercises `InMemoryOfflineMutationQueue`
//  (Core/Mocks) as a stand-in for `SwiftDataOfflineMutationQueue` — both
//  conform to the same `OfflineMutationQueue` protocol, so these
//  ordering/draining contracts apply equally to the production
//  SwiftData-backed implementation.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("OfflineMutationQueue")
struct OfflineMutationQueueTests {

    @Test("Mutations are returned in FIFO order, oldest first")
    func pendingMutationsPreservesInsertionOrder() async throws {
        let queue = InMemoryOfflineMutationQueue()
        let first = OfflineMutation(entity: .closetItem, operation: .create, payloadData: Data("first".utf8))
        let second = OfflineMutation(entity: .closetItem, operation: .update, payloadData: Data("second".utf8))
        let third = OfflineMutation(entity: .outfit, operation: .create, payloadData: Data("third".utf8))

        await queue.enqueue(first)
        await queue.enqueue(second)
        await queue.enqueue(third)

        let pending = await queue.pendingMutations()
        #expect(pending.map(\.id) == [first.id, second.id, third.id])
    }

    @Test("drain(apply:) applies mutations in order and removes each on success")
    func drainAppliesInOrderAndRemovesSuccessful() async throws {
        let queue = InMemoryOfflineMutationQueue()
        let first = OfflineMutation(entity: .closetItem, operation: .create, payloadData: Data())
        let second = OfflineMutation(entity: .closetItem, operation: .update, payloadData: Data())
        await queue.enqueue(first)
        await queue.enqueue(second)

        let recorder = AppliedOrderRecorder()
        await queue.drain { mutation in
            await recorder.record(mutation.id)
        }

        #expect(await recorder.ids == [first.id, second.id])
        let remaining = await queue.pendingMutations()
        #expect(remaining.isEmpty)
    }

    @Test("drain(apply:) stops at the first failure, preserving order for the remainder")
    func drainStopsAtFirstFailureToPreserveOrdering() async throws {
        let queue = InMemoryOfflineMutationQueue()
        let first = OfflineMutation(entity: .closetItem, operation: .create, payloadData: Data())
        let second = OfflineMutation(entity: .closetItem, operation: .update, payloadData: Data())
        let third = OfflineMutation(entity: .closetItem, operation: .update, payloadData: Data())
        await queue.enqueue(first)
        await queue.enqueue(second)
        await queue.enqueue(third)

        struct SimulatedFailure: Error {}
        let recorder = AppliedOrderRecorder()
        await queue.drain { mutation in
            await recorder.record(mutation.id)
            if mutation.id == second.id {
                throw SimulatedFailure()
            }
        }

        // First succeeded and was removed; second failed and stayed
        // queued; third was never attempted (ordering would otherwise be
        // violated if it applied ahead of the still-pending second).
        #expect(await recorder.ids == [first.id, second.id])
        let remaining = await queue.pendingMutations()
        #expect(remaining.map(\.id) == [second.id, third.id])
    }

    @Test("remove(id:) removes only the targeted mutation")
    func removeTargetsSingleMutation() async throws {
        let queue = InMemoryOfflineMutationQueue()
        let first = OfflineMutation(entity: .closetItem, operation: .create, payloadData: Data())
        let second = OfflineMutation(entity: .closetItem, operation: .update, payloadData: Data())
        await queue.enqueue(first)
        await queue.enqueue(second)

        await queue.remove(id: first.id)

        let remaining = await queue.pendingMutations()
        #expect(remaining.map(\.id) == [second.id])
    }

    @Test("clear() empties the queue")
    func clearEmptiesQueue() async throws {
        let queue = InMemoryOfflineMutationQueue()
        await queue.enqueue(OfflineMutation(entity: .closetItem, operation: .create, payloadData: Data()))
        await queue.enqueue(OfflineMutation(entity: .outfit, operation: .update, payloadData: Data()))

        await queue.clear()

        #expect(await queue.pendingMutations().isEmpty)
    }
}

/// `drain(apply:)` takes a `@Sendable` closure, so the applied order cannot be
/// collected into a captured `var` — that is a data race the Swift 6 compiler
/// correctly rejects. An actor is the right recorder here: it serialises the
/// appends without weakening the queue's concurrency contract just to make a
/// test compile.
private actor AppliedOrderRecorder {
    private(set) var ids: [UUID] = []

    func record(_ id: UUID) {
        ids.append(id)
    }
}
