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
        briefDate = try Self.decodeBriefDate(from: container)
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

    /// `brief_date` is a Postgres `date`, not a `timestamptz`.
    ///
    /// PostgREST serializes a `date` column as `"2026-08-08"`, and both paths
    /// that read this row decode with an ISO-8601 strategy that requires a
    /// full timestamp — `AstraAPIClient`'s decoder and supabase-swift's. So a
    /// perfectly good 200 threw `DecodingError.dataCorrupted`, the API client
    /// turned it into `.server("Failed to parse the server's response.")`,
    /// and Home rendered its error state over a brief the server had built
    /// correctly.
    ///
    /// It stayed hidden because it could not fire until a closet crossed
    /// `HomeBriefData.minimumItemsForOutfits` — below five items Home never
    /// calls generate at all — and because `DailyBriefDecodingTests` fed the
    /// decoder `"2026-08-06T00:00:00Z"`, a shape this wire has never once
    /// carried. The tests agreed with the code and both were wrong about the
    /// server.
    ///
    /// Fixed in the model rather than by loosening the API client's date
    /// strategy, because that would only fix one of the two readers: the
    /// cached-brief path goes through supabase-swift's own decoder, which
    /// this repo does not configure. Fixing it here fixes both, and it is
    /// also the narrower change — every OTHER date on the wire really is a
    /// timestamp, and making the client lenient about all of them would trade
    /// one silent misreading for a wider one.
    ///
    /// The full-timestamp fallback is not defensive padding: it is what makes
    /// this decoder correct for a row read back through a path that ever does
    /// return a timestamp, and it costs one line.
    private static func decodeBriefDate(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date {
        let raw = try container.decode(String.self, forKey: .briefDate)
        if let day = DateFormatter.astraDay.date(from: raw) { return day }
        if let instant = ISO8601DateFormatter().date(from: raw) { return instant }
        throw DecodingError.dataCorruptedError(
            forKey: .briefDate,
            in: container,
            debugDescription: "brief_date must be YYYY-MM-DD or a full ISO-8601 timestamp; got \(raw)"
        )
    }

    /// Symmetric with the decoder above, so a brief that is cached and read
    /// back is the same brief. The synthesized encoder would write an ISO
    /// timestamp that `decodeBriefDate` would then parse through its fallback
    /// — surviving, but round-tripping through a shape the server never
    /// sends, which is how the original mismatch went unnoticed for so long.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(DateFormatter.astraDay.string(from: briefDate), forKey: .briefDate)
        try container.encodeIfPresent(primaryOutfitID, forKey: .primaryOutfitID)
        try container.encode(alternativeOutfitIDs, forKey: .alternativeOutfitIDs)
        try container.encodeIfPresent(weatherSnapshot, forKey: .weatherSnapshot)
        try container.encodeIfPresent(scheduleSnapshot, forKey: .scheduleSnapshot)
        try container.encodeIfPresent(kyraMessage, forKey: .kyraMessage)
    }

    /// Empty-state trigger for Home (spec §6.11 "Empty state: Prompt to add
    /// 5 closet items") — a brief with no primary outfit means generation
    /// couldn't find enough owned items to work with.
    public var hasPrimaryOutfit: Bool { primaryOutfitID != nil }
}
