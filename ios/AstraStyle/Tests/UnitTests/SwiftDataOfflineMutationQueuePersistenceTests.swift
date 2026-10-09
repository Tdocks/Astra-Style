import Foundation
import SwiftData
import Testing
@testable import AstraStyle

@Suite("SwiftData offline mutation queue persistence")
struct OfflineMutationDiskTests {
    @Test("Mixed owner mutations survive relaunch, retain exact retry state, then clear on replay")
    func mutationsSurviveReopenAndReplayWithEntityHandlers() async throws {
        let (directory, storeURL) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture()

        // Enqueue out of timestamp order so the persisted fetch proves FIFO is
        // reconstructed from stored dates rather than insertion order.
        try await enqueue(fixture.outOfOrderMutations, storeURL: storeURL)
        try await assertPending(fixture.mutations, attempts: [3, 1, 0], ownerID: fixture.ownerID, storeURL: storeURL)

        let failedReplay = try await replayWithDistinctHandlers(
            storeURL: storeURL,
            failingMutationID: fixture.first.id
        )
        #expect(failedReplay.attemptedIDs == [fixture.first.id])
        #expect(failedReplay.failure == .injectedReplayFailure)

        // Reopening after a failed handler proves both the row and retry
        // counter reached the on-disk store, not a process-local queue.
        try await assertPending(fixture.mutations, attempts: [4, 1, 0], ownerID: fixture.ownerID, storeURL: storeURL)

        let successfulReplay = try await replayWithDistinctHandlers(storeURL: storeURL)
        #expect(successfulReplay.attemptedIDs == fixture.mutations.map(\.id))
        #expect(successfulReplay.failure == nil)

        // A final fresh container must observe the durable deletes as empty.
        let afterSuccess = try await pendingMutations(storeURL: storeURL)
        #expect(afterSuccess.isEmpty)
    }

    private func makeFixture() throws -> QueueFixture {
        let ownerID = UUID()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_001)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_002)
        let thirdDate = Date(timeIntervalSince1970: 1_700_000_003)
        let first = try mutation(QueueMutationSpec(
            ownerID: ownerID,
            entity: .closetItem,
            operation: .create,
            date: firstDate,
            attemptCount: 3
        ))
        let second = try mutation(QueueMutationSpec(
            ownerID: ownerID,
            entity: .outfit,
            operation: .create,
            date: secondDate,
            attemptCount: 1
        ))
        let third = try mutation(QueueMutationSpec(
            ownerID: ownerID,
            entity: .closetItem,
            operation: .update,
            date: thirdDate,
            attemptCount: 0
        ))
        return QueueFixture(ownerID: ownerID, first: first, mutations: [first, second, third], outOfOrderMutations: [third, first, second])
    }

    private func mutation(_ spec: QueueMutationSpec) throws -> OfflineMutation {
        let payload = QueueOwnerPayload(ownerID: spec.ownerID, entityID: UUID())
        return OfflineMutation(
            id: UUID(),
            entity: spec.entity,
            operation: spec.operation,
            payloadData: try JSONEncoder().encode(payload),
            enqueuedAt: spec.date,
            attemptCount: spec.attemptCount
        )
    }

    private func makeTemporaryStore() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-queue-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("queue.store", isDirectory: false))
    }

    private func assertPending(
        _ expected: [OfflineMutation],
        attempts: [Int],
        ownerID: UUID,
        storeURL: URL
    ) async throws {
        let actual = try await pendingMutations(storeURL: storeURL)
        #expect(actual.map(\.id) == expected.map(\.id))
        #expect(actual.map(\.enqueuedAt) == expected.map(\.enqueuedAt))
        #expect(actual.map(\.attemptCount) == attempts)
        #expect(actual.map(\.payloadData) == expected.map(\.payloadData))
        for pending in actual {
            let payload = try JSONDecoder().decode(QueueOwnerPayload.self, from: pending.payloadData)
            #expect(payload.ownerID == ownerID)
        }
    }

    private func enqueue(_ mutations: [OfflineMutation], storeURL: URL) async throws {
        let container = try AstraModelContainer.live(storeURL: storeURL)
        let queue = SwiftDataOfflineMutationQueue(modelContainer: container)
        for mutation in mutations {
            try await queue.enqueue(mutation)
        }
    }

    private func pendingMutations(storeURL: URL) async throws -> [OfflineMutation] {
        let container = try AstraModelContainer.live(storeURL: storeURL)
        let queue = SwiftDataOfflineMutationQueue(modelContainer: container)
        return await queue.pendingMutations()
    }

    private func replayWithDistinctHandlers(
        storeURL: URL,
        failingMutationID: UUID? = nil
    ) async throws -> ReplayResult {
        let container = try AstraModelContainer.live(storeURL: storeURL)
        let queue = SwiftDataOfflineMutationQueue(modelContainer: container)
        let recorder = ReplayRecorder()
        await queue.drain { mutation in
            switch mutation.entity {
            case .closetItem:
                try await Self.applyClosetMutation(mutation, failingMutationID: failingMutationID, recorder: recorder)
            case .outfit:
                try await Self.applyOutfitMutation(mutation, failingMutationID: failingMutationID, recorder: recorder)
            default:
                throw OfflineMutationNotHandled()
            }
        }
        return ReplayResult(
            attemptedIDs: await recorder.attemptedIDs,
            failure: await recorder.failure
        )
    }

    private static func applyClosetMutation(
        _ mutation: OfflineMutation,
        failingMutationID: UUID?,
        recorder: ReplayRecorder
    ) async throws {
        guard mutation.entity == .closetItem else { throw OfflineMutationNotHandled() }
        await recorder.recordAttempt(mutation.id)
        if mutation.id == failingMutationID {
            await recorder.recordFailure(.injectedReplayFailure)
            throw InjectedReplayFailure()
        }
    }

    private static func applyOutfitMutation(
        _ mutation: OfflineMutation,
        failingMutationID: UUID?,
        recorder: ReplayRecorder
    ) async throws {
        guard mutation.entity == .outfit else { throw OfflineMutationNotHandled() }
        await recorder.recordAttempt(mutation.id)
        if mutation.id == failingMutationID {
            await recorder.recordFailure(.injectedReplayFailure)
            throw InjectedReplayFailure()
        }
    }
}

private struct QueueOwnerPayload: Codable, Equatable {
    let ownerID: UUID
    let entityID: UUID
}

private struct QueueMutationSpec {
    let ownerID: UUID
    let entity: OfflineMutation.Entity
    let operation: OfflineMutation.Operation
    let date: Date
    let attemptCount: Int
}

private struct QueueFixture {
    let ownerID: UUID
    let first: OfflineMutation
    let mutations: [OfflineMutation]
    let outOfOrderMutations: [OfflineMutation]
}

private struct ReplayResult: Equatable {
    enum Failure: Equatable {
        case injectedReplayFailure
    }

    let attemptedIDs: [UUID]
    let failure: Failure?
}

private struct InjectedReplayFailure: Error {}

private actor ReplayRecorder {
    private(set) var attemptedIDs: [UUID] = []
    private(set) var failure: ReplayResult.Failure?

    func recordAttempt(_ id: UUID) {
        attemptedIDs.append(id)
    }

    func recordFailure(_ value: ReplayResult.Failure) {
        failure = value
    }
}
