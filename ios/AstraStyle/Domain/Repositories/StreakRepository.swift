//
//  StreakRepository.swift
//  AstraStyle
//
//  Reads `wear_days`. Writes are triggers on outfit_wears / closet_items.
//

import Foundation

public protocol StreakRepository: Sendable {
    func fetchStreak(now: Date) async throws -> WearStreak
}
