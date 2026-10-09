import Foundation

private struct GridImagePaths: Sendable {
    let primary: String
    let fallback: String?
}

private struct GridImageResolutionPlan {
    let paths: Set<String>
    let prefetchPaths: Set<String>

    init(pathsByItemID: [UUID: GridImagePaths]) {
        paths = Set(pathsByItemID.values.flatMap { paths in
            [paths.primary, paths.fallback].compactMap { $0 }
        })
        prefetchPaths = Set(pathsByItemID.values.map(\.primary))
    }
}

extension ClosetViewModel {
    /// N path lookups, then exactly one signing request.
    func resolveImages(forItemIDs itemIDs: Set<UUID>, generation: UUID) async {
        // Captured as a local so the child tasks below capture the
        // already-`Sendable` repository rather than this `@MainActor`
        // view model.
        let repository = closetRepository
        // Read once on the main actor, for the same reason `repository` is:
        // the child tasks below must not touch this view model.
        let prefersCutouts = self.prefersCutouts

        let pathsByItemID = await withTaskGroup(of: (UUID, GridImagePaths?).self, returning: [UUID: GridImagePaths].self) { group in
            for itemID in itemIDs {
                group.addTask {
                    // One garment's images failing must not take the rest
                    // of the screenful with it — the tile falls back to
                    // a failed row does not take down the rest of the grid.
                    let images = (try? await repository.fetchImages(forItem: itemID)) ?? []
                    let primary = images.first { $0.isPrimary } ?? images.first
                    guard let primaryPath = primary?.gridThumbnailStoragePath(preferringCutout: prefersCutouts) else {
                        return (itemID, nil)
                    }
                    return (
                        itemID,
                        GridImagePaths(
                            primary: primaryPath,
                            fallback: primary?.gridFallbackStoragePath(preferringCutout: prefersCutouts)
                        )
                    )
                }
            }
            var collected: [UUID: GridImagePaths] = [:]
            for await (itemID, paths) in group {
                if let paths {
                    collected[itemID] = paths
                }
            }
            return collected
        }

        guard !pathsByItemID.isEmpty else { return }
        guard generation == imageResolutionGeneration, !Task.isCancelled else { return }

        do {
            // THE batch call. One request for the whole screenful, not one
            // per tile — see `ClosetImageURLResolving`'s own header for
            // why the two-method protocol exists.
            let plan = GridImageResolutionPlan(pathsByItemID: pathsByItemID)
            let signed = try await imageURLResolver.resolve(
                storagePaths: Array(plan.paths),
                prefetching: plan.prefetchPaths
            )
            // Reload clears resolved URLs and advances the generation. A
            // signer that finishes after that point must not repopulate the
            // grid with a URL for the closet snapshot that was replaced.
            guard generation == imageResolutionGeneration, !Task.isCancelled else { return }
            for (itemID, paths) in pathsByItemID {
                applySignedURLs(signed, to: itemID, paths: paths)
            }
        } catch {
            // Signing failing is not the closet failing to load. The
            // garments, their names, brands and counts are all still on
            // screen and still correct; only the photographs are missing,
            // which the tiles already render honestly. Surface it as the
            // connectivity condition it almost always is rather than
            // replacing a working screen with an error page.
            await updateConnectivityAfterImageFailure(generation: generation)
        }
    }

    private func updateConnectivityAfterImageFailure(generation: UUID) async {
        guard generation == imageResolutionGeneration else { return }
        let offline = await networkMonitor.isOffline()
        guard generation == imageResolutionGeneration, !Task.isCancelled else { return }
        isOffline = offline
    }

    private func applySignedURLs(
        _ signed: [String: URL],
        to itemID: UUID,
        paths: GridImagePaths
    ) {
        if let url = signed[paths.primary] {
            imageURLsByItemID[itemID] = url
            if let fallbackPath = paths.fallback, let fallbackURL = signed[fallbackPath] {
                imageFallbackURLsByItemID[itemID] = fallbackURL
            }
        } else if let fallbackPath = paths.fallback, let fallbackURL = signed[fallbackPath] {
            // Storage may report an absent variant inside a successful
            // batch-sign response. Keep its source image as the fallback.
            imageURLsByItemID[itemID] = fallbackURL
        }
    }

}
