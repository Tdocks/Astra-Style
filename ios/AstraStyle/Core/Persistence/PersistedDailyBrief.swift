//
//  PersistedDailyBrief.swift
//  AstraStyle
//
//  SwiftData cache of `DailyBrief` (spec §7 offline viewability — so
//  yesterday's brief, or this morning's already-generated one, still
//  renders on the Home tab with no connectivity). One row per
//  `(userID, briefDate)`; regenerating a brief overwrites the cached row.
//

import Foundation
import SwiftData

@Model
public final class PersistedDailyBrief {
    @Attribute(.unique) public var id: UUID
    public var userID: UUID
    public var briefDate: Date
    public var primaryOutfitID: UUID?
    public var alternativeOutfitIDs: [UUID]
    public var kyraMessage: String?

    /// JSON-encoded `WeatherSnapshot?` / `ScheduleSnapshot?`.
    public var encodedWeatherSnapshot: Data?
    public var encodedScheduleSnapshot: Data?

    public var cachedAt: Date

    public init(
        id: UUID,
        userID: UUID,
        briefDate: Date,
        primaryOutfitID: UUID?,
        alternativeOutfitIDs: [UUID],
        kyraMessage: String?,
        encodedWeatherSnapshot: Data?,
        encodedScheduleSnapshot: Data?,
        cachedAt: Date
    ) {
        self.id = id
        self.userID = userID
        self.briefDate = briefDate
        self.primaryOutfitID = primaryOutfitID
        self.alternativeOutfitIDs = alternativeOutfitIDs
        self.kyraMessage = kyraMessage
        self.encodedWeatherSnapshot = encodedWeatherSnapshot
        self.encodedScheduleSnapshot = encodedScheduleSnapshot
        self.cachedAt = cachedAt
    }
}
