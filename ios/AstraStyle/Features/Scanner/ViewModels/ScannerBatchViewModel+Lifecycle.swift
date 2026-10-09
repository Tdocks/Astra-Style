import Foundation

@MainActor
extension ScannerBatchViewModel {
    public func restorePendingBatch() async {
        guard pendingBatch == nil, let ownerID = await dependencies.currentOwnerID() else { return }
        do {
            guard let record = try await dependencies.pendingStore.load(ownerID: ownerID),
                  record.ownerID == ownerID else { return }
            try await restore(record, ownerID: ownerID)
        } catch {
            phase = .failed(asAstraError(error))
        }
    }

    private func restore(_ record: ScannerBatchPendingRecord, ownerID: UUID) async throws {
        let uploaded = record.entries.compactMap { entry -> Uploaded? in
                guard let path = entry.storagePath,
                      isValidScannerBatchStoragePath(path, ownerID: ownerID) else { return nil }
                return Uploaded(
                    id: entry.id,
                    capture: PreparedCapture(
                        prepared: CapturePreparation.Prepared(
                            data: entry.data,
                            pixelWidth: entry.pixelWidth,
                            pixelHeight: entry.pixelHeight,
                            originalByteCount: entry.originalByteCount
                        ),
                        deviceHints: entry.deviceHints
                    ),
                    storagePath: path,
                    analysis: entry.analysis,
                    analysisFailureReason: entry.analysisFailureReason
                )
            }
        guard uploaded.count == record.entries.count, !uploaded.isEmpty else {
            throw AstraError.server("The saved batch could not be restored safely.")
        }
        let outcome = restoredOutcome(record)
        pendingBatch = PendingBatch(
            uploaded: uploaded,
            idempotencyKey: record.idempotencyKey,
            outcome: outcome,
            ownerID: ownerID,
            acceptedJobID: nil,
            isComplete: record.isComplete,
            consumedDraftIDs: record.consumedDraftIDs,
            discardedDraftIDs: record.discardedDraftIDs
        )
        if record.isComplete {
            await restoreCompletedDrafts(uploaded, record: record, outcome: outcome)
        } else {
            phase = .failed(AstraError.network("A batch scan was interrupted. Retry to continue."))
        }
    }

    private func restoredOutcome(_ record: ScannerBatchPendingRecord) -> Outcome {
        var outcome = Outcome(
            skippedOverLimit: record.skippedOverLimit,
            couldNotLoad: record.couldNotLoad,
            unreadable: record.unreadable,
            uploadFailed: record.uploadFailed,
            selected: record.selected
        )
        for entry in record.entries where entry.analysis == nil {
            outcome.analysisFailures[entry.analysisFailureReason ?? .unknown, default: 0] += 1
        }
        return outcome
    }

    private func restoreCompletedDrafts(
        _ uploaded: [Uploaded],
        record: ScannerBatchPendingRecord,
        outcome: Outcome
    ) async {
        for id in record.consumedDraftIDs {
            dependencies.draftStore.remove(id: id)
        }
        let draftIDs = uploaded.compactMap { item -> UUID? in
            guard let analysis = item.analysis,
                  !record.consumedDraftIDs.contains(item.id) else { return nil }
            dependencies.draftStore.put(CaptureDraft(
                id: item.id,
                prepared: item.capture.prepared,
                deviceHints: item.capture.deviceHints,
                storagePath: item.storagePath,
                analysis: analysis
            ))
            return item.id
        }
        var completedOutcome = outcome
        completedOutcome.draftIDs = draftIDs
        phase = .ready(completedOutcome)
        try? await deleteDiscardedDrafts()
        if draftIDs.isEmpty { await clearCompleteManifestIfConsumed() }
    }

    /// Explicitly abandons an ambiguous batch and removes its owned uploads.
    public func discardPendingBatch() async {
        guard let pendingBatch else { return }
        do {
            if pendingBatch.uploaded.contains(where: { !GuestLocalImageStore.isLocal($0.storagePath) }) {
                try await dependencies.closetRepository.cancelBatchAnalysis(
                    idempotencyKey: pendingBatch.idempotencyKey
                )
            }
            let paths = pendingBatch.uploaded
                .filter {
                    !pendingBatch.consumedDraftIDs.contains($0.id) ||
                        pendingBatch.discardedDraftIDs.contains($0.id)
                }
                .map(\.storagePath)
            try await deleteAll(paths)
            try await dependencies.pendingStore.remove(ownerID: pendingBatch.ownerID)
            for item in pendingBatch.uploaded where !pendingBatch.consumedDraftIDs.contains(item.id) ||
                pendingBatch.discardedDraftIDs.contains(item.id) {
                dependencies.draftStore.remove(id: item.id)
            }
            self.pendingBatch = nil
            phase = .idle
        } catch {
            phase = .failed(asAstraError(error))
        }
    }

    public func markDraftConsumed(_ id: UUID, saved: Bool) async -> Bool {
        if let write = consumptionWrites[id] { return await write.value }
        let write = Task { await persistDraftConsumption(id, saved: saved) }
        consumptionWrites[id] = write
        let succeeded = await write.value
        consumptionWrites[id] = nil
        return succeeded
    }

    private func persistDraftConsumption(_ id: UUID, saved: Bool) async -> Bool {
        guard var pendingBatch,
              pendingBatch.isComplete,
              pendingBatch.uploaded.contains(where: { $0.id == id }) else { return true }
        guard !pendingBatch.consumedDraftIDs.contains(id) else { return true }
        let previous = pendingBatch
        pendingBatch.consumedDraftIDs.insert(id)
        if !saved { pendingBatch.discardedDraftIDs.insert(id) }
        self.pendingBatch = pendingBatch
        do {
            try await persist(pendingBatch)
            if !saved { try? await deleteDiscardedDrafts() }
            await clearCompleteManifestIfConsumed()
            return true
        } catch {
            self.pendingBatch = previous
            return false
        }
    }

    public func importImages(_ images: [Data], selectedCount: Int) async {
        guard pendingBatch == nil else { return }
        let couldNotLoad = max(0, selectedCount - images.count)
        guard !images.isEmpty else {
            let nothingLoaded = Outcome(couldNotLoad: couldNotLoad, selected: selectedCount)
            logOutcome(nothingLoaded)
            phase = .ready(nothingLoaded)
            return
        }

        let accepted = Array(images.prefix(BatchScanLimits.maxItemsPerBatch))
        var outcome = Outcome(
            skippedOverLimit: images.count - accepted.count,
            couldNotLoad: couldNotLoad,
            selected: selectedCount
        )

        let prepared = prepareAll(accepted, outcome: &outcome)
        guard !prepared.isEmpty else {
            logOutcome(outcome)
            phase = .ready(outcome)
            return
        }

        let uploaded = await uploadAll(prepared, outcome: &outcome)
        guard !uploaded.isEmpty else {
            logOutcome(outcome)
            phase = .ready(outcome)
            return
        }

        let ownerID = await dependencies.currentOwnerID()
        guard let ownerID else {
            await discard(uploaded.map(\.storagePath))
            phase = .failed(AstraError.auth("Sign in again before continuing this batch."))
            return
        }
        let batch = PendingBatch(
            uploaded: uploaded,
            idempotencyKey: UUID().uuidString.lowercased(),
            outcome: outcome,
            ownerID: ownerID,
            acceptedJobID: nil
        )
        pendingBatch = batch
        await analyzeAll(
            uploaded,
            idempotencyKey: batch.idempotencyKey,
            acceptedJobID: nil,
            isRetry: false,
            outcome: &outcome
        )
    }

}
