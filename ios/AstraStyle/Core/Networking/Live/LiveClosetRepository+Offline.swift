import Foundation

extension LiveClosetRepository {
    /// Replays everything the offline queue is holding, oldest first.
    ///
    /// Called after every successful network call in this type. The queue
    /// stops at the first failure and counts an attempt against it, so a
    /// mutation that cannot apply blocks the ones behind it rather than
    /// letting a later write for the same item land first.
    func drainPendingMutations() async {
        guard beginDraining() else { return }
        defer { endDraining() }

        await offlineQueue.drain { [writer] mutation in
            // The queue is shared: `LiveOutfitRepository` enqueues `.outfit`
            // and `.outfitWear` into the same one. Those are not this type's
            // to replay, and neither failing on them (which would stop the
            // drain forever) nor applying them (which would corrupt data
            // through the wrong writer) is acceptable — so say "not mine" and
            // let them stay queued for their owner. NOTE: nothing drains
            // outfit mutations yet; see P1-CORE-06 in docs/03-progress.md.
            guard mutation.entity == .closetItem else { throw OfflineMutationNotHandled() }
            let item = try JSONDecoder.astraDefault.decode(ClosetItem.self, from: mutation.payloadData)
            switch mutation.operation {
            case .create: _ = try await writer.create(item, images: [])
            case .update: _ = try await writer.update(item)
            case .delete: try await writer.archive(id: item.id)
            }
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
}
