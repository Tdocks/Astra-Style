//
//  LiveOutfitRepository+Offline.swift
//  AstraStyle
//
//  P1-CORE-06: `updateOutfit` and `recordWear` have always enqueued a
//  `.outfit`/`.outfitWear` mutation on failure (see `LiveOutfitRepository`),
//  but nothing in the app ever replayed them — `LiveClosetRepository`'s own
//  drain skips them via `OfflineMutationNotHandled` (correctly, it isn't
//  their owner), so they sat in the shared queue forever rather than being
//  dropped. This is the missing replayer, wired the same way
//  `LiveClosetRepository.drainPendingMutations()` is: called after every
//  successful network call this type makes.
//
//  No conflict-resolution pass here, unlike the closet's `drainPendingMutations`
//  (ADR 0005 / `OfflineConflictResolution`). Both queued shapes are
//  overwrite-style already: `updateOutfit` was already a plain last-write
//  wins `UPDATE` with no offline conflict check in its online path, and
//  `recordWear` is a pure `INSERT` with a client-minted id — there is no
//  remote row for either to conflict with that this drain does not already
//  handle by construction.
//

import Foundation

extension LiveOutfitRepository {
    func drainPendingMutations() async {
        guard beginDraining() else { return }
        defer { endDraining() }

        let writer = self.writer
        await offlineQueue.drain { mutation in
            switch mutation.entity {
            case .outfit:
                let outfit = try JSONDecoder.astraDefault.decode(Outfit.self, from: mutation.payloadData)
                _ = try await writer.updateOutfit(outfit)
            case .outfitWear:
                let wear = try JSONDecoder.astraDefault.decode(OutfitWear.self, from: mutation.payloadData)
                _ = try await writer.createWear(wear)
            case .closetItem, .occasion:
                // Not this repository's mutation — owned by
                // `LiveClosetRepository` (`.closetItem`) or nothing yet
                // (`.occasion`). Skip rather than fail so this repository's
                // own backlog behind it still drains (mirrors
                // `LiveClosetRepository+Offline`'s handling of `.outfit`).
                throw OfflineMutationNotHandled()
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
}
