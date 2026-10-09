import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("Monthly review purchase attribution")
struct MonthlyReviewViewModelTests {
    @Test("A prior-month purchase is excluded even if it is evaluated this month")
    func purchaseMonthControlsAttribution() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let candidate = candidate(name: "Last month's coat")
        let evaluation = evaluation(candidateID: candidate.id, createdAt: interval.start.addingTimeInterval(3_600), unlocked: 8)
        let snapshot = await snapshot(
            month: interval.start,
            purchases: [(candidate, interval.start.addingTimeInterval(-1))],
            evaluations: [evaluation]
        )

        #expect(snapshot?.bestPurchase == nil)
        #expect(snapshot?.bestPurchaseOutfitsUnlocked == nil)
    }

    @Test("A current-month purchase uses an evaluation from before the month")
    func olderEvaluationStillAttributableToCurrentPurchase() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let candidate = candidate(name: "Purchased this month")
        let evaluation = evaluation(candidateID: candidate.id, createdAt: interval.start.addingTimeInterval(-86_400), unlocked: 6)
        let snapshot = await snapshot(
            month: interval.start,
            purchases: [(candidate, interval.start.addingTimeInterval(60))],
            evaluations: [evaluation]
        )

        #expect(snapshot?.bestPurchase == candidate.name)
        #expect(snapshot?.bestPurchaseOutfitsUnlocked == 6)
    }

    @Test("The latest evaluation wins even when its score is lower")
    func latestEvaluationWinsOverOlderHigherScore() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let candidate = candidate(name: "Re-evaluated purchase")
        let old = evaluation(candidateID: candidate.id, createdAt: interval.start.addingTimeInterval(-172_800), unlocked: 12)
        let latest = evaluation(candidateID: candidate.id, createdAt: interval.start.addingTimeInterval(-86_400), unlocked: 2)
        let snapshot = await snapshot(
            month: interval.start,
            purchases: [(candidate, interval.start.addingTimeInterval(60))],
            evaluations: [old, latest]
        )

        #expect(snapshot?.bestPurchase == candidate.name)
        #expect(snapshot?.bestPurchaseOutfitsUnlocked == 2)
    }

    @Test("A future evaluation cannot rewrite an elapsed purchase review")
    func evaluationAfterReviewMonthIsExcluded() async throws {
        let currentStart = try #require(Calendar.current.dateInterval(of: .month, for: .now)?.start)
        let monthStart = try #require(Calendar.current.date(byAdding: .month, value: -1, to: currentStart))
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: monthStart))
        let candidate = candidate(name: "September purchase")
        let futureEvaluation = evaluation(
            candidateID: candidate.id,
            createdAt: interval.end.addingTimeInterval(60),
            unlocked: 9
        )
        let snapshot = await snapshot(
            month: interval.start,
            purchases: [(candidate, interval.start.addingTimeInterval(60))],
            evaluations: [futureEvaluation]
        )

        #expect(snapshot?.bestPurchase == nil)
        #expect(snapshot?.bestPurchaseOutfitsUnlocked == nil)
    }

    @Test("The month start is included and next month start is excluded")
    func purchaseRangeUsesHalfOpenMonthBoundary() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let boundaryPurchase = candidate(name: "Boundary purchase")
        let nextMonthPurchase = candidate(name: "Next month's purchase")
        let evaluations = [
            evaluation(candidateID: boundaryPurchase.id, createdAt: interval.start.addingTimeInterval(-1), unlocked: 3),
            evaluation(candidateID: nextMonthPurchase.id, createdAt: interval.start.addingTimeInterval(-1), unlocked: 9)
        ]
        let snapshot = await snapshot(
            month: interval.start,
            purchases: [
                (boundaryPurchase, interval.start),
                (nextMonthPurchase, interval.end)
            ],
            evaluations: evaluations
        )

        #expect(snapshot?.bestPurchase == boundaryPurchase.name)
        #expect(snapshot?.bestPurchaseOutfitsUnlocked == 3)
    }

    @Test("A purchase history failure is surfaced as a retryable review error")
    func purchaseHistoryFailureDoesNotLookLikeNoPurchases() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let shopping = MockShoppingRepository()
        await shopping.setPurchaseHistoryError(.network("Purchase history is temporarily unavailable."))

        let viewModel = makeViewModel(month: interval.start, shopping: shopping)
        await viewModel.load()

        guard case .failed(let message) = viewModel.state else {
            Issue.record("A failed purchase-history request must not produce an empty review")
            return
        }
        #expect(message == "Purchase history is temporarily unavailable.")
    }

    @Test("An evaluation history failure is surfaced instead of hiding the best purchase")
    func evaluationHistoryFailureDoesNotLookLikeNoEvaluations() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let shopping = MockShoppingRepository()
        let product = candidate(name: "Purchased this month")
        await shopping.seedCandidate(product)
        await shopping.seedPurchase(candidateID: product.id, purchasedAt: interval.start.addingTimeInterval(60))
        await shopping.setEvaluationHistoryError(.network("Evaluation history is temporarily unavailable."))

        let viewModel = makeViewModel(month: interval.start, shopping: shopping)
        await viewModel.load()

        guard case .failed(let message) = viewModel.state else {
            Issue.record("A failed evaluation-history request must not imply there was no evaluated purchase")
            return
        }
        #expect(message == "Evaluation history is temporarily unavailable.")
    }
    private func snapshot(
        month: Date,
        purchases: [(ProductCandidate, Date)],
        evaluations: [ProductEvaluation]
    ) async -> MonthlyReviewSnapshot? {
        let shopping = MockShoppingRepository()
        for (product, purchasedAt) in purchases {
            await shopping.seedCandidate(product)
            await shopping.seedPurchase(candidateID: product.id, purchasedAt: purchasedAt)
        }
        for evaluation in evaluations { await shopping.seedEvaluation(evaluation) }
        let viewModel = makeViewModel(month: month, shopping: shopping)
        await viewModel.load()
        guard case .loaded(let result) = viewModel.state else {
            Issue.record("Monthly review failed to load in the in-memory fixture")
            return nil
        }
        return result
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
    private func candidate(name: String) -> ProductCandidate {
        ProductCandidate(
            id: UUID(),
            canonicalURL: URL(string: "https://example.com/\(UUID().uuidString)") ?? URL(fileURLWithPath: "/"),
            retailer: "Example",
            name: name,
            category: .top
        )
    }

    private func evaluation(candidateID: UUID, createdAt: Date, unlocked: Int) -> ProductEvaluation {
        ProductEvaluation(
            userID: SampleData.userID,
            productCandidateID: candidateID,
            compatibilityScore: 80,
            redundancyScore: 10,
            outfitsUnlocked: unlocked,
            verdict: .consider,
            reasoning: "Test evaluation",
            createdAt: createdAt
        )
    }
}
