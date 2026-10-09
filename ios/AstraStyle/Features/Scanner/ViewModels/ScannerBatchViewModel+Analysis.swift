import Foundation

extension ScannerBatchViewModel {
    func logOutcome(_ outcome: Outcome) {
        guard !outcome.isCompletelyClean else {
            Self.logger.info("batch clean: \(outcome.readyCount, privacy: .public) ready")
            return
        }
        let analysis = outcome.analysisFailures.isEmpty
            ? "none"
            : outcome.analysisFailures
                .map { "\($0.key.rawValue)=\($0.value)" }
                .sorted()
                .joined(separator: ",")
        Self.logger.error(
            "batch lost \(outcome.lostCount, privacy: .public)/\(outcome.selected, privacy: .public) — couldNotLoad=\(outcome.couldNotLoad, privacy: .public) overLimit=\(outcome.skippedOverLimit, privacy: .public) unreadable=\(outcome.unreadable, privacy: .public) uploadFailed=\(outcome.uploadFailed, privacy: .public) analysis=\(analysis, privacy: .public)"
        )
    }

    func persist(_ batch: PendingBatch) async throws {
        let record = ScannerBatchPendingRecord(
            ownerID: batch.ownerID,
            idempotencyKey: batch.idempotencyKey,
            entries: batch.uploaded.map { item in
                ScannerBatchPendingEntry(
                    id: item.id,
                    data: item.capture.prepared.data,
                    pixelWidth: item.capture.prepared.pixelWidth,
                    pixelHeight: item.capture.prepared.pixelHeight,
                    originalByteCount: item.capture.prepared.originalByteCount,
                    deviceHints: item.capture.deviceHints,
                    storagePath: item.storagePath,
                    analysis: item.analysis,
                    analysisFailureReason: item.analysisFailureReason
                )
            },
            selected: batch.outcome.selected,
            skippedOverLimit: batch.outcome.skippedOverLimit,
            couldNotLoad: batch.outcome.couldNotLoad,
            unreadable: batch.outcome.unreadable,
            uploadFailed: batch.outcome.uploadFailed,
            isComplete: batch.isComplete,
            consumedDraftIDs: batch.consumedDraftIDs,
            discardedDraftIDs: batch.discardedDraftIDs
        )
        try await dependencies.pendingStore.save(record)
    }

    func capPhase(for error: FreeTierClosetError) -> Phase {
        switch error {
        case .capReached(let limit):
            .capReached(limit: limit)
        }
    }

    /// Best-effort cleanup. Failures leave an orphan, but do not hide the
    /// more useful analysis result from the user.
    func discard(_ paths: [String]) async {
        for path in paths {
            try? await dependencies.closetRepository.deleteCapturedImage(atPath: path)
        }
    }

    func deleteAll(_ paths: [String]) async throws {
        for path in paths {
            try await dependencies.closetRepository.deleteCapturedImage(atPath: path)
        }
    }

    func asAstraError(_ error: Error) -> AstraError {
        if let astra = error as? AstraError { return astra }
        return AstraError.network(String(
            localized: "That batch could not be analysed. Try again in a moment.",
            comment: "Scanner batch analysis failure"
        ))
    }

    func analyzeAll(
        _ uploaded: [Uploaded],
        idempotencyKey: String,
        acceptedJobID: UUID?,
        isRetry: Bool,
        outcome: inout Outcome
    ) async {
        phase = .analyzing(total: uploaded.count)
        guard let ownerID = await dependencies.currentOwnerID(),
              let pendingBatch,
              pendingBatch.ownerID == ownerID else {
            phase = .failed(AstraError.auth("Your account changed. Sign in to the account that started this batch."))
            return
        }

        let current = PendingBatch(
            uploaded: uploaded,
            idempotencyKey: idempotencyKey,
            outcome: outcome,
            ownerID: ownerID,
            acceptedJobID: acceptedJobID
        )
        self.pendingBatch = current
        do {
            try await persist(current)
        } catch {
            if isRetry || acceptedJobID != nil {
                phase = .failed(AstraError.server("Couldn't update this batch's retry details. Its photos were kept."))
                return
            }
            // No enqueue was attempted, so these deterministic uploads are
            // not owned by a server job and can be removed safely.
            await discard(uploaded.map(\.storagePath))
            self.pendingBatch = nil
            phase = .failed(AstraError.server("Couldn't save this batch's retry details on this device."))
            return
        }

        do {
            let requests = requests(for: uploaded)
            let batch = try await dependencies.closetRepository.resumeBatchAnalysis(
                requests,
                idempotencyKey: idempotencyKey,
                acceptedJobID: acceptedJobID,
                isRetry: isRetry
            )
            await finish(
                batch,
                uploaded: uploaded,
                idempotencyKey: idempotencyKey,
                ownerID: ownerID,
                outcome: &outcome
            )
        } catch {
            await handleAnalysisFailure(
                error,
                current: current,
                uploaded: uploaded,
                ownerID: ownerID
            )
        }
    }

    private func requests(for uploaded: [Uploaded]) -> [ClosetItemAnalysisRequest] {
        uploaded.map { item in
            ClosetItemAnalysisRequest(
                id: item.id,
                imageData: item.capture.prepared.data,
                storagePath: item.storagePath,
                imageType: .front,
                deviceHints: item.capture.deviceHints
            )
        }
    }

