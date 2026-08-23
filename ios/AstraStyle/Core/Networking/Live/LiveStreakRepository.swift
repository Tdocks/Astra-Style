//
//  LiveStreakRepository.swift
//  AstraStyle
//
//  `wear_days` is user-scoped RLS. Triggers write the rows; this only reads.
//

import Foundation
import Supabase

public final class LiveStreakRepository: StreakRepository, @unchecked Sendable {
    private let supabase: SupabaseClient

    public init(supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)) {
        self.supabase = supabase
    }

    public func fetchStreak(now: Date) async throws -> WearStreak {
        do {
            let days: [WearDay] = try await supabase
                .from("wear_days")
                .select("user_id, worn_on")
                .execute()
                .value
            return WearStreakCalculator.stats(days: days.map(\.wornOn), today: now)
        } catch {
            throw AstraError.network("Couldn't load your streak.")
        }
    }
}
