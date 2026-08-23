//
//  WearStreakBanner.swift
//  AstraStyle
//
//  Home/Profile chrome for wear_days. Not wear_count.
//

import SwiftUI

struct WearStreakBanner: View {
    @State private var viewModel: WearStreakViewModel
    private let showsBest: Bool

    init(viewModel: WearStreakViewModel, showsBest: Bool = false) {
        _viewModel = State(wrappedValue: viewModel)
        self.showsBest = showsBest
    }

    var body: some View {
        Group {
            if let streak = viewModel.streak, streak.best > 0 || streak.current > 0 {
                copy(streak)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("streak.banner")
            }
        }
        .task { await viewModel.onAppear() }
    }

    private func copy(_ streak: WearStreak) -> Text {
        if showsBest {
            Text(String(
                localized: "Streak \(streak.current) · best \(streak.best)",
                comment: "Profile streak current and best"
            ))
        } else if streak.current > 0 {
            Text(String(
                localized: "\(streak.current) day streak",
                comment: "Home current wear-day streak"
            ))
        } else {
            Text(String(
                localized: "Wear something today to start a streak.",
                comment: "Home streak empty"
            ))
        }
    }
}

@MainActor
@Observable
final class WearStreakViewModel {
    private(set) var streak: WearStreak?
    private let streakRepository: StreakRepository

    init(streakRepository: StreakRepository) {
        self.streakRepository = streakRepository
    }

    func onAppear() async {
        streak = try? await streakRepository.fetchStreak(now: .now)
    }
}
