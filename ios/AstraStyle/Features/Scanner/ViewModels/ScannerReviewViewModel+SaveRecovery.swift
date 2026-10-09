import Foundation

extension ScannerReviewViewModel {
    public func save() async {
        guard canSave else { return }
        guard let storagePath else {
            phase = .saveFailed(AstraError.validation("The photo is not uploaded yet. Try again."))
            return
        }
        phase = .saving
        guard let ownerID = await currentUserID() else {
            phase = .saveFailed(AstraError.auth("Sign in to save this piece to your closet."))
            await finishSaveCleanup()
            return
        }
        await prepareAndPersistSave(ownerID: ownerID, sourcePath: storagePath)
    }

    func prepareAndPersistSave(ownerID: UUID, sourcePath: String) async {
        let identity = saveIdentity(for: ownerID)
        let item = buildItem(id: identity.item, userID: ownerID)
        var image = ClosetItemImage(
            id: identity.image,
            closetItemID: identity.item,
            imageType: .front,
            storagePath: sourcePath,
            backgroundRemovedPath: analysis?.normalizedImagePath,
            isPrimary: true
        )
        let previouslyUncertain = saveMayHavePersisted
        var record = PendingScannerSave(ownerID: ownerID, item: item, images: [image])
        guard await scannerSaveJournal.beginForegroundSave(id: record.id, ownerID: ownerID) else {
            phase = .saveFailed(AstraError.server("A previous save for this scan is still being reconciled. Try again shortly."))
            await finishSaveCleanup()
            return
        }
        do {
            try await scannerSaveJournal.save(record)
        } catch {
            await scannerSaveJournal.endForegroundSave(id: record.id, ownerID: ownerID)
            phase = .saveFailed(AstraError.server("Couldn't prepare this scan for a safe save. Try again."))
            await finishSaveCleanup()
            return
        }
        saveMayHavePersisted = true

        if let cutoutPath = await uploadedCutoutPath() {
            image.backgroundRemovedPath = cutoutPath
            record.images = [image]
            do {
                try await scannerSaveJournal.save(record)
            } catch {
                if cutoutPath != analysis?.normalizedImagePath {
                    try? await closetRepository.deleteCapturedImage(atPath: cutoutPath)
                }
                image.backgroundRemovedPath = analysis?.normalizedImagePath
                record.images = [image]
                cachedCutout = nil
            }
        }

        guard storagePath == sourcePath, await currentUserID() == ownerID else {
            await scannerSaveJournal.endForegroundSave(id: record.id, ownerID: ownerID)
            phase = .missingDraft
            return
        }
        await persistJournaledSave(record, previouslyUncertain: previouslyUncertain)
    }

    func persistJournaledSave(_ record: PendingScannerSave, previouslyUncertain: Bool) async {
        do {
            try await persistSavedItem(record.item, images: record.images)
            try? await scannerSaveJournal.remove(id: record.id, ownerID: record.ownerID)
        } catch let error as FreeTierClosetError {
            saveMayHavePersisted = previouslyUncertain
            if !previouslyUncertain {
                do {
                    try await scannerSaveJournal.remove(id: record.id, ownerID: record.ownerID)
                } catch {
                    // Keep referenced photos if the durable record could not
                    // be cleared, and let the user retry the safe cleanup.
                    saveMayHavePersisted = true
                    phase = .saveFailed(AstraError.server("Couldn't clear the saved scan recovery record. Try again."))
                    await finishSaveCleanup()
                    await scannerSaveJournal.endForegroundSave(id: record.id, ownerID: record.ownerID)
                    return
                }
            }
            if case .capReached(let limit) = error {
                phase = .capReached(limit: limit)
            }
        } catch {
            let message = (error as? AstraError) ?? AstraError.server("Couldn't save that piece. Try again.")
            phase = .saveFailed(message)
        }
        await finishSaveCleanup()
        await scannerSaveJournal.endForegroundSave(id: record.id, ownerID: record.ownerID)
    }

    func persistSavedItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws {
        savedItem = try await closetRepository.createItem(item, images: images)
        let corrected = fieldsCorrectedCount()
        analyticsClient.log(.closetItemAdded(category: item.category, source: .scan))
        if corrected > 0 {
            analyticsClient.log(.scanCorrected(fieldsCorrectedCount: corrected))
        }
        unlockCountState = .calculating
        draftStore.remove(id: draftID)
        AstraHaptics.success()
        phase = .saved
        Task { await calculateScanUnlockCount() }
    }

    public func retryScanUnlockCount() async {
        guard case .unavailable = unlockCountState else { return }
        unlockCountState = .calculating
        await calculateScanUnlockCount()
    }

    private func calculateScanUnlockCount() async {
        guard case .calculating = unlockCountState, let item = savedItem else { return }
        let activeOwner = await currentUserID()
        let isOffline = await networkMonitor.isOffline()
        guard item.userID == activeOwner, !isOffline else {
            unlockCountState = .unavailable
            return
        }
        do {
            let result = try await closetRepository.fetchScanUnlockCount(savedItemID: item.id)
            guard await currentUserID() == item.userID, savedItem?.id == item.id else {
                unlockCountState = .unavailable
                return
            }
            switch result {
            case .count(let count):
                unlockCountState = .count(count)
            case .unmeasurable:
                unlockCountState = .unmeasurable
            }
        } catch is CancellationError {
            unlockCountState = .unavailable
        } catch {
            // The closet save already succeeded. A count failure is only a
            // missing report, never a reason to turn the save into failure.
            unlockCountState = .unavailable
        }
    }
}
