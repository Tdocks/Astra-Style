import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("Kyra-authored Monthly Review")
struct MonthlyReviewAuthoredReviewTests {
    @Test("Kyra authors the review only after an explicit request and the summary is reusable")
    func authoredReviewUsesKyraAndDoesNotGenerateOnLoad() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let kyra = MockKyraRepository()
        await kyra.setNextReplyMessage("Your rotation stayed steady; try the overlooked navy overshirt next month.")
        let viewModel = makeViewModel(month: interval.start, shopping: MockShoppingRepository(), kyra: kyra)

        await viewModel.load()
        #expect(await kyra.sentMessages.isEmpty)
        await viewModel.generateAuthoredReview()

        guard case .generated(let review) = viewModel.authoredReviewState else {
            Issue.record("A successful Kyra response should produce the authored review state")
            return
        }
        #expect(review.message == "Your rotation stayed steady; try the overlooked navy overshirt next month.")
        let sent = await kyra.sentMessages
        #expect(sent.count == 1)
        #expect(sent[0].text.contains("Write my Monthly Review"))
        #expect(sent[0].text.contains("Do not invent measurements, purchases, outfit counts"))

        await viewModel.generateAuthoredReview()
        #expect((await kyra.sentMessages).count == 1)
    }
    @Test("Provider failure stays visible and explicit retry can complete")
    func authoredReviewFailureCanRetry() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let kyra = MockKyraRepository()
        await kyra.failNextSend(with: .provider("Kyra is temporarily unavailable."))
        let viewModel = makeViewModel(month: interval.start, shopping: MockShoppingRepository(), kyra: kyra)

        await viewModel.load()
        await viewModel.generateAuthoredReview()
        guard case .failed(let message, _, let rateLimited) = viewModel.authoredReviewState else {
            Issue.record("Provider failure must remain visible and retryable")
            return
        }
        #expect(message == "Kyra is temporarily unavailable.")
        #expect(!rateLimited)
        #expect((await kyra.sentMessages).count == 1)

        await viewModel.generateAuthoredReview()
        guard case .generated = viewModel.authoredReviewState else {
            Issue.record("An explicit retry should show the provider's successful response")
            return
        }
        #expect((await kyra.sentMessages).count == 2)
    }

    @Test("Kyra's daily limit is exposed as an upgrade state, not an immediate retry")
    func authoredReviewRateLimitDoesNotOfferRetryableFailure() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let kyra = MockKyraRepository()
        await kyra.failNextSend(with: .rateLimited("Daily Kyra limit reached."))
        let viewModel = makeViewModel(month: interval.start, shopping: MockShoppingRepository(), kyra: kyra)

        await viewModel.load()
        await viewModel.generateAuthoredReview()
        guard case .failed(let message, _, let rateLimited) = viewModel.authoredReviewState else {
            Issue.record("Daily limit should be shown as a distinct state")
            return
        }
        #expect(message == "Daily Kyra limit reached.")
        #expect(rateLimited)
        #expect((await kyra.sentMessages).count == 1)
    }

    @Test("A review loaded for the previous account is never sent to Kyra")
    func accountSwitchClearsMonthlyFactsBeforeProviderCall() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let owner = MonthlyReviewOwnerFixture(id: SampleData.userID)
        let kyra = MockKyraRepository()
        let viewModel = makeViewModel(
            month: interval.start,
            shopping: MockShoppingRepository(),
            kyra: kyra,
            currentOwnerID: { await owner.current() }
        )

        await viewModel.load()
        await owner.switchTo(UUID())
        await viewModel.generateAuthoredReview()

        guard case .failed(let message) = viewModel.state else {
            Issue.record("The old account's Monthly Review should be cleared after account switching")
            return
        }
        #expect(message.contains("Your account changed"))
        #expect(await kyra.sentMessages.isEmpty)
    }

    @Test("A structured Kyra provider fallback is not presented as a completed review")
    func authoredReviewRejectsProviderFallbackAndRetriesSameThread() async throws {
        let interval = try #require(Calendar.current.dateInterval(of: .month, for: Date.now))
        let kyra = MockKyraRepository()
        await kyra.setNextFallbackReason("provider_error")
        let viewModel = makeViewModel(month: interval.start, shopping: MockShoppingRepository(), kyra: kyra)

        await viewModel.load()
        await viewModel.generateAuthoredReview()
        guard case .failed(_, let retryThreadID, let rateLimited) = viewModel.authoredReviewState,
              let retryThreadID else {
            Issue.record("A structured provider fallback must remain a retryable failure")
            return
        }
        #expect(!rateLimited)
        await kyra.setNextReplyMessage("A fresh provider-authored review using only recorded facts.")
        await viewModel.generateAuthoredReview()
        guard case .generated(let review) = viewModel.authoredReviewState else {
            Issue.record("A successful retry should replace the failed fallback state")
            return
        }
        #expect(review.message == "A fresh provider-authored review using only recorded facts.")
        #expect(review.threadID == retryThreadID)
        #expect((await kyra.sentThreadIDs).count == 2)
        #expect((await kyra.sentThreadIDs)[1] == retryThreadID)
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

private actor MonthlyReviewOwnerFixture {
    private var id: UUID

    init(id: UUID) { self.id = id }

    func current() -> UUID { id }

    func switchTo(_ id: UUID) { self.id = id }
}
