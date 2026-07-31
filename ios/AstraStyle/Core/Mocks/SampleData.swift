//
//  SampleData.swift
//  AstraStyle
//
//  Shared, believable sample data used across every Mock* repository and
//  SwiftUI preview (spec §31 "mocks sit behind the same protocols as
//  production... make previews and early UI work possible before the
//  backend exists"). One coherent wardrobe, real (as of this writing)
//  menswear brands, plausible prices — not lorem ipsum.
//

import Foundation

public enum SampleData {
    public static let userID = UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID()

    public static let profile = Profile(
        id: userID,
        displayName: "Marcus Bennett",
        avatarURL: nil,
        locationName: "Brooklyn, NY",
        timezone: "America/New_York",
        units: .imperial,
        theme: .dark,
        onboardingCompletedAt: Calendar.current.date(byAdding: .day, value: -74, to: .now),
        subscriptionTier: .premium
    )

    public static let styleProfile = StyleProfile(
        userID: userID,
        primaryIdentity: .modernHeritage,
        secondaryIdentities: [.quietLuxury, .smartCasual],
        preferredColors: ["navy", "olive", "stone", "charcoal", "white"],
        avoidedColors: ["neon green", "bright orange"],
        preferredFit: .tailored,
        formalityPreference: .balanced,
        logoTolerance: ToleranceLevel.low.score,
        trendTolerance: ToleranceLevel.medium.score,
        accessoryPreference: .moderate,
        styleSummary: "Marcus gravitates toward heritage American workwear filtered through a tailored, quiet-luxury lens — think Buck Mason meets Aimé Leon Dore, with Alden boots doing a lot of the heavy lifting."
    )

    /// A Style DNA result (spec §6.10), shaped exactly like what
    /// `POST /style-dna/generate` returns for `styleProfile` above.
    ///
    /// Deliberately NOT complete: `openQuestions` is non-empty and
    /// `measuredDimensions` names three axes, not eight, because that is the
    /// real shape of a result today — the §6.9 comparison set has fourteen pairs,
    /// so five dimensions arrive absent. A fixture showing eight confident
    /// axes would let a preview or a snapshot test look right while the
    /// screen's honest-degradation states went unexercised.
    public static let styleDNA = StyleDNA(
        primaryIdentity: .modernHeritage,
        identityBasis: "the identity you ranked first",
        secondaryInfluences: [.quietLuxury, .smartCasual],
        palette: StyleDNAPalette(
            preferredColors: ["charcoal", "navy", "oatmeal", "tobacco brown", "olive"],
            avoidedColors: ["neon brights", "cold silver grey"],
            rationale: "Modern Heritage runs on earth tones with one cold anchor, so a heavy jacket reads considered rather than costume."
        ),
        silhouette: StyleDNASilhouette(
            headline: "Straight and substantial, with a natural shoulder.",
            detail: "Heavier cloth holds its own shape, so a straight-leg trouser and an unpadded shoulder let it hang the way it was cut. You said you prefer a tailored fit, so that is the starting cut."
        ),
        signatureOpportunities: [
            StyleDNARecommendation(
                title: "A waxed cotton jacket in olive or brown",
                reason: "It is the one layer that anchors this whole direction and gets better with wear."
            ),
            StyleDNARecommendation(
                title: "A brown leather boot with a welted sole",
                reason: "Dresses up under a trouser and down over denim, so it earns its place twice."
            ),
            StyleDNARecommendation(
                title: "A jacket that works without a tie",
                reason: "You named business casual, which is the dress code that needs a jacket and forbids a suit."
            )
        ],
        wardrobePriorities: [
            StyleDNAPriority(
                rank: 1,
                title: "Cover the days you actually dress for",
                reason: "You said your week is mostly in an office with a business casual dress code. That decides how many of each piece you need before it decides which pieces."
            ),
            StyleDNAPriority(
                rank: 2,
                title: "Two trousers that take the same boot",
                reason: "A shared shoe is what turns separate pieces into a wardrobe."
            )
        ],
        summary: "You are Modern Heritage. The palette to build on is charcoal, navy, oatmeal, tobacco brown and olive. First thing to fix: cover the days you actually dress for.",
        formalityPreference: .balanced,
        logoTolerance: ToleranceLevel.low.score,
        trendTolerance: ToleranceLevel.medium.score,
        accessoryPreference: .moderate,
        knownInputs: [
            "the style identities you picked",
            "your work dress code",
            "the shape of your week",
            "3 of 3 style comparisons"
        ],
        openQuestions: [
            "Kyra has not asked you about texture, branding, how current you like things, accessories and contrast yet. Until she has, those parts lean on the direction you chose rather than on anything you said."
        ],
        measuredDimensions: ["colour_tolerance", "formality", "silhouette"],
        modelIdentifier: "astra-deterministic-stylist/1"
    )

