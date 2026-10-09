import Foundation
import Testing
@testable import AstraStyle

@Suite("Shopping purchase pagination")
struct LiveShoppingPurchasePaginationTests {
    @Test("Fetches beyond the PostgREST row cap without gaps or duplicates")
    func fetchesEveryPage() async throws {
        let purchases = (0..<1_001).map { index in
            ProductPurchase(
                productCandidateID: UUID(),
                purchasedAt: Date(timeIntervalSince1970: TimeInterval(1_800_000_000 - index))
            )
        }
        let fixture = PurchasePageFixture(purchases: purchases)

        let result = try await LiveShoppingRepository.collectPurchasePages(pageSize: 500) { offset, limit in
            await fixture.fetchPage(offset: offset, limit: limit)
        }

        #expect(result == purchases)
        #expect(await fixture.requestedOffsets() == [0, 500, 1_000])
    }

    @Test("Rejects an invalid page size before requesting a page")
    func rejectsInvalidPageSize() async {
        do {
            _ = try await LiveShoppingRepository.collectPurchasePages(pageSize: 0) { _, _ in [] }
            Issue.record("A zero page size must be rejected")
        } catch let error as AstraError {
            #expect(error.category == .validation)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private actor PurchasePageFixture {
    private let purchases: [ProductPurchase]
    private var offsets: [Int] = []

    init(purchases: [ProductPurchase]) {
        self.purchases = purchases
    }

    func fetchPage(offset: Int, limit: Int) -> [ProductPurchase] {
        offsets.append(offset)
        guard offset < purchases.count else { return [] }
        return Array(purchases[offset..<min(offset + limit, purchases.count)])
    }

    func requestedOffsets() -> [Int] { offsets }
}
