//
//  ClosetItem.swift
//  AstraStyle
//
//  Maps `closet_items` (spec §9). This is the central node of the Wardrobe
//  Graph (spec §10).
//

import Foundation

public struct ClosetItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var userID: UUID
    public var name: String
    public var brand: String?
    public var category: ClothingCategory
    public var subcategory: String?
    public var primaryColor: String?
    public var secondaryColors: [String]
    public var pattern: GarmentPattern?
    public var material: [String]
    public var size: String?
    public var fit: ItemFit?
    public var condition: ItemCondition?
    public var seasonality: [Season]
    public var formalityScore: Int?
    public var warmthScore: Int?
    public var waterResistanceScore: Int?
    public var purchaseDate: Date?
    public var pricePaid: Decimal?
    public var currency: String?
    public var retailer: String?
    public var productURL: URL?
    public var wearCount: Int
    public var lastWornAt: Date?
    public var laundryState: LaundryState
    public var availabilityState: AvailabilityState
    public var archivedAt: Date?

    /// pgvector embedding used server-side for compatibility/duplicate
    /// search. Opaque to the client.
    public var embedding: [Float]?

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        userID: UUID,
        name: String,
        brand: String? = nil,
        category: ClothingCategory,
        subcategory: String? = nil,
        primaryColor: String? = nil,
        secondaryColors: [String] = [],
        pattern: GarmentPattern? = nil,
        material: [String] = [],
        size: String? = nil,
        fit: ItemFit? = nil,
        condition: ItemCondition? = nil,
        seasonality: [Season] = [],
        formalityScore: Int? = nil,
        warmthScore: Int? = nil,
        waterResistanceScore: Int? = nil,
        purchaseDate: Date? = nil,
        pricePaid: Decimal? = nil,
        currency: String? = nil,
        retailer: String? = nil,
        productURL: URL? = nil,
        wearCount: Int = 0,
        lastWornAt: Date? = nil,
        laundryState: LaundryState = .clean,
        availabilityState: AvailabilityState = .available,
        archivedAt: Date? = nil,
        embedding: [Float]? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.brand = brand
        self.category = category
        self.subcategory = subcategory
        self.primaryColor = primaryColor
        self.secondaryColors = secondaryColors
        self.pattern = pattern
        self.material = material
        self.size = size
        self.fit = fit
        self.condition = condition
        self.seasonality = seasonality
        self.formalityScore = formalityScore
        self.warmthScore = warmthScore
        self.waterResistanceScore = waterResistanceScore
        self.purchaseDate = purchaseDate
        self.pricePaid = pricePaid
        self.currency = currency
        self.retailer = retailer
        self.productURL = productURL
        self.wearCount = wearCount
        self.lastWornAt = lastWornAt
        self.laundryState = laundryState
        self.availabilityState = availabilityState
        self.archivedAt = archivedAt
        self.embedding = embedding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case brand
        case category
        case subcategory
        case primaryColor = "primary_color"
        case secondaryColors = "secondary_colors"
        case pattern
        case material
        case size
        case fit
        case condition
        case seasonality
        case formalityScore = "formality_score"
        case warmthScore = "warmth_score"
        case waterResistanceScore = "water_resistance_score"
        case purchaseDate = "purchase_date"
        case pricePaid = "price_paid"
        case currency
        case retailer
        case productURL = "product_url"
        case wearCount = "wear_count"
        case lastWornAt = "last_worn_at"
        case laundryState = "laundry_state"
        case availabilityState = "availability_state"
        case archivedAt = "archived_at"
        case embedding
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// True once soft-deleted via `archived_at` (spec §9 "soft deletion
    /// where appropriate").
    public var isArchived: Bool { archivedAt != nil }

    /// Whether the item can be scheduled into today's outfit right now.
    public var isWearableToday: Bool {
        !isArchived && laundryState == .clean && availabilityState == .available
    }
}
