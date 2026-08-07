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

        let itemsByID = Dictionary(uniqueKeysWithValues: closetItems.map { ($0.id, $0) })
        outfitItemsByOutfit[outfit.id] = recommendation.itemIDs.enumerated().compactMap { index, closetItemID in
            guard
                let category = itemsByID[closetItemID]?.category,
                let role = OutfitItemRole(rawValue: category.rawValue)
            else { return nil }
            return OutfitItem(outfitID: outfit.id, closetItemID: closetItemID, role: role, sortOrder: index)
        }

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

    public func fetchDailyBrief(for date: Date) async throws -> DailyBrief? {
        briefsByDay[DateFormatter.astraDay.string(from: date)]
    }

    public func generateDailyBrief(for date: Date, regenerate: Bool) async throws -> DailyBrief {
        let brief = SampleData.dailyBrief(for: date)
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
