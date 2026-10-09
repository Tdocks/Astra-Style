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
        let newItems = data.items.filter { contains($0.createdAt, in: data.interval) }
        let bestEvaluation = bestEvaluation(in: data)
        let bestPurchase = await fetchBestPurchase(for: bestEvaluation)
        try await verifyActiveOwner(ownerID)
        let underused = underusedItems(in: data)
        let trendText = versatilitySummary(
            score: data.versatilityScore,
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
            versatilityScore: data.versatilityScore,
            previousVersatilityScore: data.previousVersatilityScore
        )
    }

    private func fetchReviewData(interval: DateInterval, expectedOwnerID: UUID) async throws -> MonthlyReviewData {
        async let itemsTask = closetRepository.fetchMonthlyHistoryItems(createdOrPurchasedBefore: interval.end)
        async let wearsTask = outfitRepository.fetchOutfitWears(from: interval.start, before: interval.end)
        let (allItems, wears) = try await (itemsTask, wearsTask)
        try await verifyActiveOwner(expectedOwnerID)
        guard allItems.allSatisfy({ $0.userID == expectedOwnerID }),
              wears.allSatisfy({ $0.userID == expectedOwnerID }) else {
            throw AstraError.auth("Monthly Review data belongs to another account.")
        }
        let itemWearCounts = try await monthlyItemWearCounts(wears: wears, ownerID: expectedOwnerID)
        try await verifyActiveOwner(expectedOwnerID)

        let scoreHistory = try await fetchScoreHistory(interval: interval, ownerID: expectedOwnerID)
        let purchases = try await shoppingRepository.fetchPurchases(from: interval.start, to: interval.end)
        try await verifyActiveOwner(expectedOwnerID)
        let purchaseIDs = Set(purchases.map(\.productCandidateID))
        let evaluations = try await shoppingRepository.fetchLatestEvaluations(
            candidateIDs: purchaseIDs,
            before: interval.end
        )
        try await verifyActiveOwner(expectedOwnerID)
        guard evaluations.allSatisfy({ $0.userID == expectedOwnerID }) else {
            throw AstraError.auth("Monthly Review evaluations belong to another account.")
        }
        return MonthlyReviewData(
            interval: interval,
            items: allItems,
            wears: wears,
            evaluations: evaluations,
            purchases: purchases,
            itemWearCounts: itemWearCounts,
            versatilityScore: scoreHistory.monthScore,
            previousVersatilityScore: scoreHistory.previousScore,
            didSaveScoreSnapshot: scoreHistory.didSave
        )
    }

    private func fetchScoreHistory(interval: DateInterval, ownerID: UUID) async throws -> MonthlyScoreHistory {
        let currentMonthStart = Calendar.current.dateInterval(of: .month, for: .now)?.start
        let currentScoreSnapshot: WardrobeScoreSnapshot?
        do {
            currentScoreSnapshot = try await closetRepository.fetchWardrobeScoreSnapshot()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            currentScoreSnapshot = nil
        }
        try await verifyActiveOwner(ownerID)
        let currentScore = currentScoreSnapshot?.score?.versatility
        var currentMonthPreviousScore: Int?
        var didSaveCurrentMonthScore = false
        if let currentMonthStart, let currentScore {
            let saved = try await saveScoreSnapshot(currentScore, monthStart: currentMonthStart)
            currentMonthPreviousScore = saved.previousScore
            didSaveCurrentMonthScore = saved.didSave
            try await verifyActiveOwner(ownerID)
        }
        if currentMonthStart == interval.start {
            return MonthlyScoreHistory(
                monthScore: currentScore,
                previousScore: currentMonthPreviousScore,
                didSave: didSaveCurrentMonthScore
            )
        } else {
            let history = try await closetRepository.fetchMonthlyVersatilityHistory(monthStart: interval.start)
            try await verifyActiveOwner(ownerID)
            return MonthlyScoreHistory(
                monthScore: history.monthScore,
                previousScore: history.previousScore,
                didSave: false
            )
        }
    }

    private func monthlyItemWearCounts(wears: [OutfitWear], ownerID: UUID) async throws -> [UUID: Int] {
        let outfitIDs = Array(Set(wears.map(\.outfitID))).sorted { $0.uuidString < $1.uuidString }
        var counts: [UUID: Int] = [:]
        for start in stride(from: 0, to: outfitIDs.count, by: 20) {
            let batch = Array(outfitIDs[start..<min(start + 20, outfitIDs.count)])
            let rows = try await withThrowingTaskGroup(of: [OutfitItem].self) { group in
                for outfitID in batch {
                    group.addTask { try await outfitRepository.fetchOutfitItems(outfitID: outfitID) }
                }
                var collected: [[OutfitItem]] = []
                for try await value in group { collected.append(value) }
                return collected.flatMap { $0 }
            }
            try await verifyActiveOwner(ownerID)
            guard rows.allSatisfy({ batch.contains($0.outfitID) }) else {
                throw AstraError.server("Monthly Review outfit history is invalid.")
            }
            for outfitID in batch {
                let outfitWears = wears.filter { $0.outfitID == outfitID }.count
                guard outfitWears > 0 else { continue }
                let outfitRows = rows.filter { $0.outfitID == outfitID }
                for itemID in Set(outfitRows.filter { $0.productCandidateID == nil }.compactMap(\.closetItemID)) {
                    counts[itemID, default: 0] += outfitWears
                }
            }
        }
        return counts
    }

    private func saveScoreSnapshot(_ score: Int, monthStart: Date) async throws -> (previousScore: Int?, didSave: Bool) {
        do {
            let previous = try await closetRepository.captureMonthlyVersatilitySnapshot(
                monthStart: monthStart,
                score: score
            )
            return (previous, true)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (nil, false)
        }
    }

    private func spendSummary(items: [ClosetItem], interval: DateInterval) -> [String] {
        var spendByCurrency: [String: Decimal] = [:]
        for item in items where item.purchaseDate.map({ containsPurchaseDate($0, in: interval) }) == true {
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
            .filter { !$0.isArchived && $0.createdAt < data.interval.start && data.itemWearCounts[$0.id, default: 0] <= 1 }
            .sorted {
                let leftCount = data.itemWearCounts[$0.id, default: 0]
                let rightCount = data.itemWearCounts[$1.id, default: 0]
                if leftCount != rightCount { return leftCount < rightCount }
                if $0.wearCount != $1.wearCount { return $0.wearCount < $1.wearCount }
                return $0.createdAt < $1.createdAt
            }
    }

    private func versatilitySummary(score: Int?, previousScore: Int?, didSave: Bool) -> String {
        let trendText: String
        if let score {
            if let previousScore {
                let change = score - previousScore
                if change > 0 {
                    trendText = "Your wardrobe versatility increased by \(change) points, from \(previousScore) to \(score)."
                } else if change < 0 {
                    trendText = "Your wardrobe versatility changed by \(change) points, from \(previousScore) to \(score)."
                } else {
                    trendText = "Your wardrobe versatility held steady at \(score)."
                }
            } else if didSave {
                trendText = "Your current versatility score is \(score). This month is your baseline; next month's review can show the change."
            } else {
                trendText = "Your wardrobe versatility score for this month is \(score), but no prior monthly comparison is available."
            }
        } else {
            trendText = "No wardrobe versatility score was captured for this month, so a month-to-month comparison is unavailable."
        }
        return trendText
    }

    private func verifyActiveOwner(_ expectedOwnerID: UUID) async throws {
        guard await currentOwnerID() == expectedOwnerID else {
            throw AstraError.auth("Your account changed while loading Monthly Review.")
        }
    }

    private func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }

    private func containsPurchaseDate(_ date: Date, in interval: DateInterval) -> Bool {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard let localDay = Calendar.current.date(from: components),
              let month = Calendar.current.dateInterval(of: .month, for: localDay) else { return false }
        return month.start == interval.start
    }
}

private struct MonthlyReviewData {
    let interval: DateInterval
    let items: [ClosetItem]
    let wears: [OutfitWear]
    let evaluations: [ProductEvaluation]
    let purchases: [ProductPurchase]
    let itemWearCounts: [UUID: Int]
    let versatilityScore: Int?
    let previousVersatilityScore: Int?
    let didSaveScoreSnapshot: Bool
}

private struct MonthlyScoreHistory {
    let monthScore: Int?
    let previousScore: Int?
    let didSave: Bool
}
