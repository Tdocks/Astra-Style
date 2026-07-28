//
//  ProductCandidate.swift
//  AstraStyle
//
//  Maps `product_candidates` (spec §9). Populated either from the curated
//  admin catalog, a retailer affiliate feed, or an on-demand analysis of a
//  user-pasted URL (spec §17 "Product ingestion").
//

import Foundation

public struct ProductCandidate: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var canonicalURL: URL
    public var retailer: String
    public var brand: String?
    public var name: String
    public var category: ClothingCategory
    public var price: Decimal?
    public var currency: String?
    public var imageURL: URL?
    public var affiliateURL: URL?

    /// e.g. in-stock sizes, ship dates — shape varies by retailer feed.
    public var availability: AstraJSONValue?

    /// e.g. material, fit notes, color — shape varies by retailer feed.
    public var attributes: AstraJSONValue?

    public var lastCheckedAt: Date?

    public init(
        id: UUID,
        canonicalURL: URL,
        retailer: String,
        brand: String? = nil,
        name: String,
        category: ClothingCategory,
        price: Decimal? = nil,
        currency: String? = nil,
        imageURL: URL? = nil,
        affiliateURL: URL? = nil,
        availability: AstraJSONValue? = nil,
        attributes: AstraJSONValue? = nil,
        lastCheckedAt: Date? = nil
    ) {
        self.id = id
        self.canonicalURL = canonicalURL
        self.retailer = retailer
        self.brand = brand
        self.name = name
        self.category = category
        self.price = price
        self.currency = currency
        self.imageURL = imageURL
        self.affiliateURL = affiliateURL
        self.availability = availability
        self.attributes = attributes
        self.lastCheckedAt = lastCheckedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case canonicalURL = "canonical_url"
        case retailer
        case brand
        case name
        case category
        case price
        case currency
        case imageURL = "image_url"
        case affiliateURL = "affiliate_url"
        case availability
        case attributes
        case lastCheckedAt = "last_checked_at"
    }

    /// `true` when an affiliate relationship exists and must be disclosed
    /// per spec §17 "Sponsored products must be labeled."
    public var isAffiliateLink: Bool { affiliateURL != nil }
}
