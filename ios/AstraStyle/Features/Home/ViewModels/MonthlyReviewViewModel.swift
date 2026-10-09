import Foundation
import Observation

@MainActor
@Observable
final class MonthlyReviewViewModel {
    enum State {
        case loading
        case loaded(MonthlyReviewSnapshot)
        case failed(String)
    }

    private(set) var state: State = .loading
    let month: Date

    private let closetRepository: ClosetRepository
    private let outfitRepository: OutfitRepository
    private let shoppingRepository: ShoppingRepository

    init(
        month: Date,
        closetRepository: ClosetRepository,
        outfitRepository: OutfitRepository,
        shoppingRepository: ShoppingRepository
    ) {
        self.month = Calendar.current.dateInterval(of: .month, for: month)?.start ?? month
        self.closetRepository = closetRepository
        self.outfitRepository = outfitRepository
        self.shoppingRepository = shoppingRepository
    }

    func load() async {
        state = .loading
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else {
            state = .failed("This month couldn't be opened.")
            return
        }
        do {
            let data = try await fetchReviewData(interval: interval)
            state = .loaded(await makeSnapshot(data: data))
        } catch let error as AstraError {
            state = .failed(error.message)
        } catch {
            state = .failed("Your monthly review couldn't load. Please try again.")
        }
    }

    private func fetchReviewData(interval: DateInterval) async throws -> MonthlyReviewData {
        let end = interval.end.addingTimeInterval(-0.001)
        async let itemsTask = closetRepository.fetchItems()
        async let wearsTask = outfitRepository.fetchOutfitWears(from: interval.start, to: end)
        async let scoreTask = closetRepository.fetchWardrobeScoreSnapshot()
        let (allItems, wears, scoreSnapshot) = try await (itemsTask, wearsTask, scoreTask)
        let scoreHistory = await saveScoreSnapshot(scoreSnapshot.score, monthStart: interval.start)
        let purchases = try await shoppingRepository.fetchPurchases(from: interval.start, to: interval.end)
        let purchaseIDs = Set(purchases.map(\.productCandidateID))
        let evaluations = try await shoppingRepository.fetchLatestEvaluations(candidateIDs: purchaseIDs)
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

    private func makeSnapshot(data: MonthlyReviewData) async -> MonthlyReviewSnapshot {
        let newItems = data.items.filter { data.interval.contains($0.createdAt) }
        let bestEvaluation = bestEvaluation(in: data)
        let bestPurchase = await fetchBestPurchase(for: bestEvaluation)
        let underused = underusedItems(in: data)
        let trendText = versatilitySummary(
            score: data.score,
            previousScore: data.previousVersatilityScore,
            didSave: data.didSaveScoreSnapshot
        )
        let challenge = monthlyChallenge(underused: underused, wearCount: data.wears.count)
        let spendLines = spendSummary(items: data.items, interval: data.interval)
        return MonthlyReviewSnapshot(
            monthTitle: month.formatted(.dateTime.month(.wide).year()),
            newItemCount: newItems.count,
            trackedSpend: spendLines,
            wearCount: data.wears.count,
            uniqueOutfitCount: Set(data.wears.map(\.outfitID)).count,
            bestPurchase: bestPurchase?.name,
            bestPurchaseOutfitsUnlocked: bestEvaluation?.outfitsUnlocked,
            underusedItems: Array(underused.prefix(3)).map(\.name),
            versatilitySummary: trendText,
            nextPriority: nextPriority(from: data.score, newItemCount: newItems.count, wearCount: data.wears.count),
            challenge: challenge
        )
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

    private func monthlyChallenge(underused: [ClosetItem], wearCount: Int) -> String {
        if let first = underused.first {
            return "Wear \(first.name) in a new combination this month."
        } else if wearCount == 0 {
            return "Log your first worn look so next month's review can learn from your real rotation."
        } else {
            return "Repeat a favorite look with one small change, then mark it worn."
        }
    }

    private func nextPriority(from score: WardrobeScore?, newItemCount: Int, wearCount: Int) -> String {
        guard let score else { return "Build a small core wardrobe and record a few worn looks." }
        let weakest = [
            (WardrobeScoreComponentName.versatility, score.versatility),
            (.fitConfidence, score.fitConfidence),
            (.occasionCoverage, score.occasionCoverage),
            (.colorCohesion, score.colorCohesion),
            (.wearUtilization, score.wearUtilization),
            (.condition, score.condition),
            (.redundancyControl, score.redundancyControl)
        ].min { $0.1 < $1.1 }?.0
        switch weakest {
        case .versatility: return "Create more combinations from the pieces you already own."
        case .fitConfidence: return "Add fit notes to the items you reach for most."
        case .occasionCoverage: return "Fill one gap for an occasion you have coming up."
        case .colorCohesion: return "Try one new look using your strongest existing colors."
        case .wearUtilization: return wearCount == 0 ? "Start logging the looks you wear." : "Give overlooked pieces another chance before adding more."
        case .condition: return "Review care and laundry status for the pieces you wear most."
        case .redundancyControl: return newItemCount > 0 ? "Pause before buying another piece in a category you just added." : "Choose your next purchase to fill a clear outfit gap."
        case nil: return "Keep building looks from your existing wardrobe."
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

struct MonthlyReviewSnapshot {
    let monthTitle: String
    let newItemCount: Int
    let trackedSpend: [String]
    let wearCount: Int
    let uniqueOutfitCount: Int
    let bestPurchase: String?
    let bestPurchaseOutfitsUnlocked: Int?
    let underusedItems: [String]
    let versatilitySummary: String
    let nextPriority: String
    let challenge: String

    var kyraPrompt: String {
        let spendText = trackedSpend.isEmpty ? "No closet purchase spend was recorded." : trackedSpend.joined(separator: ", ")
        let bestPurchaseText = bestPurchase.map { name in
            "Best evaluated purchase: \(name), opening \(bestPurchaseOutfitsUnlocked ?? 0) new outfit combinations."
        } ?? "No purchased item had an evaluation this month."
        let underusedText = underusedItems.isEmpty ? "No especially underused items were found." : "Underused pieces: \(underusedItems.joined(separator: ", "))."
        return """
        Help me review my personal style for \(monthTitle) using these recorded facts. New closet pieces: \(newItemCount). Tracked closet spend: \(spendText). Looks marked worn: \(wearCount) across \(uniqueOutfitCount) different outfits. \(bestPurchaseText) \(underusedText) \(versatilitySummary)
        Please give me a short, encouraging review, one practical next priority, and one specific style challenge for next month. Be clear when the history is too limited to draw a trend.
        """
    }
}
