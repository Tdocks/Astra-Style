//
//  DailyBrief.swift
//  AstraStyle
//
//  Maps `daily_briefs` (spec §9). This is the data backing Kyra's Daily
//  Brief (spec §6.11), the Home tab's primary content.
//

import Foundation

public struct DailyBrief: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var userID: UUID
    public var briefDate: Date
    public var primaryOutfitID: UUID?
    public var alternativeOutfitIDs: [UUID]
    public var weatherSnapshot: WeatherSnapshot?
    public var scheduleSnapshot: ScheduleSnapshot?
    public var kyraMessage: String?

    public init(
        id: UUID,
        userID: UUID,
        briefDate: Date,
        primaryOutfitID: UUID? = nil,
        alternativeOutfitIDs: [UUID] = [],
        weatherSnapshot: WeatherSnapshot? = nil,
        scheduleSnapshot: ScheduleSnapshot? = nil,
        kyraMessage: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.briefDate = briefDate
        self.primaryOutfitID = primaryOutfitID
        self.alternativeOutfitIDs = alternativeOutfitIDs
        self.weatherSnapshot = weatherSnapshot
        self.scheduleSnapshot = scheduleSnapshot
        self.kyraMessage = kyraMessage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case briefDate = "brief_date"
        case primaryOutfitID = "primary_outfit_id"
        case alternativeOutfitIDs = "alternative_outfit_ids"
        case weatherSnapshot = "weather_snapshot"
        case scheduleSnapshot = "schedule_snapshot"
        case kyraMessage = "kyra_message"
    }

    /// Empty-state trigger for Home (spec §6.11 "Empty state: Prompt to add
    /// 5 closet items") — a brief with no primary outfit means generation
    /// couldn't find enough owned items to work with.
    public var hasPrimaryOutfit: Bool { primaryOutfitID != nil }
}
