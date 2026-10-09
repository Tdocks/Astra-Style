import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("Profile shopping counts")
struct ProfileShoppingStatsViewModelTests {
    @Test("A failed count read is an error, never a successful zero")
    func failedReadDoesNotBecomeZeroCounts() async {
        let repository = MockShoppingRepository()
        await repository.setWishlistError(.network("Wishlist unavailable."))
        let viewModel = ProfileShoppingStatsViewModel(shoppingRepository: repository)

        await viewModel.onAppear()

        #expect(viewModel.state == .failed("Wishlist unavailable."))
    }

    @Test("A successful empty response is shown as a genuine zero")
    func successfulEmptyCountsAreZero() async {
        let viewModel = ProfileShoppingStatsViewModel(shoppingRepository: MockShoppingRepository())

        await viewModel.onAppear()

        #expect(viewModel.state == .loaded(savedCount: 0, purchasedCount: 0))
    }

    @Test("Retry replaces a visible failure with current counts")
    func retryLoadsCountsAfterFailure() async throws {
        let repository = MockShoppingRepository()
        await repository.setPurchasedError(.network("Purchases unavailable."))
        let viewModel = ProfileShoppingStatsViewModel(shoppingRepository: repository)
        await viewModel.onAppear()
        #expect(viewModel.state == .failed("Purchases unavailable."))

        await repository.setPurchasedError(nil)
        let saved = try await repository.extractProduct(from: #require(URL(string: "https://example.com/saved-piece")))
        let purchased = try await repository.extractProduct(from: #require(URL(string: "https://example.com/purchased-piece")))
        try await repository.addToWishlist(candidateID: saved.id)
        try await repository.markPurchased(candidateID: purchased.id)

        await viewModel.retry()

        #expect(viewModel.state == .loaded(savedCount: 1, purchasedCount: 1))
    }
}
