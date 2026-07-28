//
//  LifestyleProfile.swift
//  AstraStyle
//
//  Maps `lifestyle_profiles` (spec §9), populated during the lifestyle
//  onboarding step (spec §6.8).
//

import Foundation

public struct LifestyleProfile: Codable, Hashable, Sendable {
    public var userID: UUID
    public var occupationCategory: OccupationCategory?
    public var dressCode: DressCode?
    public var commonOccasions: [String]
    public var climatePreferences: [String]
    public var monthlyBudget: Decimal?
    public var preferredBrands: [String]
    public var avoidedBrands: [String]
    public var laundryCadence: LaundryCadence?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        userID: UUID,
        occupationCategory: OccupationCategory? = nil,
        dressCode: DressCode? = nil,
        commonOccasions: [String] = [],
        climatePreferences: [String] = [],
        monthlyBudget: Decimal? = nil,
        preferredBrands: [String] = [],
        avoidedBrands: [String] = [],
        laundryCadence: LaundryCadence? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.userID = userID
        self.occupationCategory = occupationCategory
        self.dressCode = dressCode
        self.commonOccasions = commonOccasions
        self.climatePreferences = climatePreferences
        self.monthlyBudget = monthlyBudget
        self.preferredBrands = preferredBrands
        self.avoidedBrands = avoidedBrands
        self.laundryCadence = laundryCadence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case occupationCategory = "occupation_category"
        case dressCode = "dress_code"
        case commonOccasions = "common_occasions"
        case climatePreferences = "climate_preferences"
        case monthlyBudget = "monthly_budget"
        case preferredBrands = "preferred_brands"
        case avoidedBrands = "avoided_brands"
        case laundryCadence = "laundry_cadence"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