    // Centimetres and kilograms, because that is what `body_profiles` stores —
    // see the header of BodyProfile.swift. This fixture previously held 71 and
    // 178, meaning 5'11" and 178lb, which the model reads as a man 71cm tall
    // weighing 178kg. Preview-only data, but it is the data every SwiftUI
    // preview and every mock-backed test runs against, so a nonsense frame here
    // becomes nonsense fit advice everywhere the feature is exercised by hand.
    // 5'11" / 178lb / 40" chest / 33" waist / 32" inseam / 15.5" neck:
    public static let bodyProfile = BodyProfile(
        userID: userID,
        heightCm: 180.3,
        weightKg: 80.7,
        chestCm: 101.6,
        waistCm: 83.8,
        inseamCm: 81.3,
        neckCm: 39.4,
        shoeSize: "10.5 US",
        shirtSize: "M",
        trouserSize: "33x32",
        fitNotes: [.longTorso, .broadChest]
    )

    public static let lifestyleProfile = LifestyleProfile(
        userID: userID,
        occupationCategory: .technology,
        dressCode: .businessCasual,
        commonOccasions: ["client meetings", "dinner with friends", "weekend errands", "date nights"],
        climatePreferences: ["four_season_northeast"],
        monthlyBudget: 350,
        preferredBrands: ["Buck Mason", "Todd Snyder", "Alden", "Drake's", "Aimé Leon Dore"],
        avoidedBrands: [],
        laundryCadence: .weekly
    )

}

// MARK: - Wardrobe fixtures
//
// The closet and outfit fixtures live in an extension rather than in the enum
// body above, and the reason is mechanical rather than aesthetic: 25 garments
// and their outfits are ~230 lines of data, which puts the enum past
// SwiftLint's `type_body_length` on its own. Splitting on the data/identity
// seam keeps both halves readable and means adding a garment doesn't
// eventually re-break the build. Same treatment as `SliceView`.

extension SampleData {
    // MARK: - Closet (25 items)

