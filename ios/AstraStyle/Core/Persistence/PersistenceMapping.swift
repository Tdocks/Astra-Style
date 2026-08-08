//
//  PersistenceMapping.swift
//  AstraStyle
//
//  Explicit, two-way mapping between SwiftData `@Model` cache rows and
//  their `Domain` value-type counterparts. Kept in one file so the two
//  representations of each entity are easy to keep in sync by inspection.
//

import Foundation
import SwiftData

public enum PersistenceMapping {

    // MARK: - ClosetItem

    public static func domainModel(from persisted: PersistedClosetItem) -> ClosetItem {
        ClosetItem(
            id: persisted.id,
            userID: persisted.userID,
            name: persisted.name,
            brand: persisted.brand,
            category: ClothingCategory(rawValue: persisted.categoryRaw) ?? .top,
            subcategory: persisted.subcategory,
            primaryColor: persisted.primaryColor,
            secondaryColors: persisted.secondaryColors,
            pattern: persisted.patternRaw.flatMap(GarmentPattern.init(rawValue:)),
            material: persisted.material,
            size: persisted.size,
            fit: persisted.fitRaw.flatMap(ItemFit.init(rawValue:)),
            condition: persisted.conditionRaw.flatMap(ItemCondition.init(rawValue:)),
            seasonality: persisted.seasonalityRaw.compactMap(Season.init(rawValue:)),
            formalityScore: persisted.formalityScore,
            warmthScore: persisted.warmthScore,
            waterResistanceScore: persisted.waterResistanceScore,
            purchaseDate: persisted.purchaseDate,
            pricePaid: persisted.pricePaidMinorUnits.map { Decimal($0) / 100 },
            currency: persisted.currency,
            retailer: persisted.retailer,
            productURL: persisted.productURLString.flatMap(URL.init(string:)),
            wearCount: persisted.wearCount,
            lastWornAt: persisted.lastWornAt,
            laundryState: LaundryState(rawValue: persisted.laundryStateRaw) ?? .clean,
            availabilityState: AvailabilityState(rawValue: persisted.availabilityStateRaw) ?? .available,
            archivedAt: persisted.archivedAt,
            createdAt: persisted.createdAt,
            updatedAt: persisted.updatedAt
        )
    }

    public static func persistedModel(from item: ClosetItem, pendingSync: Bool = false) -> PersistedClosetItem {
        PersistedClosetItem(
            id: item.id,
            userID: item.userID,
            name: item.name,
            brand: item.brand,
            categoryRaw: item.category.rawValue,
            subcategory: item.subcategory,
            primaryColor: item.primaryColor,
            secondaryColors: item.secondaryColors,
            patternRaw: item.pattern?.rawValue,
            material: item.material,
            size: item.size,
            fitRaw: item.fit?.rawValue,
            conditionRaw: item.condition?.rawValue,
            seasonalityRaw: item.seasonality.map(\.rawValue),
            formalityScore: item.formalityScore,
            warmthScore: item.warmthScore,
            waterResistanceScore: item.waterResistanceScore,
            purchaseDate: item.purchaseDate,
            pricePaidMinorUnits: item.pricePaid.map { Int(truncating: ($0 * 100) as NSDecimalNumber) },
            currency: item.currency,
            retailer: item.retailer,
            productURLString: item.productURL?.absoluteString,
            wearCount: item.wearCount,
            lastWornAt: item.lastWornAt,
            laundryStateRaw: item.laundryState.rawValue,
            availabilityStateRaw: item.availabilityState.rawValue,
            archivedAt: item.archivedAt,
            primaryImageStoragePath: nil,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            pendingSync: pendingSync
        )
    }

    /// Mutates an existing `PersistedClosetItem` in place to match `item`,
    /// for update-in-place call sites rather than delete+reinsert, which
    /// would needlessly churn the
    /// SwiftData row's identity. Mirrors `persistedModel(from:pendingSync:)`
    /// field-for-field, minus `id`/`createdAt` (identity/history, never
    /// updated) and `primaryImageStoragePath` (not sourced from `ClosetItem`
    /// in either mapping direction today).
    public static func update(_ persisted: PersistedClosetItem, with item: ClosetItem) {
        persisted.userID = item.userID
        persisted.name = item.name
        persisted.brand = item.brand
        persisted.categoryRaw = item.category.rawValue
        persisted.subcategory = item.subcategory
        persisted.primaryColor = item.primaryColor
        persisted.secondaryColors = item.secondaryColors
        persisted.patternRaw = item.pattern?.rawValue
        persisted.material = item.material
        persisted.size = item.size
        persisted.fitRaw = item.fit?.rawValue
        persisted.conditionRaw = item.condition?.rawValue
        persisted.seasonalityRaw = item.seasonality.map(\.rawValue)
        persisted.formalityScore = item.formalityScore
        persisted.warmthScore = item.warmthScore
        persisted.waterResistanceScore = item.waterResistanceScore
        persisted.purchaseDate = item.purchaseDate
        persisted.pricePaidMinorUnits = item.pricePaid.map { Int(truncating: ($0 * 100) as NSDecimalNumber) }
        persisted.currency = item.currency
        persisted.retailer = item.retailer
        persisted.productURLString = item.productURL?.absoluteString
        persisted.wearCount = item.wearCount
        persisted.lastWornAt = item.lastWornAt
        persisted.laundryStateRaw = item.laundryState.rawValue
        persisted.availabilityStateRaw = item.availabilityState.rawValue
        persisted.archivedAt = item.archivedAt
        persisted.updatedAt = item.updatedAt
    }