    private func handleAnalysisFailure(
        _ error: Error,
        current: PendingBatch,
        uploaded: [Uploaded],
        ownerID: UUID
    ) async {
        if let capError = error as? FreeTierClosetError {
            await cancelAndClean(current, uploaded: uploaded)
            phase = capPhase(for: capError)
            return
        }
        guard let failure = error as? ClosetBatchAnalysisFailure else {
            pendingBatch = current
            let astra = asAstraError(error)
            Self.logger.error("batch analysis threw: \(astra.message, privacy: .public)")
            phase = .failed(astra)
            return
        }

        switch failure {
        case .accepted(let jobID, _):
            let accepted = PendingBatch(
                uploaded: uploaded,
                idempotencyKey: current.idempotencyKey,
                outcome: current.outcome,
                ownerID: ownerID,
                acceptedJobID: jobID
            )
            pendingBatch = accepted
            // The previous record already has the same key and paths, so a
            // failed metadata upgrade can still replay the accepted job.
            try? await persist(accepted)
        case .terminalFailure:
            await cancelAndClean(current, uploaded: uploaded)
        case .rejected, .enqueueUncertain:
            pendingBatch = current
        }
        phase = .failed(failure.underlying)
    }

    private func cancelAndClean(_ current: PendingBatch, uploaded: [Uploaded]) async {
        do {
            try await dependencies.closetRepository.cancelBatchAnalysis(
                idempotencyKey: current.idempotencyKey
            )
            try await deleteAll(uploaded.map(\.storagePath))
            try await dependencies.pendingStore.remove(ownerID: current.ownerID)
            pendingBatch = nil
        } catch {
            // Cancellation can fail while a worker lease is live. In that
            // case keep both the manifest and uploaded inputs for retry.
            pendingBatch = current
        }
    }

    private func finish(
        _ batch: ClosetItemAnalysisBatch,
        uploaded: [Uploaded],
        idempotencyKey: String,
        ownerID: UUID,
        outcome: inout Outcome
    ) async {
        let completed = completedBatch(
            batch,
            uploaded: uploaded,
            idempotencyKey: idempotencyKey,
            ownerID: ownerID,
            outcome: outcome
        )
        do {
            try await persist(completed)
        } catch {
            phase = .failed(AstraError.server("The batch finished, but its review details could not be saved on this device."))
            return
        }
        pendingBatch = completed
        for item in completed.uploaded where item.analysis != nil {
            dependencies.draftStore.put(CaptureDraft(
                id: item.id,
                prepared: item.capture.prepared,
                deviceHints: item.capture.deviceHints,
                storagePath: item.storagePath,
                analysis: item.analysis
            ))
        }
        try? await deleteDiscardedDrafts()
        logOutcome(completed.outcome)
        phase = .ready(completed.outcome)
    }

    private func completedBatch(
        _ batch: ClosetItemAnalysisBatch,
        uploaded: [Uploaded],
        idempotencyKey: String,
        ownerID: UUID,
        outcome: Outcome
    ) -> PendingBatch {
        var completedUploads: [Uploaded] = []
        var completedOutcome = outcome
        for item in uploaded {
            if let analysis = batch.result(for: item.id) {
                completedUploads.append(Uploaded(
                    id: item.id,
                    capture: item.capture,
                    storagePath: item.storagePath,
                    analysis: analysis
                ))
                completedOutcome.draftIDs.append(item.id)
            } else {
                let reason = batch.failure(for: item.id)?.reason ?? .unknown
                completedUploads.append(Uploaded(
                    id: item.id,
                    capture: item.capture,
                    storagePath: item.storagePath,
                    analysisFailureReason: reason
                ))
                completedOutcome.analysisFailures[reason, default: 0] += 1
            }
        }
        let current = pendingBatch
        let completed = PendingBatch(
            uploaded: completedUploads,
            idempotencyKey: current?.idempotencyKey ?? idempotencyKey,
            outcome: completedOutcome,
            ownerID: ownerID,
            acceptedJobID: current?.acceptedJobID,
            isComplete: true,
            consumedDraftIDs: current?.consumedDraftIDs ?? [],
            discardedDraftIDs: Set(completedUploads.filter { $0.analysis == nil }.map(\.id))
        )
        return completed
    }

    func deleteDiscardedDrafts() async throws {
        guard var batch = pendingBatch, batch.isComplete, !batch.discardedDraftIDs.isEmpty else { return }
        let discarded = batch.uploaded.filter { batch.discardedDraftIDs.contains($0.id) }
        try await deleteAll(discarded.map(\.storagePath))
        batch.discardedDraftIDs.removeAll()
        pendingBatch = batch
        try await persist(batch)
    }

    func clearCompleteManifestIfConsumed() async {
        guard let batch = pendingBatch, batch.isComplete, batch.discardedDraftIDs.isEmpty else { return }
        let reviewableIDs = Set(batch.uploaded.filter { $0.analysis != nil }.map(\.id))
        guard reviewableIDs.isSubset(of: batch.consumedDraftIDs) else { return }
        do {
            try await dependencies.pendingStore.remove(ownerID: batch.ownerID)
            pendingBatch = nil
        } catch {
            phase = .failed(AstraError.server("Couldn't clear the completed batch record. Your saved items are safe."))
        }
    }
}
