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
    public var upcomingOccasions: [Occasion]
    public var purchaseOpportunity: PurchaseOpportunity?
    /// Everything wearable the man owns, by role. Carried so the empty state
    /// can say something true — see `emptyReason`.
    ///
    /// OPTIONAL, AND NIL IS NOT ZERO. The provider reads the closet with
    /// `try?`, because a closet it cannot reach must not block the brief. That
    /// left the failure indistinguishable from an empty closet: a dropped
    /// connection produced `[:]`, `closetItemCount` read 0, and Home told a
    /// man with forty garments to scan his first item. Nil means "we did not
    /// find out", which is a different sentence from "there is nothing there"
    /// and has to be carried as one.
    public var closetRoleCounts: [ClothingCategory: Int]?
    /// Today's outfit, joined to the garments and their signed images.
    /// Empty when there is no outfit, which is the same condition as
    /// `primaryOutfit == nil` and is what `emptyReason` already reads.
    public var lookGarments: [LookGarment]

    public init(
        greetingName: String,
        weather: WeatherSnapshot?,
        schedule: ScheduleSnapshot?,
        brief: DailyBrief,
        primaryOutfit: Outfit?,
        primaryOutfitItems: [OutfitItem],
        alternativeOutfits: [Outfit],
        wardrobeScore: WardrobeScore?,
        upcomingOccasions: [Occasion],
        purchaseOpportunity: PurchaseOpportunity?,
        closetRoleCounts: [ClothingCategory: Int]? = [:],
        lookGarments: [LookGarment] = []
    ) {
        self.greetingName = greetingName
        self.weather = weather
        self.schedule = schedule
        self.brief = brief
        self.primaryOutfit = primaryOutfit
        self.primaryOutfitItems = primaryOutfitItems
        self.alternativeOutfits = alternativeOutfits
        self.wardrobeScore = wardrobeScore
        self.upcomingOccasions = upcomingOccasions
        self.purchaseOpportunity = purchaseOpportunity
        self.closetRoleCounts = closetRoleCounts
        self.lookGarments = lookGarments
    }

    /// The three roles an outfit needs before one can exist at all.
    ///
    /// Not a style opinion — a structural one. `generateCandidateOutfits`
    /// builds top/bottom/shoes and returns nothing without all three, so a
    /// closet missing any of them cannot produce a single outfit however
    /// many garments it holds.
    public static let requiredRoles: [ClothingCategory] = [.top, .bottom, .shoes]

    public var missingRoles: [ClothingCategory] {
        let counts = closetRoleCounts ?? [:]
        return Self.requiredRoles.filter { (counts[$0] ?? 0) == 0 }
    }

    public var closetItemCount: Int {
        (closetRoleCounts ?? [:]).values.reduce(0, +)
    }

    /// The closet could not be read on this load.
    ///
    /// Distinct from every `EmptyReason`, because it is not a reason — it is
    /// the absence of one. `HomeViewModel` turns this into the recoverable
    /// error state rather than an empty state, since the honest thing to put
    /// in front of the user is a retry, not advice about his wardrobe.
    public var closetIsUnreadable: Bool { closetRoleCounts == nil }

    /// Why Home has no outfit to show, if it has none.
    ///
    /// This used to be a single `needsMoreClosetItems` computed as
    /// `primaryOutfit == nil`, and the screen it drove said "Add five pieces
    /// and Kyra can begin building real outfits." That sentence was read by a
    /// man with fifteen garments in his closet, because he had photographed
    /// fifteen shirts: the engine correctly built zero outfits, and the copy
    /// told him he owned almost nothing.
    ///
    /// The state was right. The reading was confounded — "too few garments"
    /// and "garments, but not the right kinds" are different facts, and
    /// collapsing them produced advice that could not help. Following it
    /// (adding five more shirts) would leave the screen exactly as it was.
    public enum EmptyReason: Equatable, Sendable {
        /// Fewer than `minimumItemsForOutfits` garments. §6.11's own case.
        case tooFewItems(have: Int, need: Int)
        /// Enough garments, but at least one role an outfit requires is
        /// missing entirely.
        case missingRoles([ClothingCategory])
        /// Enough garments and every role present, and still no outfit —
        /// nothing structural is wrong, so nothing structural is claimed.
        case noOutfitYet
    }

    /// Nil when there IS an outfit, and also nil when the closet could not be
    /// read: in that second case there is no honest answer to "why not", and
    /// guessing one is how "scan your first item" ended up in front of a man
    /// whose closet was simply unreachable for a second. `closetIsUnreadable`
    /// carries that case instead.
    public var emptyReason: EmptyReason? {
        guard primaryOutfit == nil, closetRoleCounts != nil else { return nil }
        if closetItemCount < Self.minimumItemsForOutfits {
            return .tooFewItems(have: closetItemCount, need: Self.minimumItemsForOutfits)
        }
        let missing = missingRoles
        return missing.isEmpty ? .noOutfitYet : .missingRoles(missing)
    }

    /// Kept as the single "is Home empty" question the view model asks.
    public var needsMoreClosetItems: Bool { emptyReason != nil }

    /// The closet size below which §6.11's empty state — not a Daily Brief —
    /// is the correct screen, taken from that section's own wording
    /// ("Prompt to add 5 closet items") and §21's example copy ("Add five
    /// pieces and Kyra can begin building real outfits").
    ///
    /// It lives here rather than inside `DefaultHomeBriefProvider` because
    /// it is the number the *copy* promises. If the two ever disagree the
    /// screen tells the user to add five pieces and then keeps showing him
    /// the same screen after he adds a fifth, which reads as a broken app
    /// rather than an early one.
    public static let minimumItemsForOutfits = 5
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
