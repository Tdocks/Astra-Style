//
//  AnalyticsEventQueueTests.swift
//  AstraStyleTests
//
//  Mirrors `OfflineMutationQueueTests`'s coverage shape (FIFO order,
//  drain-stops-at-first-failure) for `AnalyticsEventQueue`, plus the two
//  behaviours specific to this queue: the hard size cap (drop oldest) and
//  disk persistence surviving a fresh queue instance — the on-disk half of
//  "resilient to being offline."
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("AnalyticsEventQueue")
struct AnalyticsEventQueueTests {

    private func event(userID: UUID = UUID(), _ event: AnalyticsEvent = .onboardingStarted) -> QueuedAnalyticsEvent {
        QueuedAnalyticsEvent(userID: userID, event: event)
    }

    @Test("Events drain in FIFO order, oldest first")
    func drainAppliesInOrder() async throws {
        let queue = AnalyticsEventQueue(batchSize: 1, store: nil)
        let first = event()
        let second = event()
        await queue.enqueue(first)
        await queue.enqueue(second)

        let recorder = SentBatchRecorder()
        await queue.drain { batch in await recorder.record(batch) }

        #expect(await recorder.batches.map { $0.map(\.id) } == [[first.id], [second.id]])
        #expect(await queue.snapshot().isEmpty)
    }

    @Test("drain(send:) stops at the first failed batch, preserving the rest")
    func drainStopsAtFirstFailure() async throws {
        let queue = AnalyticsEventQueue(batchSize: 1, store: nil)
        let first = event()
        let second = event()
        let third = event()
        await queue.enqueue(first)
        await queue.enqueue(second)
        await queue.enqueue(third)

        struct SimulatedFailure: Error {}
        let recorder = SentBatchRecorder()
        await queue.drain { batch in
            await recorder.record(batch)
            if batch.first?.id == second.id {
                throw SimulatedFailure()
            }
        }

        // First batch succeeded and was removed; second failed and stayed
        // queued; third was never attempted.
        #expect(await recorder.batches.count == 2)
        let remaining = await queue.snapshot()
        #expect(remaining.map(\.id) == [second.id, third.id])
    }

    @Test("Enqueueing past maxQueueLength drops the OLDEST events, not the newest")
    func capDropsOldest() async throws {
        let queue = AnalyticsEventQueue(maxQueueLength: 3, batchSize: 10, store: nil)
        let events = (0..<5).map { _ in event() }
        for queuedEvent in events {
            await queue.enqueue(queuedEvent)
        }

        let remaining = await queue.snapshot()
        // Newest 3 survive; the oldest 2 were dropped.
        #expect(remaining.map(\.id) == events.suffix(3).map(\.id))
    }

    @Test("A queue backed by a disk store reloads its backlog after being recreated")
    func persistsAcrossInstances() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-queue-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        let store = AnalyticsEventDiskStore(fileURL: tempFile)

        let firstInstance = AnalyticsEventQueue(store: store)
        let queuedEvent = event()
        await firstInstance.enqueue(queuedEvent)

        // A brand new actor instance, reading the same file — simulates the
        // app relaunching while offline with a nonempty backlog.
        let secondInstance = AnalyticsEventQueue(store: store)
        let reloaded = await secondInstance.snapshot()
        #expect(reloaded.map(\.id) == [queuedEvent.id])
    }

    @Test("A successful drain persists the now-empty queue, not just the in-memory state")
    func successfulDrainPersistsRemoval() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-queue-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        let store = AnalyticsEventDiskStore(fileURL: tempFile)

        let queue = AnalyticsEventQueue(store: store)
        await queue.enqueue(event())
        await queue.drain { _ in }

        let reloaded = AnalyticsEventQueue(store: store)
        #expect(await reloaded.snapshot().isEmpty)
    }

    @Test("identify/reset are readable back via currentIdentity")
    func identityRoundTrips() async throws {
        let queue = AnalyticsEventQueue(store: nil)
        #expect(await queue.currentIdentity() == nil)

        let userID = UUID()
        await queue.setIdentity(userID)
        #expect(await queue.currentIdentity() == userID)

        await queue.setIdentity(nil)
        #expect(await queue.currentIdentity() == nil)
    }
}

/// `drain(send:)` takes a `@Sendable` closure, so the sent batches cannot be
/// collected into a captured `var` — an actor serialises the appends without
/// weakening the queue's own concurrency contract just to make a test
/// compile (same rationale as `OfflineMutationQueueTests.AppliedOrderRecorder`).
private actor SentBatchRecorder {
    private(set) var batches: [[QueuedAnalyticsEvent]] = []

    func record(_ batch: [QueuedAnalyticsEvent]) {
        batches.append(batch)
    }
}
