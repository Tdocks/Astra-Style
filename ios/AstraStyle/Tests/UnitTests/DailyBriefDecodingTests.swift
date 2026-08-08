//
//  DailyBriefDecodingTests.swift
//  AstraStyleTests
//
//  `daily_briefs.weather_snapshot` and `.schedule_snapshot` are
//  `jsonb NOT NULL DEFAULT '{}'`, so a row that has never had one written
//  carries `{}` rather than null. The synthesized decoder tried to build a
//  `WeatherSnapshot` out of that and threw on the first missing field —
//  which made EVERY real row undecodable, silently: `fetchDailyBrief` wraps
//  its read in `try? … ?? nil`, so the cached-brief path simply never
//  returned a brief and Home regenerated from the server every load.
//
//  These pin both halves of the fix: an empty object means absent, and a
//  populated one that does not fit still throws, because that is schema
//  drift and silently dropping a real forecast is worse than a failure.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("DailyBrief decoding")
struct DailyBriefDecodingTests {

    private func decode(_ json: String) throws -> DailyBrief {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DailyBrief.self, from: Data(json.utf8))
    }

    /// The shape a real row has today, and the one that used to throw.
    @Test("An empty snapshot object decodes as absent, not as a failure")
    func emptySnapshotsDecodeAsNil() throws {
        let brief = try decode(#"""
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "user_id": "22222222-2222-4222-8222-222222222222",
          "brief_date": "2026-08-06T00:00:00Z",
          "primary_outfit_id": null,
          "alternative_outfit_ids": [],
          "weather_snapshot": {},
          "schedule_snapshot": {},
          "kyra_message": null
        }
        """#)

        #expect(brief.weatherSnapshot == nil)
        #expect(brief.scheduleSnapshot == nil)
        #expect(brief.hasPrimaryOutfit == false)
    }

    @Test("An explicit null snapshot decodes as absent")
    func nullSnapshotsDecodeAsNil() throws {
        let brief = try decode(#"""
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "user_id": "22222222-2222-4222-8222-222222222222",
          "brief_date": "2026-08-06T00:00:00Z",
          "primary_outfit_id": "33333333-3333-4333-8333-333333333333",
          "alternative_outfit_ids": ["44444444-4444-4444-8444-444444444444"],
          "weather_snapshot": null,
          "schedule_snapshot": null,
          "kyra_message": "Wear the navy."
        }
        """#)

        #expect(brief.weatherSnapshot == nil)
        #expect(brief.scheduleSnapshot == nil)
        #expect(brief.hasPrimaryOutfit)
        #expect(brief.alternativeOutfitIDs.count == 1)
        #expect(brief.kyraMessage == "Wear the navy.")
    }

    @Test("A populated snapshot still decodes into its typed model")
    func populatedSnapshotsDecodeNormally() throws {
        let brief = try decode(#"""
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "user_id": "22222222-2222-4222-8222-222222222222",
          "brief_date": "2026-08-06T00:00:00Z",
          "primary_outfit_id": null,
          "alternative_outfit_ids": [],
          "weather_snapshot": {
            "temperature_high": 22.5,
            "temperature_low": 14.0,
            "condition": "cloudy"
          },
          "schedule_snapshot": { "event_count": 2 },
          "kyra_message": null
        }
        """#)

        #expect(brief.weatherSnapshot?.temperatureHigh == 22.5)
        #expect(brief.scheduleSnapshot?.eventCount == 2)
    }

    /// The line the leniency must not cross. A snapshot with content that
    /// does not fit the model is schema drift, and swallowing it would hide
    /// a real forecast behind a blank header.
    @Test("A populated snapshot that does not fit the model still throws")
    func driftingSnapshotStillThrows() {
        #expect(throws: (any Error).self) {
            try decode(#"""
            {
              "id": "11111111-1111-4111-8111-111111111111",
              "user_id": "22222222-2222-4222-8222-222222222222",
              "brief_date": "2026-08-06T00:00:00Z",
              "primary_outfit_id": null,
              "alternative_outfit_ids": [],
              "weather_snapshot": { "temperature_high": 22.5 },
              "schedule_snapshot": {},
              "kyra_message": null
            }
            """#)
        }
    }

    @Test("A brief round-trips through encode and decode")
    func roundTrips() throws {
        let original = DailyBrief(
            id: UUID(),
            userID: UUID(),
            briefDate: Date(timeIntervalSince1970: 1_785_000_000),
            primaryOutfitID: UUID(),
            alternativeOutfitIDs: [UUID(), UUID()],
            scheduleSnapshot: ScheduleSnapshot(eventCount: 3),
            kyraMessage: "Something specific."
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(DailyBrief.self, from: encoder.encode(original))

        #expect(restored == original)
    }
}
