//
//  ShopViewModelTests.swift
//  AstraStyleTests
//

import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("Shop tab reads curated catalog, not Unlocks")
struct ShopViewModelTests {
    @Test("Recent evaluations appear as explicitly dated history")
    func loadsRecentDecisionHistory() async throws {
        let shopping = MockShoppingRepository()
        let candidate = try await shopping.extractProduct(from: #require(URL(string: "https://example.com/trench")))
        _ = try await shopping.evaluateProduct(candidateID: candidate.id)

        let model = ShopViewModel(shoppingRepository: shopping)
        await model.onAppear()
        #expect(model.recentDecisions.count == 1)
        #expect(model.recentDecisions.first?.candidate?.id == candidate.id)
        #expect(model.recentDecisions.first?.evaluation.productCandidateID == candidate.id)
    }

    @Test("Loaded catalog comes from fetchCuratedProducts")
    func loadsCurated() async {
        let shopping = MockShoppingRepository()
        let model = ShopViewModel(shoppingRepository: shopping)
        await model.onAppear()
        guard case .loaded(let items) = model.state else {
            Issue.record("expected loaded catalog")
            return
        }
        #expect(!items.isEmpty)
    }
}