    public static let closetItems: [ClosetItem] = [
        ClosetItem(
            fixture: "Oxford Button-Down", brand: "J.Crew", category: .top, subcategory: "Dress Shirt",
            color: "white", pattern: .solid, material: ["cotton"], size: "M", fit: .tailored, formality: 55,
            price: 78, retailer: "J.Crew", wearCount: 22, daysSinceWorn: 3
        ),
        ClosetItem(
            fixture: "Merino Crewneck Sweater", brand: "Uniqlo", category: .top, subcategory: "Sweater",
            color: "navy", pattern: .solid, material: ["merino wool"], size: "M", fit: .regular,
            formality: 45, price: 50, retailer: "Uniqlo", wearCount: 30, daysSinceWorn: 1
        ),
        ClosetItem(
            fixture: "Heavyweight Pocket Tee", brand: "Buck Mason", category: .top, subcategory: "T-Shirt",
            color: "stone", pattern: .solid, material: ["cotton"], size: "M", fit: .regular, formality: 15,
            price: 38, retailer: "Buck Mason", wearCount: 41, daysSinceWorn: 0
        ),
        ClosetItem(
            fixture: "Chore Coat", brand: "Todd Snyder", category: .outerwear, subcategory: "Jacket",
            color: "olive", pattern: .solid, material: ["cotton canvas"], size: "M", fit: .relaxed,
            formality: 35, price: 248, retailer: "Todd Snyder", wearCount: 14, daysSinceWorn: 6
        ),
        ClosetItem(
            fixture: "Oxford Polo", brand: "Aimé Leon Dore", category: .top, subcategory: "Polo",
            color: "navy", pattern: .solid, material: ["cotton pique"], size: "M", fit: .tailored,
            formality: 30, price: 145, retailer: "Aimé Leon Dore", wearCount: 12, daysSinceWorn: 4
        ),
        ClosetItem(
            fixture: "Knit Polo", brand: "Drake's", category: .top, subcategory: "Polo", color: "olive",
            pattern: .solid, material: ["cotton"], size: "M", fit: .tailored, formality: 30, price: 195,
            retailer: "Drake's", wearCount: 8, daysSinceWorn: 12
        ),
        ClosetItem(
            fixture: "Flannel Shirt", brand: "L.L.Bean", category: .top, subcategory: "Casual Shirt",
            color: "charcoal", pattern: .plaid, material: ["cotton flannel"], size: "M", fit: .regular,
            formality: 20, price: 65, retailer: "L.L.Bean", wearCount: 19, daysSinceWorn: 9
        ),
        ClosetItem(
            fixture: "Oxford Cloth Button-Down", brand: "Ralph Lauren", category: .top,
            subcategory: "Dress Shirt", color: "light blue", pattern: .solid, material: ["cotton"],
            size: "M", fit: .tailored, formality: 60, price: 98, retailer: "Ralph Lauren", wearCount: 17,
            daysSinceWorn: 2
        ),
        ClosetItem(
            fixture: "Fleece Half-Zip", brand: "Patagonia", category: .outerwear, subcategory: "Fleece",
            color: "stone", pattern: .solid, material: ["polyester fleece"], size: "M", fit: .regular,
            formality: 10, price: 139, retailer: "Patagonia", wearCount: 25, daysSinceWorn: 5
        ),
        ClosetItem(
            fixture: "Slim Trousers", brand: "Bonobos", category: .bottom, subcategory: "Chinos",
            color: "stone", pattern: .solid, material: ["cotton twill"], size: "33x32", fit: .slim,
            formality: 50, price: 98, retailer: "Bonobos", wearCount: 28, daysSinceWorn: 3
        ),
        ClosetItem(
            fixture: "Selvedge Denim", brand: "Buck Mason", category: .bottom, subcategory: "Jeans",
            color: "indigo", pattern: .solid, material: ["cotton denim"], size: "33x32", fit: .slim,
            formality: 20, price: 128, retailer: "Buck Mason", wearCount: 55, daysSinceWorn: 0
        ),
        ClosetItem(
            fixture: "Wool Trousers", brand: "Theory", category: .bottom, subcategory: "Dress Trousers",
            color: "charcoal", pattern: .solid, material: ["wool"], size: "33x32", fit: .tailored,
            formality: 75, price: 245, retailer: "Theory", wearCount: 9, daysSinceWorn: 15
        ),
        ClosetItem(
            fixture: "Cargo Trousers", brand: "Norse Projects", category: .bottom,
            subcategory: "Cargo Pants", color: "olive", pattern: .solid, material: ["cotton"],
            size: "33x32", fit: .relaxed, formality: 20, price: 175, retailer: "Norse Projects",
            wearCount: 11, daysSinceWorn: 8
        ),
        ClosetItem(
            fixture: "Five-Pocket Twill Pants", brand: "J.Crew", category: .bottom,
            subcategory: "Casual Pants", color: "navy", pattern: .solid, material: ["cotton twill"],
            size: "33x32", fit: .tailored, formality: 40, price: 88, retailer: "J.Crew", wearCount: 16,
            daysSinceWorn: 4
        ),
        ClosetItem(
            fixture: "Shorts", brand: "Bonobos", category: .bottom, subcategory: "Chino Shorts",
            color: "stone", pattern: .solid, material: ["cotton"], size: "33", fit: .tailored,
            formality: 20, price: 78, retailer: "Bonobos", wearCount: 14, daysSinceWorn: 40
        ),
        ClosetItem(
            fixture: "Trench Coat", brand: "Todd Snyder", category: .outerwear, subcategory: "Overcoat",
            color: "khaki", pattern: .solid, material: ["cotton gabardine"], size: "M", fit: .tailored,
            formality: 65, price: 398, retailer: "Todd Snyder", wearCount: 6, daysSinceWorn: 20
        ),
        ClosetItem(
            fixture: "Wool Overcoat", brand: "Suitsupply", category: .outerwear, subcategory: "Overcoat",
            color: "charcoal", pattern: .solid, material: ["wool"], size: "M", fit: .tailored,
            formality: 80, price: 449, retailer: "Suitsupply", wearCount: 5, daysSinceWorn: 30
        ),
        ClosetItem(
            fixture: "Waxed Trucker Jacket", brand: "Taylor Stitch", category: .outerwear,
            subcategory: "Jacket", color: "olive", pattern: .solid, material: ["waxed cotton"], size: "M",
            fit: .regular, formality: 25, price: 248, retailer: "Taylor Stitch", wearCount: 18,
            daysSinceWorn: 7
        ),
        ClosetItem(
            fixture: "Suede Chukka Boots", brand: "Clarks", category: .shoes, subcategory: "Boots",
            color: "sand", pattern: .solid, material: ["suede"], size: "10.5", fit: .regular, formality: 45,
            price: 150, retailer: "Clarks", wearCount: 33, daysSinceWorn: 1
        ),
        ClosetItem(
            fixture: "Leather Chelsea Boots", brand: "Alden", category: .shoes, subcategory: "Boots",
            color: "brown", pattern: .solid, material: ["leather"], size: "10.5", fit: .regular,
            formality: 60, price: 598, retailer: "Alden", wearCount: 27, daysSinceWorn: 2
        ),
        ClosetItem(
            fixture: "Achilles Low Sneakers", brand: "Common Projects", category: .shoes,
            subcategory: "Sneakers", color: "white", pattern: .solid, material: ["leather"], size: "10.5",
            fit: .regular, formality: 25, price: 445, retailer: "Common Projects", wearCount: 61,
            daysSinceWorn: 0
        ),
        ClosetItem(
            fixture: "Penny Loafers", brand: "G.H. Bass", category: .shoes, subcategory: "Loafers",
            color: "brown", pattern: .solid, material: ["leather"], size: "10.5", fit: .regular,
            formality: 55, price: 175, retailer: "G.H. Bass", wearCount: 15, daysSinceWorn: 10
        ),
        ClosetItem(
            fixture: "Canvas Low-Tops", brand: "Vans", category: .shoes, subcategory: "Sneakers",
            color: "navy", pattern: .solid, material: ["canvas"], size: "10.5", fit: .regular,
            formality: 10, price: 65, retailer: "Vans", wearCount: 24, daysSinceWorn: 3
        ),
        ClosetItem(
            fixture: "Automatic Field Watch", brand: "Hamilton", category: .watch, subcategory: "Watch",
            color: "steel", pattern: .solid, material: ["stainless steel"], size: "38mm", fit: nil,
            formality: 55, price: 595, retailer: "Hamilton", wearCount: 90, daysSinceWorn: 0
        ),
        ClosetItem(
            fixture: "Leather Belt", brand: "J.Crew", category: .accessory, subcategory: "Belt",
            color: "brown", pattern: .solid, material: ["leather"], size: "34", fit: nil, formality: 40,
            price: 58, retailer: "J.Crew", wearCount: 70, daysSinceWorn: 0
        )
    ]

