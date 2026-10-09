//
//  ShopViewModel.swift
//  AstraStyle
//
//  Curated `product_candidates` for the Shop tab. Discover Unlocks stays
//  on fetchUnlocks (ADR 0020). Sponsored is a label, never a sort key.
//

import Foundation
import Observation

@MainActor
@Observable
public final class ShopViewModel {
    public enum ViewState: Sendable {
        case loading
        case loaded([ProductCandidate])
        case empty
        case failed(AstraError)
    }

    public private(set) var state: ViewState = .loading
    public private(set) var recentDecisions: [ProductDecisionSnapshot] = []

    private let shoppingRepository: ShoppingRepository

    public init(shoppingRepository: ShoppingRepository) {
        self.shoppingRepository = shoppingRepository
    }

    public func onAppear() async {
        guard case .loading = state else { return }
        await load()
    }

    public func refresh() async {
        await load()
    }

    public func historicalDecisionRoute(candidateID: UUID) -> ShopRoute {
        .historicalDecision(candidateID: candidateID)
    }

    private func load() async {
        recentDecisions = (try? await shoppingRepository.fetchRecentDecisions(limit: 20))?
            .filter { $0.candidate != nil } ?? []
        do {
            let items = try await shoppingRepository.fetchCuratedProducts(category: nil)
            state = items.isEmpty ? .empty : .loaded(items)
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }
}