    // MARK: - Outfit

    public static func domainModel(from persisted: PersistedOutfit) -> Outfit {
        Outfit(
            id: persisted.id,
            userID: persisted.userID,
            name: persisted.name,
            description: persisted.itemDescription,
            occasionTags: persisted.occasionTags,
            formalityScore: persisted.formalityScore,
            compatibilityScore: persisted.compatibilityScore,
            source: OutfitSource(rawValue: persisted.sourceRaw) ?? .aiGenerated,
            heroImageURL: persisted.heroImageURLString.flatMap(URL.init(string:)),
            isFavorite: persisted.isFavorite,
            createdAt: persisted.createdAt,
            updatedAt: persisted.updatedAt
        )
    }

    public static func persistedModel(from outfit: Outfit, items: [OutfitItem], pendingSync: Bool = false) -> PersistedOutfit {
        let encodedItems = (try? JSONEncoder.astraDefault.encode(items)) ?? Data()
        return PersistedOutfit(
            id: outfit.id,
            userID: outfit.userID,
            name: outfit.name,
            itemDescription: outfit.description,
            occasionTags: outfit.occasionTags,
            formalityScore: outfit.formalityScore,
            compatibilityScore: outfit.compatibilityScore,
            sourceRaw: outfit.source.rawValue,
            heroImageURLString: outfit.heroImageURL?.absoluteString,
            isFavorite: outfit.isFavorite,
            createdAt: outfit.createdAt,
            updatedAt: outfit.updatedAt,
            encodedItems: encodedItems,
            pendingSync: pendingSync
        )
    }

    public static func domainOutfitItems(from persisted: PersistedOutfit) -> [OutfitItem] {
        (try? JSONDecoder.astraDefault.decode([OutfitItem].self, from: persisted.encodedItems)) ?? []
    }

    /// Mutates an existing `PersistedOutfit` in place to match `outfit`,
    /// mirroring `update(_:with:)` for `PersistedClosetItem` above.
    /// Deliberately leaves `encodedItems` untouched — `Outfit` carries no
    /// item list of its own, and a caller with fresh items to cache calls
    /// `OutfitCaching.upsert(_:items:)` or `upsertItems(_:forOutfit:)`
    /// instead, which set it explicitly.
    public static func update(_ persisted: PersistedOutfit, with outfit: Outfit) {
        persisted.userID = outfit.userID
        persisted.name = outfit.name
        persisted.itemDescription = outfit.description
        persisted.occasionTags = outfit.occasionTags
        persisted.formalityScore = outfit.formalityScore
        persisted.compatibilityScore = outfit.compatibilityScore
        persisted.sourceRaw = outfit.source.rawValue
        persisted.heroImageURLString = outfit.heroImageURL?.absoluteString
        persisted.isFavorite = outfit.isFavorite
        persisted.updatedAt = outfit.updatedAt
    }

    // MARK: - DailyBrief

    public static func domainModel(from persisted: PersistedDailyBrief) -> DailyBrief {
        DailyBrief(
            id: persisted.id,
            userID: persisted.userID,
            briefDate: persisted.briefDate,
            primaryOutfitID: persisted.primaryOutfitID,
            alternativeOutfitIDs: persisted.alternativeOutfitIDs,
            weatherSnapshot: persisted.encodedWeatherSnapshot.flatMap { try? JSONDecoder.astraDefault.decode(WeatherSnapshot.self, from: $0) },
            scheduleSnapshot: persisted.encodedScheduleSnapshot.flatMap { try? JSONDecoder.astraDefault.decode(ScheduleSnapshot.self, from: $0) },
            kyraMessage: persisted.kyraMessage
        )
    }

    public static func persistedModel(from brief: DailyBrief) -> PersistedDailyBrief {
        PersistedDailyBrief(
            id: brief.id,
            userID: brief.userID,
            briefDate: brief.briefDate,
            primaryOutfitID: brief.primaryOutfitID,
            alternativeOutfitIDs: brief.alternativeOutfitIDs,
            kyraMessage: brief.kyraMessage,
            encodedWeatherSnapshot: brief.weatherSnapshot.flatMap { try? JSONEncoder.astraDefault.encode($0) },
            encodedScheduleSnapshot: brief.scheduleSnapshot.flatMap { try? JSONEncoder.astraDefault.encode($0) },
            cachedAt: .now
        )
    }
}
