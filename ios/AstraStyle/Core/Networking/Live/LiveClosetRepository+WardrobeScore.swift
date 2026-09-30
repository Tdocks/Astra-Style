//
//  LiveClosetRepository+WardrobeScore.swift
//  AstraStyle
//
//  Reads the caller-scoped Wardrobe Score computed by the `closet` Edge
//  Function. The score is derived from current user data and is never stored
//  as a second, potentially stale copy.
//

import Foundation

private struct WardrobeScoreResponse: Decodable, Sendable {
    struct Component: Decodable, Sendable {
        let value: Int
        let degraded: Bool
    }

    let score: Int?
    let activeItemCount: Int
    let confidence: Double
    let components: [String: Component]

    enum CodingKeys: String, CodingKey {
        case score
        case activeItemCount = "active_item_count"
        case confidence
        case components
    }
}

extension LiveClosetRepository {
    public func fetchWardrobeScore() async throws -> WardrobeScore {
        let snapshot = try await fetchWardrobeScoreSnapshot()
        guard let score = snapshot.score else {
            throw AstraError.unimplemented(
                String(localized: "Add a piece to your closet to start your Wardrobe Score.")
            )
        }
        return score
    }

    public func fetchWardrobeScoreSnapshot() async throws -> WardrobeScoreSnapshot {
        let response: WardrobeScoreResponse
        do {
            response = try await apiClient.send(.fetchWardrobeScore, as: WardrobeScoreResponse.self)
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.network("Couldn't load your Wardrobe Score.")
        }

        func component(_ name: WardrobeScoreComponentName) throws -> WardrobeScoreResponse.Component {
            guard let value = response.components[name.rawValue] else {
                throw AstraError.server("The Wardrobe Score response was incomplete.")
            }
            return value
        }

        let versatility = try component(.versatility)
        let fitConfidence = try component(.fitConfidence)
        let occasionCoverage = try component(.occasionCoverage)
        let colorCohesion = try component(.colorCohesion)
        let wearUtilization = try component(.wearUtilization)
        let condition = try component(.condition)
        let redundancyControl = try component(.redundancyControl)

        let score = response.score.map {
            WardrobeScore(
                overall: $0,
                versatility: versatility.value,
                fitConfidence: fitConfidence.value,
                occasionCoverage: occasionCoverage.value,
                colorCohesion: colorCohesion.value,
                wearUtilization: wearUtilization.value,
                condition: condition.value,
                redundancyControl: redundancyControl.value
            )
        }
        let degraded = Set(WardrobeScoreComponentName.allCases.filter { name in
            response.components[name.rawValue]?.degraded == true
        })

        return WardrobeScoreSnapshot(
            score: score,
            activeItemCount: response.activeItemCount,
            confidence: response.confidence,
            degradedComponents: degraded
        )
    }

    public func captureMonthlyVersatilitySnapshot(monthStart: Date, score: Int) async throws -> Int? {
        guard let userID = await currentUserID() else {
            throw AstraError.auth("Sign in again to save your monthly wardrobe review.")
        }
        guard (0...100).contains(score),
              let thisMonth = Calendar.current.dateInterval(of: .month, for: monthStart)?.start,
              let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: thisMonth) else {
            throw AstraError.validation("That monthly score couldn't be saved.")
        }

        let previousDate = DateFormatter.astraDay.string(from: previousMonth)
        let monthDate = DateFormatter.astraDay.string(from: thisMonth)
        let previousRows: [MonthlyVersatilityScoreRow]
        do {
            previousRows = try await supabase.from("wardrobe_score_monthly_snapshots")
                .select("versatility_score")
                .eq("user_id", value: userID)
                .eq("month_start", value: previousDate)
                .limit(1)
                .execute()
                .value
        } catch {
            throw AstraError.network("Couldn't load last month's wardrobe score.")
        }

        do {
            try await supabase.from("wardrobe_score_monthly_snapshots")
                .upsert(
                    MonthlyVersatilityScoreWrite(
                        userID: userID,
                        monthStart: monthDate,
                        versatilityScore: score,
                        capturedAt: .now
                    ),
                    onConflict: "user_id,month_start"
                )
                .execute()
        } catch {
            throw AstraError.network("Couldn't save this month's wardrobe score. Please try again.")
        }
        return previousRows.first?.versatilityScore
    }
}

private struct MonthlyVersatilityScoreRow: Decodable, Sendable {
    let versatilityScore: Int

    enum CodingKeys: String, CodingKey {
        case versatilityScore = "versatility_score"
    }
}

private struct MonthlyVersatilityScoreWrite: Encodable, Sendable {
    let userID: UUID
    let monthStart: String
    let versatilityScore: Int
    let capturedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case monthStart = "month_start"
        case versatilityScore = "versatility_score"
        case capturedAt = "captured_at"
    }
}
