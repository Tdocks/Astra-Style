import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("Monthly Review prompt facts")
struct MonthlyReviewFactsTests {
    @Test("Kyra receives the monthly facts that appear on the review")
    func authoredPromptContainsRecordedItemsWearsAndPurchase() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let currentItem = closetItem(
            name: "Navy textured overshirt",
            createdAt: interval.start.addingTimeInterval(60),
            purchaseDate: interval.start.addingTimeInterval(60),
            pricePaid: 180
        )
        let oldItem = closetItem(
            name: "Olive field jacket",
            createdAt: interval.start.addingTimeInterval(-86_400),
            wearCount: 0
        )
        let outfitRepository = MockOutfitRepository()
        _ = try await outfitRepository.recordWear(
            outfitID: SampleData.heroOutfit.id,
            wornAt: interval.start.addingTimeInterval(120),
            occasion: nil,
            rating: nil,
            feedback: nil
        )
        let shopping = MockShoppingRepository()
        let purchase = candidate(name: "Purchased this month")
        await shopping.seedCandidate(purchase)
        await shopping.seedPurchase(candidateID: purchase.id, purchasedAt: interval.start.addingTimeInterval(90))
        await shopping.seedEvaluation(evaluation(candidateID: purchase.id, createdAt: interval.start, unlocked: 5))
        let kyra = MockKyraRepository()
        let viewModel = makeViewModel(
            month: interval.start,
            shopping: shopping,
            kyra: kyra,
            closetItems: [currentItem, oldItem],
            outfitRepository: outfitRepository
        )

        await viewModel.load()
        await viewModel.generateAuthoredReview()
        let prompt = try #require((await kyra.sentMessages).first?.text)
        #expect(prompt.contains("New closet items: 1 (Navy textured overshirt)"))
        #expect(prompt.contains("Looks marked worn: 1 across 1 outfits"))
        #expect(prompt.contains("Best evaluated purchase: Purchased this month, opening 5 new outfit combinations."))
        #expect(prompt.contains("Underused pieces: Olive field jacket."))
        #expect(prompt.count <= 2_000)
    }

    @Test("Elapsed month keeps archived additions and purchases added to the closet later")
    func elapsedMonthIncludesHistoricalClosetFacts() async throws {
        let currentStart = try #require(Calendar.current.dateInterval(of: .month, for: .now)?.start)
        let monthStart = try #require(Calendar.current.date(byAdding: .month, value: -1, to: currentStart))
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: monthStart))
        let archived = closetItem(
            name: "Archived September shirt",
            createdAt: interval.start.addingTimeInterval(60),
            purchaseDate: interval.start.addingTimeInterval(60),
            pricePaid: 20,
            archivedAt: interval.end.addingTimeInterval(60)
        )
        let addedLater = closetItem(
            name: "Late-added September shoes",
            createdAt: interval.end.addingTimeInterval(60),
            purchaseDate: interval.start.addingTimeInterval(120),
            pricePaid: 30
        )
        let shopping = MockShoppingRepository()
        let closet = MockClosetRepository(items: [archived, addedLater])
        let viewModel = MonthlyReviewViewModel(
            month: interval.start,
            closetRepository: closet,
            outfitRepository: MockOutfitRepository(),
            shoppingRepository: shopping,
            kyraRepository: MockKyraRepository(),
            currentOwnerID: { SampleData.userID }
        )

        await viewModel.load()

        guard case .loaded(let snapshot) = viewModel.state else {
            Issue.record("The elapsed month should load from historical closet facts")
            return
        }
        #expect(snapshot.newItemCount == 1)
        #expect(snapshot.newItemNames == ["Archived September shirt"])
        #expect(snapshot.trackedSpend.joined().contains("50"))
        #expect(await closet.monthlyVersatilityCaptureMonths == [currentStart])
        #expect(await closet.monthlyVersatilityHistoryReads == [interval.start])
    }

    @Test("Underuse counts repeated monthly wear events for each owned outfit piece")
    func monthlyWearEventsOverrideLifetimeWearCount() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: .now))
        let heroItemID = try #require(SampleData.heroOutfitItems().compactMap(\.closetItemID).first)
        let identifiedItem = ClosetItem(
            id: heroItemID,
            userID: SampleData.userID,
            name: "Worn repeatedly this month",
            category: .outerwear,
            wearCount: 0,
            createdAt: interval.start.addingTimeInterval(-86_400)
        )
        let outfits = MockOutfitRepository()
        for day in 1...3 {
            _ = try await outfits.recordWear(
                outfitID: SampleData.heroOutfit.id,
                wornAt: interval.start.addingTimeInterval(TimeInterval(day * 3_600)),
                occasion: nil,
                rating: nil,
                feedback: nil
            )
        }
        let viewModel = MonthlyReviewViewModel(
            month: interval.start,
            closetRepository: MockClosetRepository(items: [identifiedItem]),
            outfitRepository: outfits,
            shoppingRepository: MockShoppingRepository(),
            kyraRepository: MockKyraRepository(),
            currentOwnerID: { SampleData.userID }
        )

        await viewModel.load()

        guard case .loaded(let snapshot) = viewModel.state else {
            Issue.record("The current month should load its recorded wear history")
            return
        }
        #expect(snapshot.underusedItems.isEmpty)
    }

    @Test("The final millisecond belongs to the month but the exact end does not")
    func monthlyWearRangeUsesExactExclusiveEnd() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: .now))
        let outfits = MockOutfitRepository()
        _ = try await outfits.recordWear(
            outfitID: SampleData.heroOutfit.id,
            wornAt: interval.end.addingTimeInterval(-0.0005),
            occasion: nil,
            rating: nil,
            feedback: nil
        )
        _ = try await outfits.recordWear(
            outfitID: SampleData.heroOutfit.id,
            wornAt: interval.end,
            occasion: nil,
            rating: nil,
            feedback: nil
        )
        let viewModel = MonthlyReviewViewModel(
            month: interval.start,
            closetRepository: MockClosetRepository(items: []),
            outfitRepository: outfits,
            shoppingRepository: MockShoppingRepository(),
            kyraRepository: MockKyraRepository(),
            currentOwnerID: { SampleData.userID }
        )

        await viewModel.load()

        guard case .loaded(let snapshot) = viewModel.state else {
            Issue.record("The month should load its wear events")
            return
        }
        #expect(snapshot.wearCount == 1)
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
    private func closetItem(
        name: String,
        createdAt: Date,
        purchaseDate: Date? = nil,
        pricePaid: Decimal? = nil,
        wearCount: Int = 0,
        archivedAt: Date? = nil
    ) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: SampleData.userID,
            name: name,
            category: .outerwear,
            purchaseDate: purchaseDate,
            pricePaid: pricePaid,
            currency: "USD",
            wearCount: wearCount,
            archivedAt: archivedAt,
            createdAt: createdAt
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
