//
//  ProductDecisionViewModelTests.swift
//  AstraStyleTests
//
//  Wave D: paste-a-link don't-buy. The page shows evaluate's verdict and
//  unlocks; buy/consider may reopen his URL; skip/wait may not; sponsored
//  never becomes a sort key because this page has no alternatives list.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Product decision page")
@MainActor
struct ProductDecisionViewModelTests {

    @Test("Evaluate then show unlocks and reasoning")
    func loadedShowsEvaluation() async throws {
        let shopping = MockShoppingRepository()
        let url = try #require(URL(string: "https://example.com/navy-blazer"))
        let candidate = try await shopping.extractProduct(from: url)
        await shopping.setEvaluationOverride(
            ProductEvaluation(
                userID: SampleData.userID,
                productCandidateID: candidate.id,
                compatibilityScore: 72,
                redundancyScore: 20,
                outfitsUnlocked: 4,
                verdict: .buy,
                reasoning: "it opens up 4 new outfits"
            )
        )

        let model = ProductDecisionViewModel(candidateID: candidate.id, shoppingRepository: shopping)
        await model.onAppear()

        guard case .loaded(let loaded) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(loaded.evaluation.outfitsUnlocked == 4)
        #expect(loaded.evaluation.reasoning.contains("4 new outfits"))
        #expect(loaded.evaluation.verdict == .buy)
        #expect(loaded.candidate?.canonicalURL == url)
        #expect(model.canOpenSourceURL)
        #expect(model.sourceURL == url)
    }

    @Test("An empty closet still shows the server's sentence, not a fake zero-unlock as incompatibility")
    func emptyClosetKeepsServerReasoning() async throws {
        let shopping = MockShoppingRepository()
        let url = try #require(URL(string: "https://example.com/first-shoe"))
        let candidate = try await shopping.extractProduct(from: url)
        await shopping.setEvaluationOverride(
            ProductEvaluation(
                userID: SampleData.userID,
                productCandidateID: candidate.id,
                compatibilityScore: 0,
                redundancyScore: 0,
                outfitsUnlocked: 0,
                verdict: .consider,
                reasoning: "there was nothing to pair this against"
            )
        )

        let model = ProductDecisionViewModel(candidateID: candidate.id, shoppingRepository: shopping)
        await model.onAppear()

        guard case .loaded(let loaded) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(loaded.evaluation.outfitsUnlocked == 0)
        #expect(loaded.evaluation.reasoning.contains("nothing to pair"))
    }

    @Test("Skip and wait do not reopen the retailer")
    func skipDoesNotOpenSource() async throws {
        let shopping = MockShoppingRepository()
        let url = try #require(URL(string: "https://example.com/second-bomber"))
        let candidate = try await shopping.extractProduct(from: url)
        await shopping.setEvaluationOverride(
            ProductEvaluation(
                userID: SampleData.userID,
                productCandidateID: candidate.id,
                compatibilityScore: 40,
                redundancyScore: 90,
                outfitsUnlocked: 0,
                verdict: .skip,
                reasoning: "you already own something very close to this"
            )
        )

        let model = ProductDecisionViewModel(candidateID: candidate.id, shoppingRepository: shopping)
        await model.onAppear()

        #expect(!model.canOpenSourceURL)
        #expect(model.sourceURL == nil)
        #expect(model.shareText == "Astra said skip: \(candidate.name)")
    }

    @Test("The loaded page carries candidate and evaluation only — no sponsored alternatives to sort")
    func noSponsoredAlternativesPayload() async throws {
        let shopping = MockShoppingRepository()
        let url = try #require(URL(string: "https://example.com/chino"))
        let candidate = try await shopping.extractProduct(from: url)

        let model = ProductDecisionViewModel(candidateID: candidate.id, shoppingRepository: shopping)
        await model.onAppear()

        guard case .loaded(let loaded) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        let mirror = Mirror(reflecting: loaded)
        let labels = Set(mirror.children.compactMap(\.label))
        #expect(labels == ["candidate", "evaluation", "isCachedSnapshot"])
        #expect(!labels.contains("sponsored"))
        #expect(!labels.contains("alternatives"))
    }

    @Test("Offline opening shows the saved verdict with an explicit stale snapshot marker")
    func opensCachedEvaluationOffline() async throws {
        let shopping = MockShoppingRepository()
        let url = try #require(URL(string: "https://example.com/chino"))
        let candidate = try await shopping.extractProduct(from: url)
        let saved = try await shopping.evaluateProduct(candidateID: candidate.id)
        await shopping.setEvaluateError(AstraError.network("offline"))

        let model = ProductDecisionViewModel(candidateID: candidate.id, shoppingRepository: shopping)
        await model.onAppear()
        guard case .loaded(let loaded) = model.state else {
            Issue.record("expected a cached evaluation, got \(model.state)")
            return
        }
        #expect(loaded.isCachedSnapshot)
        #expect(loaded.evaluation == saved)
        #expect(loaded.candidate?.id == candidate.id)
    }

