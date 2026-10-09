import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("Monthly Review summary reuse")
struct MonthlyReviewCacheViewModelTests {
    @Test("Reopening the same facts revision restores the authored review without a Kyra request")
    func matchingSummaryCacheAvoidsAnotherProviderRequest() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let kyra = MockKyraRepository()
        await kyra.setNextReplyMessage("Your month had a steady rotation.")
        let cache = InMemoryMonthlyReviewSummaryCache()
        let first = makeViewModel(month: interval.start, shopping: MockShoppingRepository(), kyra: kyra, summaryCache: cache)
        await first.load()
        await first.generateAuthoredReview()
        guard case .generated(let authored) = first.authoredReviewState else {
            Issue.record("The first request should produce a summary")
            return
        }

        let reopened = makeViewModel(month: interval.start, shopping: MockShoppingRepository(), kyra: kyra, summaryCache: cache)
        await reopened.load()
        guard case .generated(let restored) = reopened.authoredReviewState else {
            Issue.record("A matching revision should be available immediately on reopen")
            return
        }
        #expect(restored.message == authored.message)
        #expect(restored.threadID == authored.threadID)
        #expect(restored.source == .cached)
        #expect((await kyra.sentMessages).count == 1)

        await reopened.refreshAuthoredReview()
        #expect((await kyra.sentMessages).count == 2)
        #expect((await kyra.sentThreadIDs).last == authored.threadID)
    }

    @Test("A cache read error blocks a possibly duplicate provider request")
    func unreadableCacheRequiresRetryBeforeKyra() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let kyra = MockKyraRepository()
        let viewModel = makeViewModel(
            month: interval.start,
            shopping: MockShoppingRepository(),
            kyra: kyra,
            summaryCache: UnreadableMonthlyReviewCache()
        )
        await viewModel.load()
        await viewModel.generateAuthoredReview()

        guard case .cacheUnavailable = viewModel.authoredReviewState else {
            Issue.record("An unreadable cache must not be treated as an empty cache")
            return
        }
        #expect(await kyra.sentMessages.isEmpty)
    }

    @Test("A local save retry does not call Kyra a second time")
    func failedCacheWriteCanRetryWithoutAnotherProviderCall() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let kyra = MockKyraRepository()
        let cache = FailFirstMonthlyReviewWriteCache()
        let viewModel = makeViewModel(month: interval.start, shopping: MockShoppingRepository(), kyra: kyra, summaryCache: cache)
        await viewModel.load()
        await viewModel.generateAuthoredReview()
        guard case .generated(let review) = viewModel.authoredReviewState else {
            Issue.record("A provider-authored response should remain visible when local caching fails")
            return
        }
        #expect(!review.cacheSaved)
        await viewModel.saveGeneratedReview()
        guard case .generated(let saved) = viewModel.authoredReviewState else {
            Issue.record("Retrying the local save should update the cache state")
            return
        }
        #expect(saved.cacheSaved)
        #expect((await kyra.sentMessages).count == 1)
    }
    private func makeViewModel(
        month: Date,
        shopping: MockShoppingRepository,
        kyra: KyraRepository = MockKyraRepository(),
        summaryCache: MonthlyReviewSummaryCaching = InMemoryMonthlyReviewSummaryCache(),
        closetItems: [ClosetItem] = [],
        outfitRepository: OutfitRepository = MockOutfitRepository(),
        currentOwnerID: @escaping @Sendable () async -> UUID? = { SampleData.userID }
    ) -> MonthlyReviewViewModel {
        MonthlyReviewViewModel(
            month: month,
            closetRepository: MockClosetRepository(items: closetItems),
            outfitRepository: outfitRepository,
            shoppingRepository: shopping,
            kyraRepository: kyra,
            summaryCache: summaryCache,
            currentOwnerID: currentOwnerID
        )
    }
}

private actor UnreadableMonthlyReviewCache: MonthlyReviewSummaryCaching {
    func cached(ownerID: UUID, monthKey: String, dataRevision: String) async throws -> MonthlyReviewSummary? {
        throw AstraError.network("Cache unavailable")
    }
    func store(_ summary: MonthlyReviewSummary) async throws {}
    func removeAll(ownerID: UUID) async throws {}
}

private actor FailFirstMonthlyReviewWriteCache: MonthlyReviewSummaryCaching {
    private var failNextWrite = true
    private var stored: MonthlyReviewSummary?

    func cached(ownerID: UUID, monthKey: String, dataRevision: String) async throws -> MonthlyReviewSummary? {
        guard let stored, stored.ownerID == ownerID, stored.monthKey == monthKey, stored.dataRevision == dataRevision else { return nil }
        return stored
    }

    func store(_ summary: MonthlyReviewSummary) async throws {
        if failNextWrite {
            failNextWrite = false
            throw AstraError.network("Disk temporarily unavailable")
        }
        stored = summary
    }

    func removeAll(ownerID: UUID) async throws {
        if stored?.ownerID == ownerID { stored = nil }
    }
}
