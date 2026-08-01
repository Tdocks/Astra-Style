//
//  OfflineConflictResolutionTests.swift
//  AstraStyleTests
//
//  Ticket P3-INFRA-01 / ADR 0005: last-write-wins by `updated_at` for field
//  edits; destructive archive/delete never silently discarded or auto-applied
//  over a newer remote row. Pure helper tests plus drain wiring that proves
//  discards leave resolvable recorded state.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Offline conflict resolution — ADR 0005 last-write-wins")
struct OfflineConflictResolutionTests {

    // MARK: - Fixtures

    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    private func item(name: String, updatedAt: Date) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: name,
            category: .top,
            updatedAt: updatedAt
        )
    }

    private func sameIdentity(as base: ClosetItem, name: String, updatedAt: Date) -> ClosetItem {
        ClosetItem(
            id: base.id,
            userID: base.userID,
            name: name,
            category: base.category,
            updatedAt: updatedAt
        )
    }

    // MARK: - Pure helper

    @Test("Local newer update → apply")
    func localNewerUpdateApplies() {
        let local = item(name: "Local", updatedAt: newer)
        let remote = sameIdentity(as: local, name: "Remote", updatedAt: older)
        let decision = OfflineConflictResolution.resolve(
            local: local,
            remote: remote,
            operation: .update
        )
        #expect(decision == .apply)
    }

    @Test("Equal updated_at on update → apply (tie favours queued local intent)")
    func equalTimestampsOnUpdateApply() {
        let local = item(name: "Local", updatedAt: newer)
        let remote = sameIdentity(as: local, name: "Remote", updatedAt: newer)
        let decision = OfflineConflictResolution.resolve(
            local: local,
            remote: remote,
            operation: .update
        )
        #expect(decision == .apply)
    }

    @Test("Remote newer update → discardLocal with reason (never silent)")
    func remoteNewerUpdateDiscardsWithReason() {
        let local = item(name: "Local", updatedAt: older)
        let remote = sameIdentity(as: local, name: "Remote", updatedAt: newer)
        let decision = OfflineConflictResolution.resolve(
            local: local,
            remote: remote,
            operation: .update
        )
        guard case .discardLocal(let reason) = decision else {
            Issue.record("Expected discardLocal, got \(decision)")
            return
        }
        #expect(reason.contains("newer"))
        #expect(reason.contains("last-write-wins"))
    }

    @Test("Remote newer archive/delete → surfaceConflict, not apply")
    func remoteNewerDeleteSurfacesConflict() {
        let local = item(name: "Local", updatedAt: older)
        let remote = sameIdentity(as: local, name: "Remote", updatedAt: newer)
        let decision = OfflineConflictResolution.resolve(
            local: local,
            remote: remote,
            operation: .delete
        )
        guard case .surfaceConflict(let reason) = decision else {
            Issue.record("Expected surfaceConflict, got \(decision)")
            return
        }
        #expect(reason.contains("archive/delete"))
        #expect(decision != .apply)
    }

    @Test("Local newer archive/delete → apply")
    func localNewerDeleteApplies() {
        let local = item(name: "Local", updatedAt: newer)
        let remote = sameIdentity(as: local, name: "Remote", updatedAt: older)
        let decision = OfflineConflictResolution.resolve(
            local: local,
            remote: remote,
            operation: .delete
        )
        #expect(decision == .apply)
    }

    @Test("Missing remote on update → surfaceConflict")
    func missingRemoteOnUpdateSurfacesConflict() {
        let local = item(name: "Local", updatedAt: newer)
        let decision = OfflineConflictResolution.resolve(
            local: local,
            remote: nil,
            operation: .update
        )
        guard case .surfaceConflict = decision else {
            Issue.record("Expected surfaceConflict, got \(decision)")
            return
        }
    }

    @Test("Missing remote on delete → discardLocal (already absent)")
    func missingRemoteOnDeleteDiscardsAsNoOp() {
        let local = item(name: "Local", updatedAt: newer)
        let decision = OfflineConflictResolution.resolve(
            local: local,
            remote: nil,
            operation: .delete
        )
        guard case .discardLocal = decision else {
            Issue.record("Expected discardLocal, got \(decision)")
            return
        }
    }

    // MARK: - Drain wiring

    private actor StubClosetWriter: ClosetWriting {
        private var remoteRows: [UUID: ClosetItem]
        private(set) var updated: [UUID] = []
        private(set) var archived: [UUID] = []
        private(set) var created: [UUID] = []

        init(remoteRows: [UUID: ClosetItem] = [:]) {
            self.remoteRows = remoteRows
        }

        func fetch(id: UUID) async throws -> ClosetItem? { remoteRows[id] }

        func create(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
            created.append(item.id)
            remoteRows[item.id] = item
            return item
        }

        func update(_ item: ClosetItem) async throws -> ClosetItem {
            updated.append(item.id)
            remoteRows[item.id] = item
            return item
        }

        func archive(id: UUID) async throws {
            archived.append(id)
            remoteRows[id] = nil
        }
    }

    private func makeRepository(
        queue: InMemoryOfflineMutationQueue,
        writer: some ClosetWriting,
        conflictRecorder: OfflineConflictRecording
    ) -> LiveClosetRepository {
        LiveClosetRepository(
            apiClient: AstraAPIClient(environment: .preview),
            offlineQueue: queue,
            supabase: AstraSupabaseClientFactory.previewClient,
            writer: writer,
            conflictRecorder: conflictRecorder,
            cache: InMemoryClosetItemCache()
        )
    }

    private func enqueue(
        _ operation: OfflineMutation.Operation,
        item: ClosetItem,
        on queue: InMemoryOfflineMutationQueue
    ) async throws {
        let payload = try JSONEncoder.astraDefault.encode(item)
        await queue.enqueue(
            OfflineMutation(entity: .closetItem, operation: operation, payloadData: payload)
        )
    }

    @Test("Drain applies local-newer update and leaves no conflict record")
    func drainAppliesLocalNewerUpdate() async throws {
        let local = item(name: "Local edit", updatedAt: newer)
        let remote = sameIdentity(as: local, name: "Stale remote", updatedAt: older)
        let writer = StubClosetWriter(remoteRows: [remote.id: remote])
        let recorder = InMemoryOfflineConflictRecorder()
        let queue = InMemoryOfflineMutationQueue()
        try await enqueue(.update, item: local, on: queue)
        let repository = makeRepository(queue: queue, writer: writer, conflictRecorder: recorder)

        await repository.drainPendingMutations()

        #expect(await queue.pendingMutations().isEmpty)
        #expect(await writer.updated == [local.id])
        #expect(await recorder.recordedConflicts().isEmpty)
    }

    @Test("Drain discards remote-newer update with recorded resolvable state")
    func drainDiscardsRemoteNewerUpdateWithRecord() async throws {
        let local = item(name: "Stale local", updatedAt: older)
        let remote = sameIdentity(as: local, name: "Winning remote", updatedAt: newer)
        let writer = StubClosetWriter(remoteRows: [remote.id: remote])
        let recorder = InMemoryOfflineConflictRecorder()
        let queue = InMemoryOfflineMutationQueue()
        try await enqueue(.update, item: local, on: queue)
        let repository = makeRepository(queue: queue, writer: writer, conflictRecorder: recorder)

        await repository.drainPendingMutations()

        #expect(await queue.pendingMutations().isEmpty, "Discarded mutation must leave the queue")
        #expect(await writer.updated.isEmpty, "Remote-newer update must not overwrite remote")
        let conflicts = await recorder.recordedConflicts()
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.disposition == .discardedLocal)
        #expect(conflicts.first?.itemID == local.id)
        #expect(conflicts.first?.operation == .update)
        // Typed error remains constructible from the recorded conflict.
        let typed = OfflineSyncConflictError(conflict: try #require(conflicts.first))
        #expect(typed.conflict.disposition == .discardedLocal)
    }

    @Test("Drain surfaces remote-newer archive as needsResolution and does not archive")
    func drainSurfacesRemoteNewerArchive() async throws {
        let local = item(name: "Local archive intent", updatedAt: older)
        let remote = sameIdentity(as: local, name: "Edited on other device", updatedAt: newer)
        let writer = StubClosetWriter(remoteRows: [remote.id: remote])
        let recorder = InMemoryOfflineConflictRecorder()
        let queue = InMemoryOfflineMutationQueue()
        try await enqueue(.delete, item: local, on: queue)
        let repository = makeRepository(queue: queue, writer: writer, conflictRecorder: recorder)

        await repository.drainPendingMutations()

        #expect(await queue.pendingMutations().isEmpty)
        #expect(await writer.archived.isEmpty, "Must not auto-apply archive over newer remote")
        let conflicts = await recorder.recordedConflicts()
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.disposition == .needsResolution)
        #expect(conflicts.first?.operation == .delete)
        let typed = OfflineSyncConflictError(conflict: try #require(conflicts.first))
        #expect(typed.conflict.disposition == .needsResolution)
    }

    @Test("Create drain prefers update when the remote id already exists")
    func createPreferUpdateWhenRemoteExists() async throws {
        let local = item(name: "Replayed create", updatedAt: newer)
        let remote = sameIdentity(as: local, name: "Already there", updatedAt: older)
        let writer = StubClosetWriter(remoteRows: [remote.id: remote])
        let recorder = InMemoryOfflineConflictRecorder()
        let queue = InMemoryOfflineMutationQueue()
        try await enqueue(.create, item: local, on: queue)
        let repository = makeRepository(queue: queue, writer: writer, conflictRecorder: recorder)

        await repository.drainPendingMutations()

        #expect(await queue.pendingMutations().isEmpty)
        #expect(await writer.created.isEmpty)
        #expect(await writer.updated == [local.id])
        #expect(await recorder.recordedConflicts().isEmpty)
    }
}
