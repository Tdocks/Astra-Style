import Foundation

extension LiveClosetRepository {
    /// Replays everything the offline queue is holding, oldest first.
    ///
    /// Called after every successful network call in this type. The queue
    /// stops at the first failure and counts an attempt against it, so a
    /// mutation that cannot apply blocks the ones behind it rather than
    /// letting a later write for the same item land first.
    ///
    /// Conflict policy (ADR 0005 / `OfflineConflictResolution`): updates
    /// last-write-wins by `updated_at`; destructive archive/delete never
    /// silently overwrites a newer remote row — those surface a recorded
    /// conflict and the mutation is removed rather than applied.
    func drainPendingMutations() async {
        guard beginDraining() else { return }
        defer { endDraining() }

        let writer = self.writer
        let conflictRecorder = self.conflictRecorder
        await offlineQueue.drain { mutation in
            guard mutation.entity == .closetItem else { throw OfflineMutationNotHandled() }
            let item = try JSONDecoder.astraDefault.decode(ClosetItem.self, from: mutation.payloadData)
            try await Self.replayClosetMutation(
                mutation,
                item: item,
                writer: writer,
                conflictRecorder: conflictRecorder
            )
        }
    }

    func beginDraining() -> Bool {
        drainLock.lock()
        defer { drainLock.unlock() }
        if isDraining { return false }
        isDraining = true
        return true
    }

    func endDraining() {
        drainLock.lock()
        isDraining = false
        drainLock.unlock()
    }

    func queueMutation(_ operation: OfflineMutation.Operation, item: ClosetItem) async throws {
        let payload = try JSONEncoder.astraDefault.encode(item)
        await offlineQueue.enqueue(
            OfflineMutation(entity: .closetItem, operation: operation, payloadData: payload)
        )
    }

    // MARK: - Replay

    private static func replayClosetMutation(
        _ mutation: OfflineMutation,
        item: ClosetItem,
        writer: any ClosetWriting,
        conflictRecorder: OfflineConflictRecording
    ) async throws {
        switch mutation.operation {
        case .create:
            try await replayCreate(item, writer: writer)
        case .update, .delete:
            try await replayWithConflictCheck(
                mutation,
                item: item,
                writer: writer,
                conflictRecorder: conflictRecorder
            )
        }
    }

    /// Create has no LWW remote conflict of this shape. If the id already
    /// exists remotely (e.g. a prior partial sync), prefer update so drain
    /// does not fail on a unique-constraint conflict.
    private static func replayCreate(_ item: ClosetItem, writer: any ClosetWriting) async throws {
        if try await writer.fetch(id: item.id) != nil {
            _ = try await writer.update(item)
        } else {
            _ = try await writer.create(item, images: [])
        }
    }

    private static func replayWithConflictCheck(
        _ mutation: OfflineMutation,
        item: ClosetItem,
        writer: any ClosetWriting,
        conflictRecorder: OfflineConflictRecording
    ) async throws {
        let remote = try await writer.fetch(id: item.id)
        let decision = OfflineConflictResolution.resolve(
            local: item,
            remote: remote,
            operation: mutation.operation
        )
        switch decision {
        case .apply:
            try await applyMutation(mutation.operation, item: item, writer: writer)
        case .discardLocal(let reason):
            await recordConflict(
                mutation: mutation,
                item: item,
                remote: remote,
                disposition: .discardedLocal,
                reason: reason,
                conflictRecorder: conflictRecorder
            )
        case .surfaceConflict(let reason):
            // Record + remove (successful return). Throwing would wedge the
            // FIFO backlog; `OfflineSyncConflictError` wraps the recorded
            // value for any later UI resolution pass.
            await recordConflict(
                mutation: mutation,
                item: item,
                remote: remote,
                disposition: .needsResolution,
                reason: reason,
                conflictRecorder: conflictRecorder
            )
        }
    }

    private static func applyMutation(
        _ operation: OfflineMutation.Operation,
        item: ClosetItem,
        writer: any ClosetWriting
    ) async throws {
        switch operation {
        case .create:
            _ = try await writer.create(item, images: [])
        case .update:
            _ = try await writer.update(item)
        case .delete:
            try await writer.archive(id: item.id)
        }
    }

    private static func recordConflict(
        mutation: OfflineMutation,
        item: ClosetItem,
        remote: ClosetItem?,
        disposition: OfflineSyncConflict.Disposition,
        reason: String,
        conflictRecorder: OfflineConflictRecording
    ) async {
        let conflict = OfflineSyncConflict(
            mutationID: mutation.id,
            itemID: item.id,
            operation: mutation.operation,
            disposition: disposition,
            reason: reason,
            localUpdatedAt: item.updatedAt,
            remoteUpdatedAt: remote?.updatedAt
        )
        OfflineConflictLog.log(conflict)
        await conflictRecorder.record(conflict)
    }
}