    // MARK: - Outfits

    public static let heroOutfit = Outfit(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000101") ?? UUID(),
        userID: userID,
        name: "Client Meeting, Elevated Casual",
        description: "The olive knit polo grounds the look, the stone trousers keep it light for the weather, and the chukkas bridge smart and casual without trying too hard.",
        occasionTags: ["client meeting", "smart casual"],
        weatherMin: 60,
        weatherMax: 75,
        formalityScore: 58,
        compatibilityScore: 92,
        source: .aiGenerated,
        isFavorite: false
    )

    public static let alternativeOutfits: [Outfit] = [
        Outfit(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000102") ?? UUID(),
            userID: userID,
            name: "Denim & Oxford",
            description: "A reliable fallback: Oxford button-down, selvedge denim, Common Projects.",
            occasionTags: ["casual", "errands"],
            weatherMin: 55,
            weatherMax: 78,
            formalityScore: 42,
            compatibilityScore: 87,
            source: .aiGenerated
        ),
        Outfit(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000103") ?? UUID(),
            userID: userID,
            name: "Dinner Out",
            description: "Wool trousers and a chore coat over the Oxford polo — sharp without a jacket.",
            occasionTags: ["dinner", "date night"],
            weatherMin: 50,
            weatherMax: 70,
            formalityScore: 68,
            compatibilityScore: 89,
            source: .aiGenerated
        )
    ]

