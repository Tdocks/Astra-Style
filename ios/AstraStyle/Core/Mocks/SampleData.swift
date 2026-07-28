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
        formalityPreference: .businessCasual,
        logoTolerance: .low,
        trendTolerance: .medium,
        accessoryPreference: .moderate,
        styleSummary: "Marcus gravitates toward heritage American workwear filtered through a tailored, quiet-luxury lens — think Buck Mason meets Aimé Leon Dore, with Alden boots doing a lot of the heavy lifting."
    )

    public static let bodyProfile = BodyProfile(
        userID: userID,
        heightValue: 71,
        weightValue: 178,
        chest: 40,
        waist: 33,
        inseam: 32,
        neck: 15.5,
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

    // MARK: - Closet (25 items)

    public static let closetItems: [ClosetItem] = [
        item(name: "Oxford Button-Down", brand: "J.Crew", category: .top, subcategory: "Dress Shirt", color: "white", pattern: .solid, material: ["cotton"], size: "M", fit: .tailored, formality: 55, price: 78, retailer: "J.Crew", wearCount: 22, daysSinceWorn: 3),
        item(name: "Merino Crewneck Sweater", brand: "Uniqlo", category: .top, subcategory: "Sweater", color: "navy", pattern: .solid, material: ["merino wool"], size: "M", fit: .regular, formality: 45, price: 50, retailer: "Uniqlo", wearCount: 30, daysSinceWorn: 1),
        item(name: "Heavyweight Pocket Tee", brand: "Buck Mason", category: .top, subcategory: "T-Shirt", color: "stone", pattern: .solid, material: ["cotton"], size: "M", fit: .regular, formality: 15, price: 38, retailer: "Buck Mason", wearCount: 41, daysSinceWorn: 0),
        item(name: "Chore Coat", brand: "Todd Snyder", category: .outerwear, subcategory: "Jacket", color: "olive", pattern: .solid, material: ["cotton canvas"], size: "M", fit: .relaxed, formality: 35, price: 248, retailer: "Todd Snyder", wearCount: 14, daysSinceWorn: 6),
        item(name: "Oxford Polo", brand: "Aimé Leon Dore", category: .top, subcategory: "Polo", color: "navy", pattern: .solid, material: ["cotton pique"], size: "M", fit: .tailored, formality: 30, price: 145, retailer: "Aimé Leon Dore", wearCount: 12, daysSinceWorn: 4),
        item(name: "Knit Polo", brand: "Drake's", category: .top, subcategory: "Polo", color: "olive", pattern: .solid, material: ["cotton"], size: "M", fit: .tailored, formality: 30, price: 195, retailer: "Drake's", wearCount: 8, daysSinceWorn: 12),
        item(name: "Flannel Shirt", brand: "L.L.Bean", category: .top, subcategory: "Casual Shirt", color: "charcoal", pattern: .plaid, material: ["cotton flannel"], size: "M", fit: .regular, formality: 20, price: 65, retailer: "L.L.Bean", wearCount: 19, daysSinceWorn: 9),
        item(name: "Oxford Cloth Button-Down", brand: "Ralph Lauren", category: .top, subcategory: "Dress Shirt", color: "light blue", pattern: .solid, material: ["cotton"], size: "M", fit: .tailored, formality: 60, price: 98, retailer: "Ralph Lauren", wearCount: 17, daysSinceWorn: 2),
        item(name: "Fleece Half-Zip", brand: "Patagonia", category: .outerwear, subcategory: "Fleece", color: "stone", pattern: .solid, material: ["polyester fleece"], size: "M", fit: .regular, formality: 10, price: 139, retailer: "Patagonia", wearCount: 25, daysSinceWorn: 5),
        item(name: "Slim Trousers", brand: "Bonobos", category: .bottom, subcategory: "Chinos", color: "stone", pattern: .solid, material: ["cotton twill"], size: "33x32", fit: .slim, formality: 50, price: 98, retailer: "Bonobos", wearCount: 28, daysSinceWorn: 3),
        item(name: "Selvedge Denim", brand: "Buck Mason", category: .bottom, subcategory: "Jeans", color: "indigo", pattern: .solid, material: ["cotton denim"], size: "33x32", fit: .slim, formality: 20, price: 128, retailer: "Buck Mason", wearCount: 55, daysSinceWorn: 0),
        item(name: "Wool Trousers", brand: "Theory", category: .bottom, subcategory: "Dress Trousers", color: "charcoal", pattern: .solid, material: ["wool"], size: "33x32", fit: .tailored, formality: 75, price: 245, retailer: "Theory", wearCount: 9, daysSinceWorn: 15),
        item(name: "Cargo Trousers", brand: "Norse Projects", category: .bottom, subcategory: "Cargo Pants", color: "olive", pattern: .solid, material: ["cotton"], size: "33x32", fit: .relaxed, formality: 20, price: 175, retailer: "Norse Projects", wearCount: 11, daysSinceWorn: 8),
        item(name: "Five-Pocket Twill Pants", brand: "J.Crew", category: .bottom, subcategory: "Casual Pants", color: "navy", pattern: .solid, material: ["cotton twill"], size: "33x32", fit: .tailored, formality: 40, price: 88, retailer: "J.Crew", wearCount: 16, daysSinceWorn: 4),
        item(name: "Shorts", brand: "Bonobos", category: .bottom, subcategory: "Chino Shorts", color: "stone", pattern: .solid, material: ["cotton"], size: "33", fit: .tailored, formality: 20, price: 78, retailer: "Bonobos", wearCount: 14, daysSinceWorn: 40),
        item(name: "Trench Coat", brand: "Todd Snyder", category: .outerwear, subcategory: "Overcoat", color: "khaki", pattern: .solid, material: ["cotton gabardine"], size: "M", fit: .tailored, formality: 65, price: 398, retailer: "Todd Snyder", wearCount: 6, daysSinceWorn: 20),
        item(name: "Wool Overcoat", brand: "Suitsupply", category: .outerwear, subcategory: "Overcoat", color: "charcoal", pattern: .solid, material: ["wool"], size: "M", fit: .tailored, formality: 80, price: 449, retailer: "Suitsupply", wearCount: 5, daysSinceWorn: 30),
        item(name: "Waxed Trucker Jacket", brand: "Taylor Stitch", category: .outerwear, subcategory: "Jacket", color: "olive", pattern: .solid, material: ["waxed cotton"], size: "M", fit: .regular, formality: 25, price: 248, retailer: "Taylor Stitch", wearCount: 18, daysSinceWorn: 7),
        item(name: "Suede Chukka Boots", brand: "Clarks", category: .shoes, subcategory: "Boots", color: "sand", pattern: .solid, material: ["suede"], size: "10.5", fit: .regular, formality: 45, price: 150, retailer: "Clarks", wearCount: 33, daysSinceWorn: 1),
        item(name: "Leather Chelsea Boots", brand: "Alden", category: .shoes, subcategory: "Boots", color: "brown", pattern: .solid, material: ["leather"], size: "10.5", fit: .regular, formality: 60, price: 598, retailer: "Alden", wearCount: 27, daysSinceWorn: 2),
        item(name: "Achilles Low Sneakers", brand: "Common Projects", category: .shoes, subcategory: "Sneakers", color: "white", pattern: .solid, material: ["leather"], size: "10.5", fit: .regular, formality: 25, price: 445, retailer: "Common Projects", wearCount: 61, daysSinceWorn: 0),
        item(name: "Penny Loafers", brand: "G.H. Bass", category: .shoes, subcategory: "Loafers", color: "brown", pattern: .solid, material: ["leather"], size: "10.5", fit: .regular, formality: 55, price: 175, retailer: "G.H. Bass", wearCount: 15, daysSinceWorn: 10),
        item(name: "Canvas Low-Tops", brand: "Vans", category: .shoes, subcategory: "Sneakers", color: "navy", pattern: .solid, material: ["canvas"], size: "10.5", fit: .regular, formality: 10, price: 65, retailer: "Vans", wearCount: 24, daysSinceWorn: 3),
        item(name: "Automatic Field Watch", brand: "Hamilton", category: .watch, subcategory: "Watch", color: "steel", pattern: .solid, material: ["stainless steel"], size: "38mm", fit: nil, formality: 55, price: 595, retailer: "Hamilton", wearCount: 90, daysSinceWorn: 0),
        item(name: "Leather Belt", brand: "J.Crew", category: .accessory, subcategory: "Belt", color: "brown", pattern: .solid, material: ["leather"], size: "34", fit: nil, formality: 40, price: 58, retailer: "J.Crew", wearCount: 70, daysSinceWorn: 0),
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
        source: .kyraGenerated,
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
            source: .kyraGenerated
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
            source: .kyraGenerated
        ),
    ]

    public static func heroOutfitItems() -> [OutfitItem] {
        [
            OutfitItem(outfitID: heroOutfit.id, closetItemID: closetItems[5].id, role: .top, sortOrder: 0),      // Drake's knit polo
            OutfitItem(outfitID: heroOutfit.id, closetItemID: closetItems[9].id, role: .bottom, sortOrder: 1),   // Bonobos slim trousers
            OutfitItem(outfitID: heroOutfit.id, closetItemID: closetItems[18].id, role: .shoes, sortOrder: 2),   // Clarks chukka boots
            OutfitItem(outfitID: heroOutfit.id, closetItemID: closetItems[23].id, role: .watch, sortOrder: 3),   // Hamilton field watch
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
        earliestFormalityLevel: .businessCasual,
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

    // MARK: - Helpers

    private static func item(
        name: String,
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
    ) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: userID,
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
