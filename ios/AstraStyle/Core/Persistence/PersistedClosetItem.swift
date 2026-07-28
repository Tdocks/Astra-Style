//
//  PersistedClosetItem.swift
//  AstraStyle
//
//  SwiftData cache of `ClosetItem` (spec §7 "Cached closet and outfits
//  remain viewable" offline). Deliberately a separate type from the
//  Domain `ClosetItem` value type — see `PersistenceMapping.swift` for the
//  conversion functions in both directions. Keeping these distinct means
//  SwiftData's `@Model` macro (which requires a reference type with
//  mutable stored properties) never leaks into `Domain`, which stays pure
//  value types per spec §8's architecture.
//

import Foundation
import SwiftData

@Model
public final class PersistedClosetItem {
    @Attribute(.unique) public var id: UUID
    public var userID: UUID
    public var name: String
    public var brand: String?
    public var categoryRaw: String
    public var subcategory: String?
    public var primaryColor: String?
    public var secondaryColors: [String]
    public var patternRaw: String?
    public var material: [String]
    public var size: String?
    public var fitRaw: String?
    public var conditionRaw: String?
    public var seasonalityRaw: [String]
    public var formalityScore: Int?
    public var warmthScore: Int?
    public var waterResistanceScore: Int?
    public var purchaseDate: Date?
    public var pricePaidMinorUnits: Int?
    public var currency: String?
    public var retailer: String?
    public var productURLString: String?
    public var wearCount: Int
    public var lastWornAt: Date?
    public var laundryStateRaw: String
    public var availabilityStateRaw: String
    public var archivedAt: Date?
    public var primaryImageStoragePath: String?
    public var createdAt: Date
    public var updatedAt: Date

    /// Set when this row was created/edited offline and hasn't been
    /// confirmed by a successful server round trip yet — lets the Closet
    /// UI show a subtle "syncing" affordance (spec §7 "Local edits queue
    /// for sync").
    public var pendingSync: Bool

    public init(
        id: UUID,
        userID: UUID,
        name: String,
        brand: String?,
        categoryRaw: String,
        subcategory: String?,
        primaryColor: String?,
        secondaryColors: [String],
        patternRaw: String?,
        material: [String],
        size: String?,
        fitRaw: String?,
        conditionRaw: String?,
        seasonalityRaw: [String],
        formalityScore: Int?,
        warmthScore: Int?,
        waterResistanceScore: Int?,
        purchaseDate: Date?,
        pricePaidMinorUnits: Int?,
        currency: String?,
        retailer: String?,
        productURLString: String?,
        wearCount: Int,
        lastWornAt: Date?,
        laundryStateRaw: String,
        availabilityStateRaw: String,
        archivedAt: Date?,
        primaryImageStoragePath: String?,
        createdAt: Date,
        updatedAt: Date,
        pendingSync: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.brand = brand
        self.categoryRaw = categoryRaw
        self.subcategory = subcategory
        self.primaryColor = primaryColor
        self.secondaryColors = secondaryColors
        self.patternRaw = patternRaw
        self.material = material
        self.size = size
        self.fitRaw = fitRaw
        self.conditionRaw = conditionRaw
        self.seasonalityRaw = seasonalityRaw
        self.formalityScore = formalityScore
        self.warmthScore = warmthScore
        self.waterResistanceScore = waterResistanceScore
        self.purchaseDate = purchaseDate
        self.pricePaidMinorUnits = pricePaidMinorUnits
        self.currency = currency
        self.retailer = retailer
        self.productURLString = productURLString
        self.wearCount = wearCount
        self.lastWornAt = lastWornAt
        self.laundryStateRaw = laundryStateRaw
        self.availabilityStateRaw = availabilityStateRaw
        self.archivedAt = archivedAt
        self.primaryImageStoragePath = primaryImageStoragePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pendingSync = pendingSync
    }
}
