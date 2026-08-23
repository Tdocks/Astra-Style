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
    public struct Catalog: Sendable {
        public var mine: [Outfit]
        public var wornByOthers: [Outfit]
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

    private let outfitRepository: OutfitRepository
    private let shoppingRepository: ShoppingRepository

    public init(
        outfitRepository: OutfitRepository,
        shoppingRepository: ShoppingRepository
    ) {
        self.outfitRepository = outfitRepository
        self.shoppingRepository = shoppingRepository
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

            let mine = try await mineTask.filter { !$0.isArchived }
            let wornByOthers = (try? await publicTask) ?? []
            let unlocks = rankedGapUnlocks((try? await unlocksTask) ?? [])
            let catalog = Catalog(mine: mine, wornByOthers: wornByOthers, unlocks: unlocks)
            state = catalog.isEmpty ? .empty : .loaded(catalog)
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
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
