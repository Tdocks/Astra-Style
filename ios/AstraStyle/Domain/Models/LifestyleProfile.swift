//
//  LifestyleProfile.swift
//  AstraStyle
//
//  Maps `lifestyle_profiles` (spec §9), populated during the lifestyle
//  onboarding step (spec §6.8).
//
//  Four fields were missing until the Phase 2 pre-flight: `currency`,
//  `travelFrequency`, `religiousServiceAttireNeeds` and
//  `sustainabilityPreference`. All four are columns that already exist on the
//  table, and all four are named explicitly in spec §6.8's field list. The
//  onboarding screens would therefore have collected answers this model could
//  not persist.
//
//  `currency` is the one that would have caused real damage. `monthlyBudget` is
//  a bare `Decimal` — without a currency beside it, a budget of 500 is
//  meaningless, and `CostPerWearCalculator` (§16) divides money by wears to
//  produce a figure shown to the user. A dollar budget interpreted as euros is
//  not a rounding error, it is wrong advice about what someone can afford.
//

import Foundation

public struct LifestyleProfile: Codable, Hashable, Sendable {
    public var userID: UUID
    public var occupationCategory: OccupationCategory?
    public var dressCode: DressCode?
    public var commonOccasions: [String]
    /// Shape of the user's week (§6.8 "Typical week").
    ///
    /// Distinct from `dressCode`, which says what he wears WHEN dressed for
    /// work. This says how many days that is — five days in an office and one
    /// need different quantities of the same wardrobe, and nothing else on the
    /// profile distinguishes them.
    public var typicalWeek: String?
    public var climatePreferences: [String]
    public var monthlyBudget: Decimal?

    /// ISO 4217 code for `monthlyBudget`. `NOT NULL DEFAULT 'USD'` in Postgres,
    /// so non-optional here — a budget without a currency is not a
    /// representable state, and making this optional would push the ambiguity
    /// out to every call site that formats money.
    public var currency: String

    public var preferredBrands: [String]
    public var avoidedBrands: [String]
    public var laundryCadence: LaundryCadence?

    // The three §6.8 fields below are free text rather than enums, matching the
    // `text` columns. Deliberate: "religious/service attire needs" cannot be
    // enumerated without excluding someone, and guessing a closed set here
    // would be the kind of decision that reads as thoughtless to whoever it
    // leaves out. Travel frequency and sustainability preference are text for
    // now because §6.8 does not specify their vocabularies; if they later
    // become enums they need Postgres enums and a `check_schema_drift` mapping
    // in the same change.
    public var travelFrequency: String?
    public var religiousServiceAttireNeeds: String?
    public var sustainabilityPreference: String?

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        userID: UUID,
        occupationCategory: OccupationCategory? = nil,
        dressCode: DressCode? = nil,
        commonOccasions: [String] = [],
        typicalWeek: String? = nil,
        climatePreferences: [String] = [],
        monthlyBudget: Decimal? = nil,
        currency: String = "USD",
        preferredBrands: [String] = [],
        avoidedBrands: [String] = [],
        laundryCadence: LaundryCadence? = nil,
        travelFrequency: String? = nil,
        religiousServiceAttireNeeds: String? = nil,
        sustainabilityPreference: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.userID = userID
        self.occupationCategory = occupationCategory
        self.dressCode = dressCode
        self.commonOccasions = commonOccasions
        self.typicalWeek = typicalWeek
        self.climatePreferences = climatePreferences
        self.monthlyBudget = monthlyBudget
        self.currency = currency
        self.preferredBrands = preferredBrands
        self.avoidedBrands = avoidedBrands
        self.laundryCadence = laundryCadence
        self.travelFrequency = travelFrequency
        self.religiousServiceAttireNeeds = religiousServiceAttireNeeds
        self.sustainabilityPreference = sustainabilityPreference
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case occupationCategory = "occupation_category"
        case dressCode = "dress_code"
        case commonOccasions = "common_occasions"
        case typicalWeek = "typical_week"
        case climatePreferences = "climate_preferences"
        case monthlyBudget = "monthly_budget"
        case currency
        case preferredBrands = "preferred_brands"
        case avoidedBrands = "avoided_brands"
        case laundryCadence = "laundry_cadence"
        case travelFrequency = "travel_frequency"
        case religiousServiceAttireNeeds = "religious_service_attire_needs"
        case sustainabilityPreference = "sustainability_preference"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // `currency` is NOT NULL with a default server-side, but a row written
    // before that default existed, or a partial projection, can still arrive
    // without it. Decoding to "USD" rather than throwing keeps a legacy row
    // readable; the alternative is a profile the app cannot open at all.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(UUID.self, forKey: .userID)
        occupationCategory = try c.decodeIfPresent(OccupationCategory.self, forKey: .occupationCategory)
        dressCode = try c.decodeIfPresent(DressCode.self, forKey: .dressCode)
        commonOccasions = try c.decodeIfPresent([String].self, forKey: .commonOccasions) ?? []
        climatePreferences = try c.decodeIfPresent([String].self, forKey: .climatePreferences) ?? []
        monthlyBudget = try c.decodeIfPresent(Decimal.self, forKey: .monthlyBudget)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        preferredBrands = try c.decodeIfPresent([String].self, forKey: .preferredBrands) ?? []
        avoidedBrands = try c.decodeIfPresent([String].self, forKey: .avoidedBrands) ?? []
        laundryCadence = try c.decodeIfPresent(LaundryCadence.self, forKey: .laundryCadence)
        travelFrequency = try c.decodeIfPresent(String.self, forKey: .travelFrequency)
        religiousServiceAttireNeeds = try c.decodeIfPresent(
            String.self, forKey: .religiousServiceAttireNeeds
        )
        sustainabilityPreference = try c.decodeIfPresent(String.self, forKey: .sustainabilityPreference)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}
