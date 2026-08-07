//
//  LiveOutfitRepository+Brief.swift
//  AstraStyle
//
//  The daily brief and packing halves of `LiveOutfitRepository`.
//
//  SPLIT FOR LENGTH, NOT FOR ARCHITECTURE. `P4-OUTFIT-15`'s offline cache and
//  `P1-CORE-06`'s queue drain pushed the type to 282 lines against SwiftLint's
//  `type_body_length` limit of 280. `.swiftlint.yml`'s header forbids raising a
//  threshold to accommodate new code — the same rule that split
//  `LiveClosetRepository+Scan.swift` out of the closet repository.
//
//  These two methods are the natural seam: everything above them is an outfit,
//  and everything here is a document ABOUT outfits that some other endpoint
//  composed. They share the repository's client and its user scope and nothing
//  else, which is why they were the cheapest 104 lines to move.
//

import Foundation

public extension LiveOutfitRepository {
    public func fetchDailyBrief(for date: Date) async throws -> DailyBrief? {
        do {
            return try await supabase.from("daily_briefs")
                .select()
                .eq("brief_date", value: DateFormatter.astraDay.string(from: date))
                .single()
                .execute()
                .value
        } catch {
            return nil
        }
    }

    public func generateDailyBrief(for date: Date, regenerate: Bool, weather: WeatherSnapshot?) async throws -> DailyBrief {
        struct Body: Encodable, Sendable {
            let date: String
            let regenerate: Bool
            // Reuses `WeatherSnapshot`'s own `Encodable`/`CodingKeys`, so the
            // wire shape matches `weather_snapshot` exactly — no second,
            // divergent JSON shape for the same data.
            let weatherSnapshot: WeatherSnapshot?
            enum CodingKeys: String, CodingKey {
                case date
                case regenerate
                case weatherSnapshot = "weather_snapshot"
            }
        }
        return try await apiClient.send(
            .generateDailyBrief,
            body: Body(date: DateFormatter.astraDay.string(from: date), regenerate: regenerate, weatherSnapshot: weather),
            as: DailyBrief.self
        )
    }

    public func generatePackingPlan(_ request: PackingRequest) async throws -> PackingPlan {
        struct Body: Encodable, Sendable {
            let destination: String
            let startDate: Date
            let endDate: Date
            let activities: [String]
            let dressCodes: [DressCode]
            let luggageConstraint: LuggageConstraint
            let hasLaundryAccess: Bool
            enum CodingKeys: String, CodingKey {
                case destination
                case startDate = "start_date"
                case endDate = "end_date"
                case activities
                case dressCodes = "dress_codes"
                case luggageConstraint = "luggage_constraint"
                case hasLaundryAccess = "has_laundry_access"
            }
        }
        return try await apiClient.send(
            .generatePacking,
            body: Body(
                destination: request.destination,
                startDate: request.startDate,
                endDate: request.endDate,
                activities: request.activities,
                dressCodes: request.dressCodes,
                luggageConstraint: request.luggageConstraint,
                hasLaundryAccess: request.hasLaundryAccess
            ),
            as: PackingPlan.self
        )
    }
}

/// `POST /outfits/generate` request body.

extension DateFormatter {
    /// `YYYY-MM-DD`, matching the Postgres `date` column type used by
    /// `daily_briefs.brief_date` (spec §9).
    static let astraDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter
    }()}
