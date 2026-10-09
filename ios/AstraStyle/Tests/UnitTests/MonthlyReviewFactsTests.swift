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
        wearCount: Int = 0
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
