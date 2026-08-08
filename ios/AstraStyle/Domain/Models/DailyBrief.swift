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

    /// Hand-written so that an EMPTY snapshot object decodes as `nil`
    /// instead of throwing and taking the whole brief down with it.
    ///
    /// `weather_snapshot` and `schedule_snapshot` are
    /// `jsonb NOT NULL DEFAULT '{}'` (`20260728100700_planning.sql`), so
    /// every row that has not had one written carries `{}`, not null. The
    /// synthesized decoder reaches those keys with `decodeIfPresent`, which
    /// finds a value, tries to build a `WeatherSnapshot` out of it, and
    /// throws on the first missing non-optional field — an Optional
    /// property does not make a *malformed* value decode to nil, only a
    /// missing or null one.
    ///
    /// So before this existed, any real `daily_briefs` row was undecodable.
    /// `fetchDailyBrief` reads the row straight over Postgrest and wraps
    /// the call in `try? … ?? nil`, so the failure was invisible: the
    /// cached-brief path simply never returned a brief, and Home
    /// regenerated from the server every single time.
    ///
    /// The leniency is deliberately narrow. An empty object is treated as
    /// absent, which is what it means. A *populated* object that fails to
    /// decode still throws, because that is schema drift and the one thing
    /// worse than a crash here would be silently dropping a real forecast.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        briefDate = try container.decode(Date.self, forKey: .briefDate)
        primaryOutfitID = try container.decodeIfPresent(UUID.self, forKey: .primaryOutfitID)
        alternativeOutfitIDs = try container.decodeIfPresent([UUID].self, forKey: .alternativeOutfitIDs) ?? []
        weatherSnapshot = try Self.decodeSnapshot(WeatherSnapshot.self, from: container, forKey: .weatherSnapshot)
        scheduleSnapshot = try Self.decodeSnapshot(ScheduleSnapshot.self, from: container, forKey: .scheduleSnapshot)
        kyraMessage = try container.decodeIfPresent(String.self, forKey: .kyraMessage)
    }

    private static func decodeSnapshot<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> T? {
        // `[String: AstraJSONValue]` rather than a nested container, because
        // "is this object empty" is a question about the raw JSON and asking
        // it through the typed decoder is what fails in the first place.
        guard let raw = try container.decodeIfPresent([String: AstraJSONValue].self, forKey: key) else {
            return nil
        }
        guard !raw.isEmpty else { return nil }
        return try container.decode(type, forKey: key)
    }

    /// Empty-state trigger for Home (spec §6.11 "Empty state: Prompt to add
    /// 5 closet items") — a brief with no primary outfit means generation
    /// couldn't find enough owned items to work with.
    public var hasPrimaryOutfit: Bool { primaryOutfitID != nil }
}
