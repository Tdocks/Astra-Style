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
