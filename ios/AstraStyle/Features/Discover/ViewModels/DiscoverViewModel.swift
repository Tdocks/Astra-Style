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
        public let id: UUID
        public let name: String
        public let description: String?
        public let isPublicLook: Bool
        public var garments: [LookGarment]

        public init(outfit: Outfit, garments: [LookGarment]) {
            id = outfit.id
            name = outfit.name
            description = outfit.description
            isPublicLook = false
            self.garments = garments
        }

        public init(publicLook: PublicWornLook, garments: [LookGarment]) {
            id = publicLook.id
            name = publicLook.name
            description = publicLook.description
            isPublicLook = true
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
    public private(set) var wardrobeGraph: WardrobeGraph = .menswear3Role

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
            let wornByOthersLooks = (try? await publicTask) ?? []
            let unlocks = rankedGapUnlocks((try? await unlocksTask) ?? [])
            let closet = try await closetTask

            async let myItemsTask = outfitItems(for: mineOutfits)
            async let publicGarmentsTask = publicGarments(for: wornByOthersLooks)

            let myItems = await myItemsTask
            let myGarments = await hydrator.hydrate(outfits: myItems, closet: closet)
            let publicRows = await publicGarmentsTask
            let publicByOutfitID = await hydrator.hydrate(publicLookGarments: publicRows)

            let mineLooks = zip(mineOutfits, myGarments)
                .map { DiscoverLook(outfit: $0.0, garments: $0.1) }
            let othersLooks = wornByOthersLooks.map { publicLook in
                DiscoverLook(publicLook: publicLook, garments: publicByOutfitID[publicLook.id] ?? [])
            }

            let catalog = Catalog(
                mine: mineLooks,
                wornByOthers: othersLooks,
                unlocks: unlocks
            )
            state = catalog.isEmpty ? .empty : .loaded(catalog)
            await loadFrame()
            if let profile = try? await profileRepository.fetchCurrentProfile() {
                wardrobeGraph = profile.wardrobeGraph
            }
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
        let ids = outfits.map(\.id)
        guard !ids.isEmpty else { return [] }
        guard let rows = try? await outfitRepository.fetchOutfitItems(outfitIDs: ids) else {
            return Array(repeating: [], count: ids.count)
        }
        let itemsByOutfitID = Dictionary(grouping: rows, by: \.outfitID)
        return ids.map { itemsByOutfitID[$0] ?? [] }
    }

    private func publicGarments(for looks: [PublicWornLook]) async -> [PublicLookGarment] {
        let ids = looks.map(\.id)
        guard !ids.isEmpty else { return [] }
        return (try? await outfitRepository.fetchPublicLookGarments(outfitIDs: ids)) ?? []
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
