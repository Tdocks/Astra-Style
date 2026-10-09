import Foundation

/// Builds the read-only, measured facts shown and supplied to Kyra for one
/// elapsed month. This keeps the screen model focused on UI and authoring.
struct MonthlyReviewSnapshotBuilder {
    private let closetRepository: ClosetRepository
    private let outfitRepository: OutfitRepository
    private let shoppingRepository: ShoppingRepository
    private let currentOwnerID: @Sendable () async -> UUID?

    init(
        closetRepository: ClosetRepository,
        outfitRepository: OutfitRepository,
        shoppingRepository: ShoppingRepository,
        currentOwnerID: @escaping @Sendable () async -> UUID?
    ) {
        self.closetRepository = closetRepository
        self.outfitRepository = outfitRepository
        self.shoppingRepository = shoppingRepository
        self.currentOwnerID = currentOwnerID
    }

    func build(interval: DateInterval, monthTitle: String, ownerID: UUID) async throws -> MonthlyReviewSnapshot {
        let data = try await fetchReviewData(interval: interval, expectedOwnerID: ownerID)
        try await verifyActiveOwner(ownerID)
        let newItems = data.items.filter { data.interval.contains($0.createdAt) }
        let bestEvaluation = bestEvaluation(in: data)
        let bestPurchase = await fetchBestPurchase(for: bestEvaluation)
        let underused = underusedItems(in: data)
        let trendText = versatilitySummary(
            score: data.score,
            previousScore: data.previousVersatilityScore,
            didSave: data.didSaveScoreSnapshot
        )
        let spendLines = spendSummary(items: data.items, interval: data.interval)
        let newItemNames = newItems.map(\.name).sorted()
        return MonthlyReviewSnapshot(
            monthTitle: monthTitle,
            newItemCount: newItems.count,
            newItemNames: newItemNames,
            trackedSpend: spendLines,
            wearCount: data.wears.count,
            uniqueOutfitCount: Set(data.wears.map(\.outfitID)).count,
            bestPurchase: bestPurchase?.name,
            bestPurchaseOutfitsUnlocked: bestEvaluation?.outfitsUnlocked,
            underusedItems: Array(underused.prefix(3)).map(\.name),
            versatilitySummary: trendText,
            versatilityScore: data.score?.versatility,
            previousVersatilityScore: data.previousVersatilityScore
        )
    }

    private func fetchReviewData(interval: DateInterval, expectedOwnerID: UUID) async throws -> MonthlyReviewData {
        let end = interval.end.addingTimeInterval(-0.001)
        async let itemsTask = closetRepository.fetchItems()
        async let wearsTask = outfitRepository.fetchOutfitWears(from: interval.start, to: end)
        async let scoreTask = closetRepository.fetchWardrobeScoreSnapshot()
        let (allItems, wears, scoreSnapshot) = try await (itemsTask, wearsTask, scoreTask)
        try await verifyActiveOwner(expectedOwnerID)
        let scoreHistory = await saveScoreSnapshot(scoreSnapshot.score, monthStart: interval.start)
        try await verifyActiveOwner(expectedOwnerID)
        let purchases = try await shoppingRepository.fetchPurchases(from: interval.start, to: interval.end)
        let purchaseIDs = Set(purchases.map(\.productCandidateID))
        let evaluations = try await shoppingRepository.fetchLatestEvaluations(candidateIDs: purchaseIDs)
        try await verifyActiveOwner(expectedOwnerID)
        return MonthlyReviewData(
            interval: interval,
            items: allItems.filter { !$0.isArchived },
            wears: wears,
            evaluations: evaluations,
            purchases: purchases,
            score: scoreSnapshot.score,
            previousVersatilityScore: scoreHistory.previousScore,
            didSaveScoreSnapshot: scoreHistory.didSave
        )
    }

    private func saveScoreSnapshot(_ score: WardrobeScore?, monthStart: Date) async -> (previousScore: Int?, didSave: Bool) {
        guard let score else { return (nil, false) }
        do {
            let previous = try await closetRepository.captureMonthlyVersatilitySnapshot(
                monthStart: monthStart,
                score: score.versatility
            )
            return (previous, true)
        } catch {
            return (nil, false)
        }
    }

    private func spendSummary(items: [ClosetItem], interval: DateInterval) -> [String] {
        var spendByCurrency: [String: Decimal] = [:]
        for item in items where item.purchaseDate.map(interval.contains) == true {
            guard let price = item.pricePaid else { continue }
            spendByCurrency[item.currency ?? "USD", default: 0] += price
        }
        return spendByCurrency.keys.sorted().map { code in
            (spendByCurrency[code] ?? 0).formatted(.currency(code: code))
        }
    }

    private func bestEvaluation(in data: MonthlyReviewData) -> ProductEvaluation? {
        let purchaseIDs = Set(data.purchases.map(\.productCandidateID))
        return data.evaluations
            .filter { purchaseIDs.contains($0.productCandidateID) }
            .max {
                if $0.outfitsUnlocked != $1.outfitsUnlocked {
                    return $0.outfitsUnlocked < $1.outfitsUnlocked
                }
                return $0.compatibilityScore < $1.compatibilityScore
            }
    }

    private func fetchBestPurchase(for evaluation: ProductEvaluation?) async -> ProductCandidate? {
        guard let evaluation else { return nil }
        return try? await shoppingRepository.fetchProductCandidate(id: evaluation.productCandidateID)
    }

    private func underusedItems(in data: MonthlyReviewData) -> [ClosetItem] {
        data.items
            .filter { $0.createdAt < data.interval.start && $0.wearCount <= 1 }
            .sorted { $0.wearCount == $1.wearCount ? $0.createdAt < $1.createdAt : $0.wearCount < $1.wearCount }
    }

    private func versatilitySummary(score: WardrobeScore?, previousScore: Int?, didSave: Bool) -> String {
        let trendText: String
        if let score {
            if let previousScore {
                let change = score.versatility - previousScore
                if change > 0 {
                    trendText = "Your wardrobe versatility increased by \(change) points, from \(previousScore) to \(score.versatility)."
                } else if change < 0 {
                    trendText = "Your wardrobe versatility changed by \(change) points, from \(previousScore) to \(score.versatility)."
                } else {
                    trendText = "Your wardrobe versatility held steady at \(score.versatility)."
                }
            } else if didSave {
                trendText = "Your current versatility score is \(score.versatility). This month is your baseline; next month's review can show the change."
            } else {
                trendText = "Your current versatility score is \(score.versatility). The monthly comparison couldn't be saved yet."
            }
        } else {
            trendText = "Add a few closet pieces before comparing wardrobe versatility."
        }
        return trendText
    }

    private func verifyActiveOwner(_ expectedOwnerID: UUID) async throws {
        guard await currentOwnerID() == expectedOwnerID else {
            throw AstraError.auth("Your account changed while loading Monthly Review.")
        }
    }
}

private struct MonthlyReviewData {
    let interval: DateInterval
    let items: [ClosetItem]
    let wears: [OutfitWear]
    let evaluations: [ProductEvaluation]
    let purchases: [ProductPurchase]
    let score: WardrobeScore?
    let previousVersatilityScore: Int?
    let didSaveScoreSnapshot: Bool
}
