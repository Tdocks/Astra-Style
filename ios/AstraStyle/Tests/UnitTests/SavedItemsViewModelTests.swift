//
//  SavedItemsViewModelTests.swift
//  AstraStyleTests
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Profile saved list")
@MainActor
struct SavedItemsViewModelTests {

    @Test("Empty wishlist shows empty state")
    func emptyWishlist() async {
        let model = SavedItemsViewModel(shoppingRepository: EmptySavedShoppingStub())
        await model.onAppear()
        guard case .empty = model.state else {
            Issue.record("expected .empty, got \(model.state)")
            return
        }
    }

    @Test("Saved items load into list state")
    func loadsSavedItems() async throws {
        let item = ProductCandidate(
            id: UUID(),
            canonicalURL: URL(string: "https://example.com/shoe")!,
            retailer: "Example",
            name: "Oxford",
            category: .shoes
        )
        let model = SavedItemsViewModel(
            shoppingRepository: SavedShoppingStub(items: [item])
        )
        await model.onAppear()
        guard case .loaded(let items) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(items.map(\.id) == [item.id])
    }
}

private actor EmptySavedShoppingStub: ShoppingRepository {
    func extractProduct(from url: URL) async throws -> ProductCandidate { throw AstraError.unimplemented("") }
    func evaluateProduct(candidateID: UUID) async throws -> ProductEvaluation { throw AstraError.unimplemented("") }
    func fetchProductCandidate(id: UUID) async throws -> ProductCandidate { throw AstraError.unimplemented("") }
    func fetchCuratedProducts(category: ClothingCategory?) async throws -> [ProductCandidate] { [] }
    func fetchUnlocks() async throws -> [ProductUnlock] { [] }
    func fetchWishlist() async throws -> [ProductCandidate] { [] }
    func fetchPurchased() async throws -> [ProductCandidate] { [] }
    func addToWishlist(candidateID: UUID) async throws {}
    func removeFromWishlist(candidateID: UUID) async throws {}
    func markPurchased(candidateID: UUID) async throws {}
}

private actor SavedShoppingStub: ShoppingRepository {
    let items: [ProductCandidate]
    init(items: [ProductCandidate]) { self.items = items }
    func extractProduct(from url: URL) async throws -> ProductCandidate { throw AstraError.unimplemented("") }
    func evaluateProduct(candidateID: UUID) async throws -> ProductEvaluation { throw AstraError.unimplemented("") }
    func fetchProductCandidate(id: UUID) async throws -> ProductCandidate { throw AstraError.unimplemented("") }
    func fetchCuratedProducts(category: ClothingCategory?) async throws -> [ProductCandidate] { [] }
    func fetchUnlocks() async throws -> [ProductUnlock] { [] }
    func fetchWishlist() async throws -> [ProductCandidate] { items }
    func fetchPurchased() async throws -> [ProductCandidate] { [] }
    func addToWishlist(candidateID: UUID) async throws {}
    func removeFromWishlist(candidateID: UUID) async throws {}
    func markPurchased(candidateID: UUID) async throws {}
}
