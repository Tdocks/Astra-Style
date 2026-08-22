//
//  ProductDecisionViewModel.swift
//  AstraStyle
//
//  Wave D: one pasted URL becomes a skip / wait / buy plus a real unlock
//  count. Sponsorship never enters this type — evaluate already forbids it
//  as an input, and this page does not rank alternatives.
//

import Foundation
import Observation

@MainActor
@Observable
public final class ProductDecisionViewModel {
    public struct Loaded: Sendable {
        public var candidate: ProductCandidate?
        public var evaluation: ProductEvaluation
    }

    public enum ViewState: Sendable {
        case loading
        case loaded(Loaded)
        case failed(AstraError)
    }

    public private(set) var state: ViewState = .loading

    private let candidateID: UUID
    private let shoppingRepository: ShoppingRepository

    public init(candidateID: UUID, shoppingRepository: ShoppingRepository) {
        self.candidateID = candidateID
        self.shoppingRepository = shoppingRepository
    }

    public func onAppear() async {
        guard case .loading = state else { return }
        await load()
    }

    public func retry() async {
        state = .loading
        await load()
    }

    /// Buy / consider may reopen the URL he pasted. Skip / wait must not
    /// push a catalog, and they do not get a retailer button.
    public var canOpenSourceURL: Bool {
        guard case .loaded(let loaded) = state, loaded.candidate != nil else { return false }
        switch loaded.evaluation.verdict {
        case .buy, .consider:
            return true
        case .waitForSale, .skip:
            return false
        }
    }

    public var sourceURL: URL? {
        guard canOpenSourceURL, case .loaded(let loaded) = state else { return nil }
        return loaded.candidate?.canonicalURL
    }

    private func load() async {
        do {
            let evaluation = try await shoppingRepository.evaluateProduct(candidateID: candidateID)
            let candidate = try? await shoppingRepository.fetchProductCandidate(id: candidateID)
            state = .loaded(Loaded(candidate: candidate, evaluation: evaluation))
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }
}
