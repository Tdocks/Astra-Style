//
//  LookHydration.swift
//  AstraStyle
//
//  Joins an outfit's `outfit_items` to the garments they point at and signs
//  their images, producing the `[LookGarment]` a screen can actually draw.
//
//  Extracted from `DefaultHomeBriefProvider`, which had the only copy. The
//  Closet's outfit carousel needs the identical join for every outfit it
//  shows, and the second copy would have been the one that quietly forgot
//  to batch the signing.
//
//  BATCHED SIGNING IS THE WHOLE REASON THIS IS A SERVICE AND NOT A LOOP.
//  `ClosetImageURLResolving` has a plural method precisely so a screen full
//  of garments costs one request; a carousel of eight outfits at four
//  garments each is thirty-two paths, and signing them one at a time is
//  thirty-two round trips for one screen. `hydrate(outfits:)` collects every
//  path across every outfit first and signs the lot once.
//
//  EVERYTHING HERE DEGRADES TO A MISSING PICTURE, NEVER A MISSING GARMENT.
//  A garment whose image will not sign still appears, named, in its slot.
//  Dropping the shoes because a URL expired would be telling the user to
//  leave the house barefoot.
//

import Foundation

public struct LookHydrator: Sendable {
    private let closetRepository: ClosetRepository
    private let imageURLResolver: ClosetImageURLResolving

    public init(closetRepository: ClosetRepository, imageURLResolver: ClosetImageURLResolving) {
        self.closetRepository = closetRepository
        self.imageURLResolver = imageURLResolver
    }

    /// One outfit's garments, in the order the scorer produced them.
    ///
    /// - Parameter closet: Garments already in hand. The join is done against
    ///   this rather than by re-fetching each row: every caller has just
    ///   loaded the closet for its own reasons, and a per-garment fetch here
    ///   would ask the server for rows the caller is holding.
    public func hydrate(items: [OutfitItem], closet: [ClosetItem]) async -> [LookGarment] {
        let hydrated = await hydrate(outfits: [items], closet: closet)
        return hydrated.first ?? []
    }

    /// Several outfits at once, signing every image across all of them in a
    /// single call. Returns one array per input, in the same order.
    public func hydrate(outfits: [[OutfitItem]], closet: [ClosetItem]) async -> [[LookGarment]] {
        let byID = Dictionary(closet.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = outfits.map { join($0, byID: byID) }

        let everyGarmentID = Set(ordered.flatMap { $0 }.map(\.item.id))
        guard !everyGarmentID.isEmpty else { return ordered }

        let pathsByGarmentID = await primaryImagePaths(for: everyGarmentID)
        let signed = (try? await imageURLResolver.resolve(
            storagePaths: Array(Set(pathsByGarmentID.values))
        )) ?? [:]

        return ordered.map { garments in
            garments.map { garment in
                var copy = garment
                if let path = pathsByGarmentID[garment.item.id] {
                    copy.imageURL = signed[path]
                }
                return copy
            }
        }
    }

    private func join(
        _ items: [OutfitItem],
        byID: [UUID: ClosetItem]
    ) -> [LookGarment] {
        items
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { item in
                guard let closetItemID = item.closetItemID, let garment = byID[closetItemID] else {
                    // A `productCandidateID` entry is a garment the user does
                    // not own — the "complete this look" suggestion. It has no
                    // closet row and nothing to draw, and inventing a slot for
                    // it would put a thing he cannot wear inside a look he is
                    // being told to wear.
                    return nil
                }
                return LookGarment(item: garment, role: item.role)
            }
    }

    /// The display path per garment, fetched concurrently. Absent means the
    /// garment has no image on file, which is a different thing from an image
    /// that failed to sign and is handled the same way by the caller.
    private func primaryImagePaths(for garmentIDs: Set<UUID>) async -> [UUID: String] {
        let repository = closetRepository
        return await withTaskGroup(of: (UUID, String?).self) { group in
            for id in garmentIDs {
                group.addTask {
                    let images = (try? await repository.fetchImages(forItem: id)) ?? []
                    let primary = images.first { $0.isPrimary } ?? images.first
                    return (id, primary?.displayStoragePath)
                }
            }
            var collected: [UUID: String] = [:]
            for await (id, path) in group where path != nil {
                collected[id] = path
            }
            return collected
        }
    }
}
