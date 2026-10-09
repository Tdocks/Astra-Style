//
//  ProductDecisionViewModel.swift
//  AstraStyle
//
//  Wave D: one pasted URL becomes a skip / wait / buy plus a real unlock
//  count. Alternatives are server-scored; full candidate and commercial
//  details load only after the user chooses one.
//

import Foundation
import Observation

@MainActor
@Observable
public final class ProductDecisionViewModel {
    public struct Loaded: Sendable {
        public var candidate: ProductCandidate?
        public var evaluation: ProductEvaluation
        public var isCachedSnapshot: Bool
    }

    public enum ViewState: Sendable {
        case loading
        case loaded(Loaded)
        case failed(AstraError)
    }

    public private(set) var state: ViewState = .loading
    public private(set) var pendingPaywall: PaywallContext?
    public private(set) var isOnWishlist = false
    public private(set) var isPurchased = false
    public private(set) var wishlistMessage: String?

    private let candidateID: UUID
    private let shoppingRepository: ShoppingRepository
    private let startsInHistoricalMode: Bool

    public init(
        candidateID: UUID,
        shoppingRepository: ShoppingRepository,
        startsInHistoricalMode: Bool = false
    ) {
        self.candidateID = candidateID
        self.shoppingRepository = shoppingRepository
        self.startsInHistoricalMode = startsInHistoricalMode
    }

    public var isHistoricalEntry: Bool { startsInHistoricalMode }

    public var isShowingHistoricalSnapshot: Bool {
        guard case .loaded(let loaded) = state else { return startsInHistoricalMode }
        return loaded.isCachedSnapshot
    }

    public func onAppear() async {
        guard case .loading = state else { return }
        await load()
    }

    public func retry() async {
        state = .loading
        await load()
    }

    /// A saved history view never scores automatically. This is the sole
    /// action that asks the server for a new wardrobe evaluation.
    public func refreshEvaluation() async {
        pendingPaywall = nil
        state = .loading
        await loadFreshEvaluation()
    }

    /// Buy / consider may reopen the URL he pasted. Skip / wait must not
    /// push a catalog, and they do not get a retailer button.
    public var canOpenSourceURL: Bool {
        guard case .loaded(let loaded) = state,
              !loaded.isCachedSnapshot,
              loaded.candidate != nil else { return false }
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

    /// Skip/wait may share the refusal. Buy/consider must not share a CTA.
    public var shareText: String? {
        guard case .loaded(let loaded) = state, !loaded.isCachedSnapshot else { return nil }
        return ProductDecisionCopy.shareText(
            verdict: loaded.evaluation.verdict,
            garmentName: loaded.candidate?.name
        )
    }

    private func load() async {
        if startsInHistoricalMode {
            await loadSavedSnapshot()
        } else {
            await loadFreshEvaluation()
        }
    }

    private func loadSavedSnapshot() async {
        do {
            guard let snapshot = try await shoppingRepository.fetchCachedDecision(candidateID: candidateID) else {
                state = .failed(AstraError.network("That saved evaluation is no longer available on this device."))
                return
            }
            state = .loaded(Loaded(
                candidate: snapshot.candidate,
                evaluation: snapshot.evaluation,
                isCachedSnapshot: true
            ))
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    private func loadFreshEvaluation() async {
        do {
            let evaluation = try await shoppingRepository.evaluateProduct(candidateID: candidateID)
            let candidate = try? await shoppingRepository.fetchProductCandidate(id: candidateID)
            state = .loaded(Loaded(candidate: candidate, evaluation: evaluation, isCachedSnapshot: false))
            await refreshSaveState()
        } catch let error as AstraError where error.category == .network {
            if let snapshot = try? await shoppingRepository.fetchCachedDecision(candidateID: candidateID) {
                state = .loaded(Loaded(
                    candidate: snapshot.candidate,
                    evaluation: snapshot.evaluation,
                    isCachedSnapshot: true
                ))
                return
            }
            state = .failed(error)
        } catch let error as AstraError where error.category == .subscriptionLimitReached {
            // Paste evaluation's one-time trial allowance is an inline
            // limit state, not a paywall (ADR-0017).
            state = .failed(error)
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    public func toggleWishlist() async {
        guard !isShowingCachedSnapshot else {
            wishlistMessage = String(localized: "Reconnect and refresh the evaluation before changing saved items.")
            return
        }
        wishlistMessage = nil
        do {
            if isOnWishlist {
                try await shoppingRepository.removeFromWishlist(candidateID: candidateID)
            } else {
                try await shoppingRepository.addToWishlist(candidateID: candidateID)
            }
            await refreshSaveState()
        } catch let error as AstraError {
            wishlistMessage = error.message
        } catch {
            wishlistMessage = String(localized: "Couldn't update that save.")
        }
    }

    public func markPurchased() async {
        guard !isShowingCachedSnapshot else {
            wishlistMessage = String(localized: "Reconnect and refresh the evaluation before changing saved items.")
            return
        }
        wishlistMessage = nil
        do {
            try await shoppingRepository.markPurchased(candidateID: candidateID)
            await refreshSaveState()
        } catch let error as AstraError {
            wishlistMessage = error.message
        } catch {
            wishlistMessage = String(localized: "Couldn't mark that as purchased.")
        }
    }

    public func clearPendingPaywall() {
        pendingPaywall = nil
    }

    private func refreshSaveState() async {
        let saved = (try? await shoppingRepository.fetchWishlist()) ?? []
        let bought = (try? await shoppingRepository.fetchPurchased()) ?? []
        isPurchased = bought.contains { $0.id == candidateID }
        isOnWishlist = !isPurchased && saved.contains { $0.id == candidateID }
    }

    private var isShowingCachedSnapshot: Bool {
        guard case .loaded(let loaded) = state else { return false }
        return loaded.isCachedSnapshot
    }
}