    public static func heroOutfitItems() -> [OutfitItem] {
        [
            OutfitItem(outfitID: heroOutfit.id, closetItemID: closetItems[5].id, role: .top, sortOrder: 0),      // Drake's knit polo
            OutfitItem(outfitID: heroOutfit.id, closetItemID: closetItems[9].id, role: .bottom, sortOrder: 1),   // Bonobos slim trousers
            OutfitItem(outfitID: heroOutfit.id, closetItemID: closetItems[18].id, role: .shoes, sortOrder: 2),   // Clarks chukka boots
            OutfitItem(outfitID: heroOutfit.id, closetItemID: closetItems[23].id, role: .watch, sortOrder: 3)   // Hamilton field watch
        ]
    }

    public static let weatherSnapshot = WeatherSnapshot(
        temperatureHigh: 74,
        temperatureLow: 61,
        apparentTemperature: 73,
        condition: .partlyCloudy,
        precipitationChance: 0.1,
        windSpeed: 8,
        humidity: 0.45,
        locationName: "Brooklyn, NY"
    )

    public static let scheduleSnapshot = ScheduleSnapshot(
        eventCount: 3,
        earliestFormalityLevel: .balanced,
        headline: "Client meeting at 10:30 AM"
    )

    public static func dailyBrief(for date: Date = .now) -> DailyBrief {
        DailyBrief(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000201") ?? UUID(),
            userID: userID,
            briefDate: date,
            primaryOutfitID: heroOutfit.id,
            alternativeOutfitIDs: alternativeOutfits.map(\.id),
            weatherSnapshot: weatherSnapshot,
            scheduleSnapshot: scheduleSnapshot,
            kyraMessage: "I'd wear the olive knit polo, stone trousers, and white sneakers today. It fits the weather and moves cleanly from work to dinner."
        )
    }

    public static let wardrobeScore = WardrobeScore(
        overall: 78,
        versatility: 74,
        fitConfidence: 82,
        occasionCoverage: 71,
        colorCohesion: 88,
        wearUtilization: 69,
        condition: 91,
        redundancyControl: 76
    )

}

// MARK: - Fixture construction

private extension ClosetItem {
    /// One row of the fixture closet above.
    ///
    /// An initialiser rather than a `SampleData.item(...)` factory function.
    /// It is literally initialising a `ClosetItem` and reads that way at all
    /// 25 call sites — and SwiftLint's `function_parameter_count`, which is
    /// aimed at behavioural functions and deliberately exempts initialisers
    /// (a value type with many fields is not a design smell), then applies
    /// correctly instead of flagging a data row as a god-function.
    ///
    /// `daysSinceWorn` is a fixture-only convenience: it is turned into a real
    /// `lastWornAt` date and a plausible `laundryState` below, so the table
    /// above never has to write `Calendar.current.date(byAdding:)` 25 times.
    init(
        fixture name: String,
        brand: String,
        category: ClothingCategory,
        subcategory: String,
        color: String,
        pattern: GarmentPattern,
        material: [String],
        size: String,
        fit: ItemFit?,
        formality: Int,
        price: Decimal,
        retailer: String,
        wearCount: Int,
        daysSinceWorn: Int
    ) {
        self.init(
            id: UUID(),
            userID: SampleData.userID,
            name: name,
            brand: brand,
            category: category,
            subcategory: subcategory,
            primaryColor: color,
            pattern: pattern,
            material: material,
            size: size,
            fit: fit,
            condition: .good,
            seasonality: [.allSeason],
            formalityScore: formality,
            purchaseDate: Calendar.current.date(byAdding: .month, value: -Int.random(in: 2...20), to: .now),
            pricePaid: price,
            currency: "USD",
            retailer: retailer,
            wearCount: wearCount,
            lastWornAt: Calendar.current.date(byAdding: .day, value: -daysSinceWorn, to: .now),
            laundryState: daysSinceWorn == 0 ? .wornOnce : .clean,
            availabilityState: .available
        )
    }
}
