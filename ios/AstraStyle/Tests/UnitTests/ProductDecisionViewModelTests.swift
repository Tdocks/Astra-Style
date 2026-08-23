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
        #expect(labels == ["candidate", "evaluation"])
        #expect(!labels.contains("sponsored"))
        #expect(!labels.contains("alternatives"))
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
