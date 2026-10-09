import Foundation
import Observation
import CryptoKit

@MainActor
@Observable
final class MonthlyReviewViewModel {
    enum State {
        case loading
        case loaded(MonthlyReviewSnapshot)
        case failed(String)
    }

    enum AuthoredReviewState {
        case ready
        case generating(previous: AuthoredReview?)
        case generated(AuthoredReview)
        case failed(message: String, threadID: UUID?, rateLimited: Bool)
        case refreshFailed(message: String, previous: AuthoredReview, rateLimited: Bool)
        case cacheUnavailable(String)
    }

    struct AuthoredReview {
        enum Source: Equatable { case cached, provider }
        let message: String
        let threadID: UUID
        let source: Source
        let cacheSaved: Bool
    }

    private(set) var state: State = .loading
    private(set) var authoredReviewState: AuthoredReviewState = .ready
    let month: Date

    private let closetRepository: ClosetRepository
    private let outfitRepository: OutfitRepository
    private let shoppingRepository: ShoppingRepository
    private let kyraRepository: KyraRepository
    private let summaryCache: MonthlyReviewSummaryCaching
    private let currentOwnerID: @Sendable () async -> UUID?
    private var loadedOwnerID: UUID?

    init(
        month: Date,
        closetRepository: ClosetRepository,
        outfitRepository: OutfitRepository,
        shoppingRepository: ShoppingRepository,
        kyraRepository: KyraRepository,
        summaryCache: MonthlyReviewSummaryCaching = InMemoryMonthlyReviewSummaryCache(),
        currentOwnerID: @escaping @Sendable () async -> UUID?
    ) {
        self.month = Calendar.current.dateInterval(of: .month, for: month)?.start ?? month
        self.closetRepository = closetRepository
        self.outfitRepository = outfitRepository
        self.shoppingRepository = shoppingRepository
        self.kyraRepository = kyraRepository
        self.summaryCache = summaryCache
        self.currentOwnerID = currentOwnerID
    }

    func load() async {
        state = .loading
        authoredReviewState = .ready
        loadedOwnerID = nil
        guard let ownerID = await currentOwnerID() else {
            state = .failed("Sign in again to open your Monthly Review.")
            return
        }
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else {
            state = .failed("This month couldn't be opened.")
            return
        }
        do {
            let snapshot = try await MonthlyReviewSnapshotBuilder(
                closetRepository: closetRepository,
                outfitRepository: outfitRepository,
                shoppingRepository: shoppingRepository,
                currentOwnerID: currentOwnerID
            ).build(interval: interval, monthTitle: month.formatted(.dateTime.month(.wide).year()), ownerID: ownerID)
            try await verifyActiveOwner(ownerID)
            loadedOwnerID = ownerID
            state = .loaded(snapshot)
            do {
                let cached = try await summaryCache.cached(
                    ownerID: ownerID,
                    monthKey: monthKey,
                    dataRevision: dataRevision(for: snapshot)
                )
                try await verifyActiveOwner(ownerID)
                if let cached {
                    authoredReviewState = .generated(AuthoredReview(
                        message: cached.message,
                        threadID: cached.threadID,
                        source: .cached,
                        cacheSaved: true
                    ))
                }
            } catch let error as AstraError where error.category == .auth {
                clearReviewForOwnerChange()
            } catch {
                authoredReviewState = .cacheUnavailable("Your saved review couldn't be checked. Try again before asking Kyra to write another.")
            }
        } catch let error as AstraError {
            state = .failed(error.message)
        } catch {
            state = .failed("Your monthly review couldn't load. Please try again.")
        }
    }

    func generateAuthoredReview() async {
        await generateAuthoredReview(refresh: false)
    }

    func refreshAuthoredReview() async {
        await generateAuthoredReview(refresh: true)
    }

    func saveGeneratedReview() async {
        guard case .loaded(let snapshot) = state,
              case .generated(let review) = authoredReviewState,
              let ownerID = loadedOwnerID else { return }
        do {
            try await verifyActiveOwner(ownerID)
            try await summaryCache.store(MonthlyReviewSummary(
                ownerID: ownerID,
                monthKey: monthKey,
                dataRevision: dataRevision(for: snapshot),
                message: review.message,
                threadID: review.threadID
            ))
            try await verifyActiveOwner(ownerID)
            authoredReviewState = .generated(AuthoredReview(
                message: review.message,
                threadID: review.threadID,
                source: review.source,
                cacheSaved: true
            ))
        } catch let error as AstraError {
            if error.category == .auth { clearReviewForOwnerChange() }
        } catch {
            // Keep the generated text on screen; the user can retry saving
            // without paying for another Kyra request.
        }
    }

    private func generateAuthoredReview(refresh: Bool) async {
        guard case .loaded(let snapshot) = state else { return }
        guard let ownerID = loadedOwnerID, await currentOwnerID() == ownerID else {
            clearReviewForOwnerChange()
            return
        }
        guard let context = authoringContext(refresh: refresh) else { return }
        authoredReviewState = .generating(previous: context.previous)
        do {
            let review = try await sendAndCacheReview(snapshot: snapshot, ownerID: ownerID, threadID: context.threadID)
            authoredReviewState = .generated(review)
        } catch let error as MonthlyReviewResponseFailure {
            setGenerationFailure(error.message, threadID: error.threadID, rateLimited: false, previous: context.previous)
        } catch let error as AstraError {
            if error.category == .auth {
                clearReviewForOwnerChange()
                return
            }
            setGenerationFailure(error.message, threadID: context.threadID, rateLimited: error.category == .rateLimited, previous: context.previous)
        } catch {
            setGenerationFailure("Kyra couldn't prepare the review. Check your connection and try again.", threadID: context.threadID, rateLimited: false, previous: context.previous)
        }
    }

