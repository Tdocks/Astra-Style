//
//  MockOutfitRepository.swift
//  AstraStyle
//
//  In-memory `OutfitRepository` for previews/tests (spec §31). This is
//  what `HomeViewModel` is built and previewed against.
//

import Foundation

public actor MockOutfitRepository: OutfitRepository {
    private var outfits: [UUID: Outfit]
    private var outfitItemsByOutfit: [UUID: [OutfitItem]]
    private var wears: [OutfitWear] = []
    private var briefsByDay: [String: DailyBrief] = [:]
    /// Every `style_feedback` row recorded, in insertion order. Exposed
    /// via `recordedFeedback` for tests/previews that want to assert on it.
    /// Named distinctly from `recordWear`'s `feedback: String?` parameter
    /// below, which is an unrelated free-text field on `outfit_wears` —
    /// same word, two different columns on two different tables.
    private var feedbackEntries: [StyleFeedback] = []

    public init() {
        var seededOutfits = [SampleData.heroOutfit: SampleData.heroOutfitItems()]
        for outfit in SampleData.alternativeOutfits {
            seededOutfits[outfit] = []
        }
        outfits = Dictionary(uniqueKeysWithValues: seededOutfits.keys.map { ($0.id, $0) })
        outfitItemsByOutfit = Dictionary(uniqueKeysWithValues: seededOutfits.map { ($0.key.id, $0.value) })

        let today = SampleData.dailyBrief()
        briefsByDay[DateFormatter.astraDay.string(from: today.briefDate)] = today
    }

    public func fetchOutfits() async throws -> [Outfit] {
        Array(outfits.values).sorted { $0.createdAt > $1.createdAt }
    }

    public func fetchOutfit(id: UUID) async throws -> Outfit {
        guard let outfit = outfits[id] else { throw AstraError.server("That outfit couldn't be found.") }
        return outfit
    }

    public func fetchOutfits(ids: [UUID]) async throws -> [Outfit] {
        ids.compactMap { outfits[$0] }
    }

    public func fetchOutfitItems(outfitID: UUID) async throws -> [OutfitItem] {
        outfitItemsByOutfit[outfitID] ?? []
    }

    public func generateOutfits(_ request: OutfitGenerationRequest) async throws -> [OutfitRecommendation] {
        [
            OutfitRecommendation(
                id: SampleData.heroOutfit.id,
                name: SampleData.heroOutfit.name,
                reason: SampleData.heroOutfit.description ?? "",
                compatibilityScore: SampleData.heroOutfit.compatibilityScore ?? 90,
                itemIDs: SampleData.heroOutfitItems().compactMap(\.closetItemID),
                missingProductIDs: []
            )
        ]
    }

    public func rankOutfits(candidateOutfitIDs: [UUID], lockedClosetItemIDs: [UUID]) async throws -> [OutfitRecommendation] {
        try await generateOutfits(OutfitGenerationRequest())
    }

    public func saveOutfit(from recommendation: OutfitRecommendation, name: String?, closetItems: [ClosetItem]) async throws -> Outfit {
        let outfit = Outfit(
            id: recommendation.id,
            userID: SampleData.userID,
            name: name ?? recommendation.name,
            description: recommendation.reason,
            compatibilityScore: recommendation.compatibilityScore,
            source: .aiGenerated
        )
        outfits[outfit.id] = outfit
        outfitItemsByOutfit[outfit.id] = OutfitItemAssembly.ownedItems(
            itemIDs: recommendation.itemIDs,
            outfitID: outfit.id,
            closetItems: closetItems
        )

        return outfit
    }

    public func updateOutfit(_ outfit: Outfit) async throws -> Outfit {
        outfits[outfit.id] = outfit
        return outfit
    }

    public func deleteOutfit(id: UUID) async throws {
        outfits[id] = nil
        outfitItemsByOutfit[id] = nil
    }

    @discardableResult
    public func recordWear(outfitID: UUID, wornAt: Date, occasion: String?, rating: Int?, feedback: String?) async throws -> OutfitWear {
        let wear = OutfitWear(id: UUID(), outfitID: outfitID, userID: SampleData.userID, wornAt: wornAt, occasion: occasion, rating: rating, feedback: feedback)
        wears.append(wear)
        return wear
    }

    /// Test/preview seam: every `outfit_wears` row recorded so far.
    public func recordedWears() async -> [OutfitWear] {
        wears
    }

    @discardableResult
    public func recordFeedback(
        targetType: StyleFeedbackTargetType,
        targetID: UUID,
        signal: StyleFeedbackSignal,
        reasonTags: [String],
        freeText: String?
    ) async throws -> StyleFeedback {
        let entry = StyleFeedback(
            id: UUID(),
            userID: SampleData.userID,
            targetType: targetType,
            targetID: targetID,
            signal: signal,
            reasonTags: reasonTags,
            freeText: freeText
        )
        feedbackEntries.append(entry)
        return entry
    }

    /// Test/preview seam: every `style_feedback` row recorded so far.
    public func recordedFeedback() async -> [StyleFeedback] {
        feedbackEntries
    }

    public func fetchDailyBrief(for date: Date) async throws -> DailyBrief? {
        briefsByDay[DateFormatter.astraDay.string(from: date)]
    }

    public func generateDailyBrief(for date: Date, regenerate: Bool, weather: WeatherSnapshot?) async throws -> DailyBrief {
        // Stores whatever weather it was handed, same as the live server —
        // a preview/test that grants weather permission should see that
        // reading persist onto the brief, not `SampleData`'s own fixture.
        var brief = SampleData.dailyBrief(for: date)
        brief.weatherSnapshot = weather
        briefsByDay[DateFormatter.astraDay.string(from: date)] = brief
        return brief
    }

    public func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan {
        PackingPlan(
            packingListItemIDs: SampleData.closetItems.prefix(6).map(\.id),
            dailyOutfitPlan: [
                PackingDayPlan(date: request.startDate, outfitID: SampleData.heroOutfit.id, isRewear: false)
            ],
            missingEssentials: ["Travel-size garment steamer"],
            weatherContingencyNote: "Pack a packable rain shell in case the forecast shifts."
        )
    }
}
