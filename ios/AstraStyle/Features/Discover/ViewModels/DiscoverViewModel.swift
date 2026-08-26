//
//  DiscoverViewModel.swift
//  AstraStyle
//
//  ADR 0017: his lookbooks, other men's worn public looks, and Unlocks
//  ranked by HIS computeUnlockCount — never last_checked_at, never
//  sponsored sort (P6-SHOP-09). Home stays private.
//

import Foundation
import Observation

@MainActor
@Observable
public final class DiscoverViewModel {
    /// One outfit joined to drawable garments for the Discover rails.
    public struct DiscoverLook: Identifiable, Sendable {
        public var outfit: Outfit
        public var garments: [LookGarment]
        public var id: UUID { outfit.id }

        public init(outfit: Outfit, garments: [LookGarment]) {
            self.outfit = outfit
            self.garments = garments
        }
    }

    public struct Catalog: Sendable {
        public var mine: [DiscoverLook]
        public var wornByOthers: [DiscoverLook]
        public var unlocks: [ProductUnlock]

        public var isEmpty: Bool {
            mine.isEmpty && wornByOthers.isEmpty && unlocks.isEmpty
        }
    }

    public enum ViewState: Sendable {
        case loading
        case loaded(Catalog)
        case empty
        case failed(AstraError)
    }

    public private(set) var state: ViewState = .loading
    public private(set) var frame: FrameProfile = .unknown

    private let outfitRepository: OutfitRepository
    private let shoppingRepository: ShoppingRepository
    private let closetRepository: ClosetRepository
    private let profileRepository: ProfileRepository
    private let hydrator: LookHydrator

    public init(
        outfitRepository: OutfitRepository,
        shoppingRepository: ShoppingRepository,
        closetRepository: ClosetRepository,
        profileRepository: ProfileRepository,
        imageURLResolver: ClosetImageURLResolving
    ) {
        self.outfitRepository = outfitRepository
        self.shoppingRepository = shoppingRepository
        self.closetRepository = closetRepository
        self.profileRepository = profileRepository
        self.hydrator = LookHydrator(
            closetRepository: closetRepository,
            imageURLResolver: imageURLResolver
        )
    }

    public func onAppear() async {
        guard case .loading = state else { return }
        await load()
    }

    public func refresh() async {
        await load()
    }

    private func load() async {
        do {
            async let mineTask = outfitRepository.fetchOutfits()
            async let publicTask = outfitRepository.fetchPublicWornLooks()
            async let unlocksTask = shoppingRepository.fetchUnlocks()
            async let closetTask = closetRepository.fetchItems()

            let mineOutfits = try await mineTask.filter { !$0.isArchived }
            let wornByOthersOutfits = (try? await publicTask) ?? []
            let unlocks = rankedGapUnlocks((try? await unlocksTask) ?? [])
            let closet = try await closetTask

            let allOutfits = mineOutfits + wornByOthersOutfits
            let itemsPerOutfit = await outfitItems(for: allOutfits)
            let allGarments = await hydrator.hydrate(outfits: itemsPerOutfit, closet: closet)

            let mineLooks = zip(mineOutfits, allGarments.prefix(mineOutfits.count))
                .map { DiscoverLook(outfit: $0.0, garments: $0.1) }
            let othersGarments = Array(allGarments.dropFirst(mineOutfits.count))
            let othersLooks = zip(wornByOthersOutfits, othersGarments)
                .map { DiscoverLook(outfit: $0.0, garments: $0.1) }

            let catalog = Catalog(
                mine: mineLooks,
                wornByOthers: othersLooks,
                unlocks: unlocks
            )
            state = catalog.isEmpty ? .empty : .loaded(catalog)
            await loadFrame()
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    private func loadFrame() async {
        guard let body = try? await profileRepository.fetchBodyProfile() else { return }
        frame = FrameDerivation.derive(from: body)
    }

    private func outfitItems(for outfits: [Outfit]) async -> [[OutfitItem]] {
        let repository = outfitRepository
        return await withTaskGroup(of: (Int, [OutfitItem]).self) { group in
            for (index, outfit) in outfits.enumerated() {
                group.addTask {
                    let items = (try? await repository.fetchOutfitItems(outfitID: outfit.id)) ?? []
                    return (index, items)
                }
            }
            var collected = Array(repeating: [OutfitItem](), count: outfits.count)
            for await (index, items) in group {
                collected[index] = items
            }
            return collected
        }
    }

    /// Gap > 0 only. Sort by unlock count descending. Ties keep input order.
    /// `sponsored` / affiliate is never a sort key (P6-SHOP-09).
    private func rankedGapUnlocks(_ items: [ProductUnlock]) -> [ProductUnlock] {
        items
            .enumerated()
            .filter { $0.element.outfitsUnlocked > 0 }
            .sorted { lhs, rhs in
                if lhs.element.outfitsUnlocked != rhs.element.outfitsUnlocked {
                    return lhs.element.outfitsUnlocked > rhs.element.outfitsUnlocked
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