    @Test("Opening recent history reads the saved snapshot and scores only after explicit refresh")
    func historicalEntryRequiresOptInToRescore() async throws {
        let shopping = MockShoppingRepository()
        let url = try #require(URL(string: "https://example.com/history-coat"))
        let candidate = try await shopping.extractProduct(from: url)
        let saved = try await shopping.evaluateProduct(candidateID: candidate.id)
        let callsBeforeOpeningHistory = await shopping.evaluationCalls

        let model = ProductDecisionViewModel(
            candidateID: candidate.id,
            shoppingRepository: shopping,
            startsInHistoricalMode: true
        )
        await model.onAppear()

        let callsAfterOpeningHistory = await shopping.evaluationCalls
        #expect(callsAfterOpeningHistory == callsBeforeOpeningHistory)
        guard case .loaded(let historical) = model.state else {
            Issue.record("expected saved historical decision, got \(model.state)")
            return
        }
        #expect(historical.isCachedSnapshot)
        #expect(historical.evaluation == saved)

        await model.refreshEvaluation()
        let callsAfterExplicitRefresh = await shopping.evaluationCalls
        #expect(callsAfterExplicitRefresh == callsBeforeOpeningHistory + 1)
        guard case .loaded(let refreshed) = model.state else {
            Issue.record("expected fresh decision after explicit refresh, got \(model.state)")
            return
        }
        #expect(!refreshed.isCachedSnapshot)
    }

    @Test("Unavailable history does not evaluate until the user chooses evaluate")
    func missingHistoryRequiresExplicitEvaluation() async throws {
        let shopping = MockShoppingRepository()
        let url = try #require(URL(string: "https://example.com/not-yet-evaluated"))
        let candidate = try await shopping.extractProduct(from: url)
        let model = ProductDecisionViewModel(
            candidateID: candidate.id,
            shoppingRepository: shopping,
            startsInHistoricalMode: true
        )
        await model.onAppear()
        #expect(await shopping.evaluationCalls == 0)
        guard case .failed = model.state else {
            Issue.record("expected missing-snapshot state")
            return
        }
        await model.refreshEvaluation()
        #expect(await shopping.evaluationCalls == 1)
    }

