//
//  HomeBriefData.swift
//  AstraStyle
//
//  The fully-hydrated, view-ready shape of Kyra's Daily Brief (spec §6.11).
//  `HomeViewModel` never assembles this itself from four separate
//  repository calls — that composition lives in `HomeBriefProviding`
//  (Services/) so the view model's job stays "hold state, react to user
//  actions" rather than "orchestrate five async calls".
//

import Foundation

public struct HomeBriefData: Sendable {
    public var greetingName: String
    public var weather: WeatherSnapshot?
    public var schedule: ScheduleSnapshot?
    public var brief: DailyBrief
    public var primaryOutfit: Outfit?
    public var primaryOutfitItems: [OutfitItem]
    public var alternativeOutfits: [Outfit]
    public var wardrobeScore: WardrobeScore?
    public var laundryAlertItemCount: Int
    public var upcomingOccasions: [Occasion]
    public var purchaseOpportunity: PurchaseOpportunity?

    public init(
        greetingName: String,
        weather: WeatherSnapshot?,
        schedule: ScheduleSnapshot?,
        brief: DailyBrief,
        primaryOutfit: Outfit?,
        primaryOutfitItems: [OutfitItem],
        alternativeOutfits: [Outfit],
        wardrobeScore: WardrobeScore?,
        laundryAlertItemCount: Int,
        upcomingOccasions: [Occasion],
        purchaseOpportunity: PurchaseOpportunity?
    ) {
        self.greetingName = greetingName
        self.weather = weather
        self.schedule = schedule
        self.brief = brief
        self.primaryOutfit = primaryOutfit
        self.primaryOutfitItems = primaryOutfitItems
        self.alternativeOutfits = alternativeOutfits
        self.wardrobeScore = wardrobeScore
        self.laundryAlertItemCount = laundryAlertItemCount
        self.upcomingOccasions = upcomingOccasions
        self.purchaseOpportunity = purchaseOpportunity
    }

    /// Drives the empty state (spec §6.11 "Prompt to add 5 closet items").
    public var needsMoreClosetItems: Bool {
        primaryOutfit == nil
    }
}

/// "Purchase opportunity with outfit unlock count" module (spec §6.11).
public struct PurchaseOpportunity: Sendable {
    public var productCandidate: ProductCandidate
    public var outfitsUnlocked: Int

    public init(productCandidate: ProductCandidate, outfitsUnlocked: Int) {
        self.productCandidate = productCandidate
        self.outfitsUnlocked = outfitsUnlocked
    }
}
