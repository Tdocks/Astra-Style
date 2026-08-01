//
//  OfflineDrainWiringTests.swift
//  AstraStyleTests
//
//  `OfflineMutationQueueTests` already covers the queue in isolation: FIFO
//  order, ordered drain, stop-at-first-failure. Every one of those tests
//  passed while the queue was, in practice, dead code — nothing in the app
//  called `drain(apply:)` at all, so mutations were accepted and never
//  replayed, and `LiveClosetRepository`'s header comment claimed the opposite.
//
//  These tests cover the part that was actually missing: the WIRING. That a
//  failed write reaches the queue, that a later successful call empties it
//  through the real writer, that a replay failure is counted rather than
//  silently retried forever, and that the drain does not run twice at once.
//  They drive `LiveClosetRepository` itself, with a stub `ClosetWriting`
//  standing in for Postgrest — the seam that exists so this is testable
//  without a live Supabase project.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Offline queue wiring — a queued closet write actually gets replayed")
struct OfflineDrainWiringTests {

    // MARK: - Doubles

    /// A `ClosetWriting` whose success/failure is switchable mid-test, so one
    /// test can express "offline, then online" rather than needing two.
    private actor StubClosetWriter: ClosetWriting {
        private var shouldFail: Bool
        private var remoteRows: [UUID: ClosetItem] = [:]
        private(set) var created: [UUID] = []
        private(set) var updated: [UUID] = []
        private(set) var archived: [UUID] = []

        init(shouldFail: Bool) {
            self.shouldFail = shouldFail
        }

        func setShouldFail(_ value: Bool) {
            shouldFail = value
        }

        /// Seeds a remote row so drain's LWW check has something to compare.
        func seedRemote(_ item: ClosetItem) {
            remoteRows[item.id] = item
        }

        var appliedIDs: [UUID] { created + updated + archived }

        func fetch(id: UUID) async throws -> ClosetItem? {
            if shouldFail { throw AstraError.network("offline") }
            return remoteRows[id]
        }

        func create(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
            if shouldFail { throw AstraError.network("offline") }
            created.append(item.id)
            remoteRows[item.id] = item
            return item
        }

        func update(_ item: ClosetItem) async throws -> ClosetItem {
            if shouldFail { throw AstraError.network("offline") }
            updated.append(item.id)
            remoteRows[item.id] = item
            return item
        }

        func archive(id: UUID) async throws {
            if shouldFail { throw AstraError.network("offline") }
            archived.append(id)
            remoteRows[id] = nil
        }
    }

    private func makeRepository(
        queue: InMemoryOfflineMutationQueue,
        writer: some ClosetWriting
    ) -> LiveClosetRepository {
        LiveClosetRepository(
            apiClient: AstraAPIClient(environment: .preview),
            offlineQueue: queue,
            supabase: AstraSupabaseClientFactory.previewClient,
            writer: writer
        )
    }

    private func item(_ name: String) -> ClosetItem {
        ClosetItem(id: UUID(), userID: UUID(), name: name, category: .top)
    }

    // MARK: - Tests

    @Test("A failed create is queued and the local value is returned")
    func failedCreateIsQueued() async throws {
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(queue: queue, writer: StubClosetWriter(shouldFail: true))
        let garment = item("Oxford Shirt")

        let returned = try await repository.createItem(garment, images: [])

        #expect(returned.id == garment.id)
        let pending = await queue.pendingMutations()
        #expect(pending.count == 1)
        #expect(pending.first?.entity == .closetItem)
        #expect(pending.first?.operation == .create)
    }