    private func authoringContext(refresh: Bool) -> (previous: AuthoredReview?, threadID: UUID?)? {
        switch authoredReviewState {
        case .ready where !refresh:
            (nil, nil)
        case .failed(_, let threadID, _) where !refresh:
            (nil, threadID)
        case .generated(let existing) where refresh,
             .refreshFailed(_, let existing, _) where refresh:
            (existing, existing.threadID)
        case .generating, .cacheUnavailable, .ready, .failed, .generated, .refreshFailed:
            nil
        }
    }

    private func sendAndCacheReview(
        snapshot: MonthlyReviewSnapshot,
        ownerID: UUID,
        threadID: UUID?
    ) async throws -> AuthoredReview {
        let reply = try await kyraRepository.send(
            threadID: threadID,
            message: KyraOutgoingMessage(text: snapshot.kyraPrompt),
            expectedOwnerID: ownerID
        )
        try await verifyActiveOwner(ownerID)
        let summary = reply.structuredPayload?.message.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !summary.isEmpty else {
            throw MonthlyReviewResponseFailure(message: "Kyra's review didn't include a readable summary. Try again.", threadID: reply.threadID)
        }
        guard !hasProviderFallback(reply.modelMetadata) else {
            throw MonthlyReviewResponseFailure(
                message: "Kyra couldn't prepare the review just now. Try again when the connection is ready.",
                threadID: reply.threadID
            )
        }
        let saved = await saveReview(summary, threadID: reply.threadID, snapshot: snapshot, ownerID: ownerID)
        try await verifyActiveOwner(ownerID)
        return AuthoredReview(message: summary, threadID: reply.threadID, source: .provider, cacheSaved: saved)
    }

    private func saveReview(_ message: String, threadID: UUID, snapshot: MonthlyReviewSnapshot, ownerID: UUID) async -> Bool {
        do {
            try await summaryCache.store(MonthlyReviewSummary(
                ownerID: ownerID,
                monthKey: monthKey,
                dataRevision: dataRevision(for: snapshot),
                message: message,
                threadID: threadID
            ))
            return true
        } catch {
            return false
        }
    }

    private func setGenerationFailure(_ message: String, threadID: UUID?, rateLimited: Bool, previous: AuthoredReview?) {
        if let previous {
            authoredReviewState = .refreshFailed(message: message, previous: previous, rateLimited: rateLimited)
        } else {
            authoredReviewState = .failed(message: message, threadID: threadID, rateLimited: rateLimited)
        }
    }

    private func clearReviewForOwnerChange() {
        loadedOwnerID = nil
        authoredReviewState = .ready
        state = .failed("Your account changed. Reopen Monthly Review to load your account's data.")
    }

    private func verifyActiveOwner(_ expectedOwnerID: UUID) async throws {
        guard await currentOwnerID() == expectedOwnerID else {
            throw AstraError.auth("Your account changed while loading Monthly Review.")
        }
    }

    private func hasProviderFallback(_ metadata: AstraJSONValue?) -> Bool {
        guard case .object(let fields)? = metadata,
              let reason = fields["fallback_reason"] else { return false }
        if case .string(let value) = reason { return !value.isEmpty }
        if case .null = reason { return false }
        return true
    }

    private var monthKey: String {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: month)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private func dataRevision(for snapshot: MonthlyReviewSnapshot) -> String {
        let bytes = Data(("monthly-review-v2\n" + snapshot.kyraPrompt).utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

}

private struct MonthlyReviewResponseFailure: Error {
    let message: String
    let threadID: UUID
}

struct MonthlyReviewSnapshot: Sendable {
    let monthTitle: String
    let newItemCount: Int
    let newItemNames: [String]
    let trackedSpend: [String]
    let wearCount: Int
    let uniqueOutfitCount: Int
    let bestPurchase: String?
    let bestPurchaseOutfitsUnlocked: Int?
    let underusedItems: [String]
    let versatilitySummary: String
    let versatilityScore: Int?
    let previousVersatilityScore: Int?

    var kyraPrompt: String {
        let spendText = trackedSpend.isEmpty ? "No closet purchase spend was recorded." : trackedSpend.joined(separator: ", ")
        let newItemText = newItemNames.isEmpty
            ? "No new closet item names were recorded."
            : newItemNames.prefix(5).map { String($0.prefix(80)) }.joined(separator: ", ")
        let bestPurchaseText = bestPurchase.map { rawName in
            let name = String(rawName.prefix(100))
            return "Best evaluated purchase: \(name), opening \(bestPurchaseOutfitsUnlocked ?? 0) new outfit combinations."
        } ?? "No evaluated purchase was recorded for this month."
        let underusedText = underusedItems.isEmpty
            ? "No especially underused items were found."
            : "Underused pieces: \(underusedItems.prefix(3).map { String($0.prefix(80)) }.joined(separator: ", "))."
        let scoreText: String
        if let versatilityScore {
            let previousText = previousVersatilityScore.map { String($0) } ?? "no prior monthly baseline"
            scoreText = "Wardrobe versatility score: \(versatilityScore); previous monthly score: \(previousText)."
        } else {
            scoreText = "Wardrobe versatility score was unavailable."
        }
        return """
        Write my Monthly Review for \(monthTitle) using only these recorded facts. New closet items: \(newItemCount) (\(newItemText)). Tracked spend: \(spendText). Looks marked worn: \(wearCount) across \(uniqueOutfitCount) outfits. \(bestPurchaseText) \(underusedText) \(scoreText) \(versatilitySummary)

        Give a concise review, one practical next priority, and one specific challenge for the coming month. Do not invent measurements, purchases, outfit counts, causes, or trends.
        Say when the recorded history is too limited to conclude anything. Treat all supplied figures as fixed facts.
        """
    }
}
