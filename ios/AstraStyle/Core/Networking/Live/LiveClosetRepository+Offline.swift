import Foundation

extension LiveClosetRepository {
    /// Merge queued local intent into a newly fetched snapshot before it is
    /// cached or shown. Otherwise a reconnect read can erase optimistic edits
    /// immediately before the same request starts draining them.
    func itemsPreservingPendingMutations(_ serverItems: [ClosetItem], for owner: UUID) async -> [ClosetItem] {
        var byID = Dictionary(uniqueKeysWithValues: serverItems.filter { $0.userID == owner }.map { ($0.id, $0) })
        for mutation in await offlineQueue.pendingMutations() where mutation.entity == .closetItem {
            if mutation.operation == .create,
               let payload = try? JSONDecoder.astraDefault.decode(ClosetCreateMutationPayload.self, from: mutation.payloadData) {
                guard payload.item.userID == owner else { continue }
                byID[payload.item.id] = payload.item
                continue
            }
            guard let item = try? JSONDecoder.astraDefault.decode(ClosetItem.self, from: mutation.payloadData),
                  item.userID == owner else { continue }
            switch mutation.operation {
            case .create, .update:
                byID[item.id] = item
            case .delete:
                var archived = item
                archived.archivedAt = archived.archivedAt ?? mutation.enqueuedAt
                byID[item.id] = archived
            }
        }
        return byID.values.sorted { $0.createdAt > $1.createdAt }
    }

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
        let currentUserID = self.currentUserID
        await offlineQueue.drain { mutation in
            guard mutation.entity == .closetItem else { throw OfflineMutationNotHandled() }
            if mutation.operation == .create,
               let payload = try? JSONDecoder.astraDefault.decode(ClosetCreateMutationPayload.self, from: mutation.payloadData) {
                guard let owner = await currentUserID(), payload.item.userID == owner else {
                    throw OfflineMutationNotHandled()
                }
                try await Self.replayCreate(payload.item, images: payload.images, writer: writer)
                return
            }
            // Previously queued item-only payloads remain readable.
            let item = try JSONDecoder.astraDefault.decode(ClosetItem.self, from: mutation.payloadData)
            guard let owner = await currentUserID(), item.userID == owner else {
                throw OfflineMutationNotHandled()
            }
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

    func pendingCreateImages(forItem itemID: UUID) async -> [ClosetItemImage] {
        guard let owner = await currentUserID() else { return [] }
        var images: [UUID: ClosetItemImage] = [:]
        for mutation in await offlineQueue.pendingMutations() where mutation.entity == .closetItem && mutation.operation == .create {
            guard let payload = try? JSONDecoder.astraDefault.decode(ClosetCreateMutationPayload.self, from: mutation.payloadData),
                  payload.item.id == itemID, payload.item.userID == owner else { continue }
            for image in payload.images where image.closetItemID == itemID { images[image.id] = image }
        }
        return images.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func queueMutation(_ operation: OfflineMutation.Operation, item: ClosetItem, images: [ClosetItemImage] = []) async throws {
        guard let owner = await currentUserID(), owner == item.userID else {
            throw AstraError.server("Couldn't save this closet change for the current account.")
        }
        let payload = operation == .create && !images.isEmpty
            ? try JSONEncoder.astraDefault.encode(ClosetCreateMutationPayload(item: item, images: images))
            : try JSONEncoder.astraDefault.encode(item)
        try await offlineQueue.enqueue(
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
            try await replayCreate(item, images: [], writer: writer)
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
    private static func replayCreate(_ item: ClosetItem, images: [ClosetItemImage], writer: any ClosetWriting) async throws {
        if try await writer.fetch(id: item.id) != nil {
            _ = try await writer.update(item)
            try await writer.ensureImages(images)
        } else {
            _ = try await writer.create(item, images: images)
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
                makeConflict(
                    mutation,
                    item: item,
                    remote: remote,
                    disposition: .discardedLocal,
                    reason: reason
                ),
                with: conflictRecorder
            )
        case .surfaceConflict(let reason):
            // Record + remove (successful return). Throwing would wedge the
            // FIFO backlog; `OfflineSyncConflictError` wraps the recorded
            // value for any later UI resolution pass.
            await recordConflict(
                makeConflict(
                    mutation,
                    item: item,
                    remote: remote,
                    disposition: .needsResolution,
                    reason: reason
                ),
                with: conflictRecorder
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

    private static func makeConflict(
        _ mutation: OfflineMutation,
        item: ClosetItem,
        remote: ClosetItem?,
        disposition: OfflineSyncConflict.Disposition,
        reason: String
    ) -> OfflineSyncConflict {
        OfflineSyncConflict(
            mutationID: mutation.id,
            itemID: item.id,
            operation: mutation.operation,
            disposition: disposition,
            reason: reason,
            localUpdatedAt: item.updatedAt,
            remoteUpdatedAt: remote?.updatedAt
        )
    }

    private static func recordConflict(
        _ conflict: OfflineSyncConflict,
        with conflictRecorder: OfflineConflictRecording
    ) async {
        OfflineConflictLog.log(conflict)
        await conflictRecorder.record(conflict)
    }
}