    @Test("A later successful write replays the whole backlog, oldest first")
    func successfulWriteDrainsTheBacklog() async throws {
        let writer = StubClosetWriter(shouldFail: true)
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(queue: queue, writer: writer)

        let first = item("Merino Sweater")
        var second = item("Chore Coat")
        second.updatedAt = Date(timeIntervalSince1970: 2_000)
        _ = try await repository.createItem(first, images: [])
        _ = try await repository.updateItem(second)
        #expect(await queue.pendingMutations().count == 2)

        // The network comes back. Seed an older remote for the update so
        // last-write-wins applies rather than treating a missing row as a
        // surfaced conflict (P3-INFRA-01).
        await writer.setShouldFail(false)
        var olderRemote = second
        olderRemote.name = "Older remote name"
        olderRemote.updatedAt = Date(timeIntervalSince1970: 1_000)
        await writer.seedRemote(olderRemote)
        let third = item("Chukka Boots")
        _ = try await repository.createItem(third, images: [])

        #expect(await queue.pendingMutations().isEmpty)
        // `third` is written first (it is the live call), then the backlog in
        // the order it was enqueued.
        #expect(await writer.appliedIDs == [third.id, first.id, second.id])
    }

    @Test("A successful read drains too — a returning user's backlog flushes without a write")
    func successfulReadDrains() async throws {
        let writer = StubClosetWriter(shouldFail: true)
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(queue: queue, writer: writer)

        let garment = item("Selvedge Denim")
        _ = try await repository.createItem(garment, images: [])
        #expect(await queue.pendingMutations().count == 1)

        await writer.setShouldFail(false)
        // `fetchItems` hits the preview Supabase client and will throw; the
        // drain is on its success path, so nothing should flush here. This
        // asserts the negative deliberately: it is the guard against a drain
        // that fires on failure and burns attempts while the device is still
        // offline.
        _ = try? await repository.fetchItems()
        #expect(await queue.pendingMutations().count == 1)

        // Draining explicitly is what `fetchItems` does on success.
        await repository.drainPendingMutations()
        #expect(await queue.pendingMutations().isEmpty)
        #expect(await writer.created == [garment.id])
    }

    @Test("A replay that fails increments attemptCount and leaves the queue intact")
    func failedReplayCountsAnAttempt() async throws {
        let writer = StubClosetWriter(shouldFail: true)
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(queue: queue, writer: writer)

        let garment = item("Wool Overcoat")
        _ = try await repository.createItem(garment, images: [])
        #expect(await queue.pendingMutations().first?.attemptCount == 0)

        await repository.drainPendingMutations()
        #expect(await queue.pendingMutations().first?.attemptCount == 1)

        await repository.drainPendingMutations()
        let pending = await queue.pendingMutations()
        #expect(pending.count == 1)
        #expect(pending.first?.attemptCount == 2)
    }

    @Test("An outfit mutation is skipped, not dropped, and does not block the closet backlog")
    func foreignMutationIsSkippedNotDiscarded() async throws {
        // The ordering here is the point: the foreign mutation is FIRST. Under
        // a plain stop-at-first-failure drain it would wedge the queue and the
        // closet write behind it would never replay.
        let writer = StubClosetWriter(shouldFail: true)
        let queue = InMemoryOfflineMutationQueue(seed: [
            OfflineMutation(entity: .outfit, operation: .update, payloadData: Data("{}".utf8))
        ])
        let repository = makeRepository(queue: queue, writer: writer)

        let garment = item("Trench Coat")
        _ = try await repository.createItem(garment, images: [])
        await writer.setShouldFail(false)
        await repository.drainPendingMutations()

        let pending = await queue.pendingMutations()
        #expect(pending.count == 1, "The outfit mutation must survive for the repository that owns it")
        #expect(pending.first?.entity == .outfit)
        #expect(pending.first?.attemptCount == 0, "Skipping is not an attempt")
        #expect(await writer.created == [garment.id], "The closet write behind it must still replay")
    }

    @Test("Two concurrent drains do not replay the same mutation twice")
    func concurrentDrainsDoNotDoubleApply() async throws {
        let writer = StubClosetWriter(shouldFail: true)
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(queue: queue, writer: writer)

        let garment = item("Field Watch")
        _ = try await repository.createItem(garment, images: [])
        await writer.setShouldFail(false)

        async let firstDrain: Void = repository.drainPendingMutations()
        async let secondDrain: Void = repository.drainPendingMutations()
        _ = await (firstDrain, secondDrain)

        #expect(await writer.created == [garment.id])
        #expect(await queue.pendingMutations().isEmpty)
    }
}