    @Test("Recent decision rows route to the historical destination")
    func recentDecisionRouteIsHistorical() async throws {
        let shopping = MockShoppingRepository()
        let candidate = try await shopping.extractProduct(from: #require(URL(string: "https://example.com/route-coat")))
        let model = ShopViewModel(shoppingRepository: shopping)
        #expect(model.historicalDecisionRoute(candidateID: candidate.id) == .historicalDecision(candidateID: candidate.id))
    }

    @Test("A traffic throttle never falls back to a stale verdict or opens a paywall")
    func rateLimitedEvaluationDoesNotUseCache() async throws {
        let shopping = MockShoppingRepository()
        let url = try #require(URL(string: "https://example.com/coat"))
        let candidate = try await shopping.extractProduct(from: url)
        _ = try await shopping.evaluateProduct(candidateID: candidate.id)
        await shopping.setEvaluateError(AstraError.rateLimited())

        let model = ProductDecisionViewModel(candidateID: candidate.id, shoppingRepository: shopping)
        await model.onAppear()
        guard case .failed(let error) = model.state else {
            Issue.record("expected rate-limit state, got \(model.state)")
            return
        }
        #expect(error.category == .rateLimited)
        #expect(model.pendingPaywall == nil)
    }

    @Test("A typed product trial limit remains an inline error")
    func typedQuotaDoesNotPresentPaywall() async throws {
        let shopping = MockShoppingRepository()
        let url = try #require(URL(string: "https://example.com/coat"))
        let candidate = try await shopping.extractProduct(from: url)
        await shopping.setEvaluateError(AstraError(
            category: .subscriptionLimitReached,
            message: "Evaluation allowance reached.",
            quotaDetails: AstraQuotaDetails(limit: "paste_product_evaluation_trial", limitCount: 1, remaining: 0, resetsAt: nil)
        ))
        let model = ProductDecisionViewModel(candidateID: candidate.id, shoppingRepository: shopping)
        await model.onAppear()
        #expect(model.pendingPaywall == nil)
    }

    @Test("Paste product trial quota is shown inline without a paywall")
    func pasteTrialQuotaDoesNotUpsell() async throws {
        let shopping = MockShoppingRepository()
        await shopping.setExtractError(AstraError(
            category: .subscriptionLimitReached,
            message: "Your product evaluation trial has been used.",
            quotaDetails: AstraQuotaDetails(limit: "paste_product_evaluation_trial", limitCount: 1, remaining: 0, resetsAt: nil)
        ))
        let model = ProductLinkPasteViewModel(shoppingRepository: shopping)
        let candidateID = await model.extract(from: "https://example.com/coat")
        #expect(candidateID == nil)
        #expect(model.pendingPaywall == nil)
        #expect(model.submitError?.category == .subscriptionLimitReached)
    }

    @Test("Server failures never fall back to an old decision")
    func serverFailureDoesNotUseCache() async throws {
        let shopping = MockShoppingRepository()
        let url = try #require(URL(string: "https://example.com/boots"))
        let candidate = try await shopping.extractProduct(from: url)
        _ = try await shopping.evaluateProduct(candidateID: candidate.id)
        await shopping.setEvaluateError(AstraError.server("evaluation failed"))

        let model = ProductDecisionViewModel(candidateID: candidate.id, shoppingRepository: shopping)
        await model.onAppear()
        guard case .failed(let error) = model.state else {
            Issue.record("expected server failure state, got \(model.state)")
            return
        }
        #expect(error.category == .server)
    }

    @Test("Save for later then mark purchased updates state")
    func wishlistThenPurchase() async throws {
        let shopping = MockShoppingRepository()
        let url = try #require(URL(string: "https://example.com/navy-knit"))
        let candidate = try await shopping.extractProduct(from: url)
        let model = ProductDecisionViewModel(candidateID: candidate.id, shoppingRepository: shopping)
        await model.onAppear()
        #expect(!model.isOnWishlist)
        #expect(!model.isPurchased)

        await model.toggleWishlist()
        #expect(model.isOnWishlist)
        #expect(!model.isPurchased)

        await model.markPurchased()
        #expect(!model.isOnWishlist)
        #expect(model.isPurchased)
        let bought = try await shopping.fetchPurchased()
        #expect(bought.map(\.id) == [candidate.id])
    }
}

@Suite("Product link paste")
@MainActor
struct ProductLinkPasteViewModelTests {

    @Test("A valid URL extracts to a candidate id")
    func extractSucceeds() async throws {
        let shopping = MockShoppingRepository()
        let model = ProductLinkPasteViewModel(shoppingRepository: shopping)
        let id = await model.extract(from: "https://example.com/products/navy-blazer")
        #expect(id != nil)
        #expect(model.submitError == nil)
    }

    @Test("Repeated submit while extraction awaits does not create a second request")
    func concurrentSubmitIsIgnored() async throws {
        let shopping = MockShoppingRepository()
        await shopping.pauseExtraction()
        let model = ProductLinkPasteViewModel(shoppingRepository: shopping)
        let first = Task { await model.extract(from: "https://example.com/products/navy-blazer") }
        for _ in 0..<1_000 {
            if await shopping.extractionCalls == 1 { break }
            await Task.yield()
        }
        guard await shopping.extractionCalls == 1 else {
            await shopping.resumeExtraction()
            _ = await first.value
            Issue.record("The first extraction did not reach its repository")
            return
        }
        let second = await model.extract(from: "https://example.com/products/other")
        let calls = await shopping.extractionCalls
        let submitting = model.isSubmitting
        await shopping.resumeExtraction()
        let firstID = await first.value
        #expect(calls == 1)
        #expect(submitting)
        #expect(second == nil)
        #expect(firstID != nil)
        #expect(!model.isSubmitting)
    }

    @Test("A non-URL fails loud instead of guessing a retailer")
    func invalidURLFails() async {
        let shopping = MockShoppingRepository()
        let model = ProductLinkPasteViewModel(shoppingRepository: shopping)
        let id = await model.extract(from: "not a link")
        #expect(id == nil)
        #expect(model.submitError?.category == .validation)
    }

    @Test("Extract errors surface rather than inventing a product")
    func extractErrorSurfaces() async {
        let shopping = MockShoppingRepository()
        await shopping.setExtractError(AstraError.provider("Could not read that page."))
        let model = ProductLinkPasteViewModel(shoppingRepository: shopping)
        let id = await model.extract(from: "https://example.com/products/unknown")
        #expect(id == nil)
        #expect(model.submitError?.category == .provider)
    }
}
