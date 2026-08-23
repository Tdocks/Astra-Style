//
//  DiscoverViewModel.swift
//  AstraStyle
//
//  ADR 0017: his lookbooks, other men's worn public looks, and an Unlocks
//  rail from product_candidates that fill HIS gaps. Home stays private.
//  Ranking is last_checked_at — never sponsored sort (P6-SHOP-09).
//

import Foundation
import Observation

@MainActor
@Observable
public final class DiscoverViewModel {
    public struct Catalog: Sendable {
        public var mine: [Outfit]
        public var wornByOthers: [Outfit]
        public var unlocks: [ProductCandidate]

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
            async let unlocksTask = shoppingRepository.fetchCuratedProducts(category: nil)

            let mine = try await mineTask.filter { !$0.isArchived }
            let wornByOthers = (try? await publicTask) ?? []
            let unlocks = (try? await unlocksTask) ?? []
            let catalog = Catalog(mine: mine, wornByOthers: wornByOthers, unlocks: unlocks)
            state = catalog.isEmpty ? .empty : .loaded(catalog)
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }
}
