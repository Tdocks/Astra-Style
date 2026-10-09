import Foundation
import Testing
@testable import AstraStyle

@Suite("Shopping wishlist pagination")
struct LiveShoppingWishlistPaginationTests {
    @Test("Collects saved and purchased rows beyond the PostgREST cap")
    func collectsBothWishlistStatesWithoutGaps() async throws {
        let saved = makeRows(count: 1_001, purchased: false)
        let purchased = makeRows(count: 1_001, purchased: true)
        let fixture = WishlistPageFixture(rows: saved + purchased)

        let savedResult = try await LiveShoppingRepository.collectWishlistPages(pageSize: 500) { offset, limit in
            await fixture.fetchPage(purchased: false, offset: offset, limit: limit)
        }
        let purchasedResult = try await LiveShoppingRepository.collectWishlistPages(pageSize: 500) { offset, limit in
            await fixture.fetchPage(purchased: true, offset: offset, limit: limit)
        }

        #expect(savedResult == saved)
        #expect(purchasedResult == purchased)
        #expect(await fixture.requestedOffsets(purchased: false) == [0, 500, 1_000])
        #expect(await fixture.requestedOffsets(purchased: true) == [0, 500, 1_000])
    }

    @Test("Bounds candidate lookup chunks and preserves candidate ordering")
    func chunksCandidateIDsForPostgrestRequests() {
        let candidateIDs = (0..<1_001).map { _ in UUID() }
        let chunks = LiveShoppingRepository.candidateIDChunks(candidateIDs)

        #expect(chunks.map(\.count) == Array(repeating: 100, count: 10) + [1])
        #expect(chunks.flatMap { $0 } == candidateIDs)
        #expect(chunks.allSatisfy { !$0.isEmpty && $0.count <= 100 })
    }

    @Test("Rejects an invalid page size before requesting a page")
    func rejectsInvalidPageSize() async {
        do {
            _ = try await LiveShoppingRepository.collectWishlistPages(pageSize: 0) { _, _ in [] }
            Issue.record("A zero page size must be rejected")
        } catch let error as AstraError {
            #expect(error.category == .validation)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeRows(count: Int, purchased: Bool) -> [LiveShoppingRepository.WishlistRow] {
        (0..<count).map { index in
            LiveShoppingRepository.WishlistRow(
                id: UUID(),
                productCandidateID: UUID(),
                purchasedAt: purchased ? Date(timeIntervalSince1970: TimeInterval(index + 1)) : nil
            )
        }
    }
}

private actor WishlistPageFixture {
    private let rows: [LiveShoppingRepository.WishlistRow]
    private var offsets: [Bool: [Int]] = [:]

    init(rows: [LiveShoppingRepository.WishlistRow]) {
        self.rows = rows
    }

    func fetchPage(purchased: Bool, offset: Int, limit: Int) -> [LiveShoppingRepository.WishlistRow] {
        offsets[purchased, default: []].append(offset)
        let matchingRows = rows.filter { ($0.purchasedAt != nil) == purchased }
        guard offset < matchingRows.count else { return [] }
        return Array(matchingRows[offset..<min(offset + limit, matchingRows.count)])
    }

    func requestedOffsets(purchased: Bool) -> [Int] {
        offsets[purchased, default: []]
    }
}
