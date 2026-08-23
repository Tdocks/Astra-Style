//
//  OutfitGenerationRequest.swift
//  AstraStyle
//
//  Request payload for `POST /outfits/generate` (spec §14), covering the
//  inputs described in spec §5.4 "Outfit generation": occasion or
//  natural-language request, weather, schedule, wardrobe, laundry
//  availability, fit, and preferences are all resolved server-side from
//  the authenticated user's context — the client only needs to supply the
//  request-specific overrides below.
//

import Foundation

public struct OutfitGenerationRequest: Sendable {
    public var occasionID: UUID?
    public var naturalLanguageRequest: String?
    public var lockedClosetItemIDs: [UUID]
    public var excludedClosetItemIDs: [UUID]
    public var desiredCount: Int

    public init(
        occasionID: UUID? = nil,
        naturalLanguageRequest: String? = nil,
        lockedClosetItemIDs: [UUID] = [],
        excludedClosetItemIDs: [UUID] = [],
        desiredCount: Int = 3
    ) {
        self.occasionID = occasionID
        self.naturalLanguageRequest = naturalLanguageRequest
        self.lockedClosetItemIDs = lockedClosetItemIDs
        self.excludedClosetItemIDs = excludedClosetItemIDs
        self.desiredCount = desiredCount
    }
}

/// Request payload for `POST /packing/generate` (spec §14, §6.24).
public struct PackingRequest: Sendable {
    public var destination: String
    public var startDate: Date
    public var endDate: Date
    public var activities: [String]
    public var dressCodes: [DressCode]
    public var luggageConstraint: LuggageConstraint
    public var hasLaundryAccess: Bool
    public var regenerate: Bool

    public init(
        destination: String,
        startDate: Date,
        endDate: Date,
        activities: [String] = [],
        dressCodes: [DressCode] = [],
        luggageConstraint: LuggageConstraint = .checkedBag,
        hasLaundryAccess: Bool = false,
        regenerate: Bool = false
    ) {
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.activities = activities
        self.dressCodes = dressCodes
        self.luggageConstraint = luggageConstraint
        self.hasLaundryAccess = hasLaundryAccess
        self.regenerate = regenerate
    }
}

public enum LuggageConstraint: String, Codable, CaseIterable, Sendable {
    case personalItemOnly = "personal_item_only"
    case carryOnOnly = "carry_on_only"
    case checkedBag = "checked_bag"
    case noConstraint = "no_constraint"
}

/// Response payload for `POST /packing/generate` (spec §6.24 "Outputs").
public struct PackingPlan: Codable, Hashable, Sendable {
    public var packingListItemIDs: [UUID]
    public var dailyOutfitPlan: [PackingDayPlan]
    public var missingEssentials: [String]
    public var weatherContingencyNote: String?

    public init(
        packingListItemIDs: [UUID],
        dailyOutfitPlan: [PackingDayPlan],
        missingEssentials: [String] = [],
        weatherContingencyNote: String? = nil
    ) {
        self.packingListItemIDs = packingListItemIDs
        self.dailyOutfitPlan = dailyOutfitPlan
        self.missingEssentials = missingEssentials
        self.weatherContingencyNote = weatherContingencyNote
    }

    enum CodingKeys: String, CodingKey {
        case packingListItemIDs = "packing_list_item_ids"
        case dailyOutfitPlan = "daily_outfit_plan"
        case missingEssentials = "missing_essentials"
        case weatherContingencyNote = "weather_contingency_note"
    }
}

public struct PackingDayPlan: Codable, Hashable, Sendable {
    public var date: Date
    public var outfitID: UUID
    /// `true` when this outfit re-wears a garment from an earlier day in
    /// the trip (spec §6.24 "Rewear map").
    public var isRewear: Bool

    /// Calendar day identity for list rows. Two days may rewear the same
    /// look; `outfitID` is not unique across the plan.
    public var dayKey: String { DateFormatter.astraDay.string(from: date) }

    public init(date: Date, outfitID: UUID, isRewear: Bool) {
        self.date = date
        self.outfitID = outfitID
        self.isRewear = isRewear
    }

    enum CodingKeys: String, CodingKey {
        case date
        case outfitID = "outfit_id"
        case isRewear = "is_rewear"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .date)
        if let day = DateFormatter.astraDay.date(from: raw) {
            date = day
        } else if let instant = ISO8601DateFormatter().date(from: raw) {
            date = instant
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .date,
                in: container,
                debugDescription: "packing day must be YYYY-MM-DD; got \(raw)"
            )
        }
        outfitID = try container.decode(UUID.self, forKey: .outfitID)
        isRewear = try container.decode(Bool.self, forKey: .isRewear)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(DateFormatter.astraDay.string(from: date), forKey: .date)
        try container.encode(outfitID, forKey: .outfitID)
        try container.encode(isRewear, forKey: .isRewear)
    }
}
