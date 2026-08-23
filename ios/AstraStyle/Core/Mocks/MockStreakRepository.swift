//
//  MockStreakRepository.swift
//  AstraStyle
//

import Foundation

public actor MockStreakRepository: StreakRepository {
    private var streak: WearStreak

    public init(streak: WearStreak = WearStreak(current: 3, best: 12)) {
        self.streak = streak
    }

    public func setStreak(_ streak: WearStreak) {
        self.streak = streak
    }

    public func fetchStreak(now: Date) async throws -> WearStreak {
        streak
    }
}
