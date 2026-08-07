//
//  HomeViewModelWeatherTests.swift
//  AstraStyleTests
//
//  P4-HOME-05: spec §7's "Location: when enabling weather" is requested in
//  context on first use of Home and nowhere else. What this file pins is
//  the ordering guarantee that makes that true at the view-model layer —
//  `DefaultHomeBriefProvider`'s half of the honesty rule is covered
//  separately in `HomeBriefProvidingTests.swift`.
//

import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("HomeViewModel weather permission")
struct HomeViewModelWeatherTests {

    @Test("onAppear reads authorization without ever requesting permission")
    func onAppearReadsWithoutRequesting() async throws {
        let provider = RecordingWeatherProvider(
            authorization: .notDetermined,
            permissionGrantResult: true,
            briefData: fixtureBriefData()
        )
        let viewModel = HomeViewModel(provider: provider, networkMonitor: StaticNetworkReachabilityMonitor(offline: false))

        await viewModel.onAppear()

        #expect(viewModel.weatherAuthorization == .notDetermined)
        #expect(provider.requestPermissionCallCount == 0)
    }

    @Test("enableWeather asks for permission and reloads the brief when granted")
    func enableWeatherReloadsWhenGranted() async throws {
        let provider = RecordingWeatherProvider(
            authorization: .notDetermined,
            permissionGrantResult: true,
            briefData: fixtureBriefData()
        )
        let viewModel = HomeViewModel(provider: provider, networkMonitor: StaticNetworkReachabilityMonitor(offline: false))
        await viewModel.onAppear()
        #expect(provider.loadCallCount == 1)

        await viewModel.enableWeather()

        #expect(viewModel.weatherAuthorization == .authorized)
        #expect(provider.requestPermissionCallCount == 1)
        // A fresh load is what actually attaches the reading — see
        // `DefaultHomeBriefProvider`'s cached-vs-generate weather overlay.
        #expect(provider.loadCallCount == 2)
    }

    @Test("enableWeather records the denial honestly and does not reload")
    func enableWeatherStaysDeniedWithoutReloading() async throws {
        let provider = RecordingWeatherProvider(
            authorization: .notDetermined,
            permissionGrantResult: false,
            briefData: fixtureBriefData()
        )
        let viewModel = HomeViewModel(provider: provider, networkMonitor: StaticNetworkReachabilityMonitor(offline: false))
        await viewModel.onAppear()
        #expect(provider.loadCallCount == 1)

        await viewModel.enableWeather()

        #expect(viewModel.weatherAuthorization == .denied)
        #expect(provider.requestPermissionCallCount == 1)
        // Nothing changed for a reload to attach — asking again would just
        // repeat the same "no weather" brief for no reason.
        #expect(provider.loadCallCount == 1)
    }

    @Test("enableWeather is a no-op once a decision already exists")
    func enableWeatherIsNoOpAfterADecision() async throws {
        let provider = RecordingWeatherProvider(
            authorization: .authorized,
            permissionGrantResult: true,
            briefData: fixtureBriefData()
        )
        let viewModel = HomeViewModel(provider: provider, networkMonitor: StaticNetworkReachabilityMonitor(offline: false))
        await viewModel.onAppear()

        await viewModel.enableWeather()

        // The system prompt has exactly one legitimate call site in this
        // app — `WeatherOptInCardView`'s button, gated on `.notDetermined`.
        // A second tap, or a stale render calling this after the state
        // already moved on, must not re-ask.
        #expect(provider.requestPermissionCallCount == 0)
    }
}

/// A minimal `.loaded`-shaped `HomeBriefData` — this suite is about
/// permission call ordering, not about the brief's content, so every field
/// beyond what `HomeViewModel`/`ViewState` need to reach `.loaded` is left
/// at its emptiest honest value.
private func fixtureBriefData() -> HomeBriefData {
    HomeBriefData(
        greetingName: "Marcus",
        weather: nil,
        schedule: nil,
        brief: DailyBrief(id: UUID(), userID: UUID(), briefDate: .now, primaryOutfitID: UUID()),
        primaryOutfit: nil,
        primaryOutfitItems: [],
        alternativeOutfits: [],
        wardrobeScore: nil,
        laundryAlertItemCount: 0,
        upcomingOccasions: [],
        purchaseOpportunity: nil
    )
}

// MARK: - Test double

/// `HomeBriefProviding` double that records what `HomeViewModel` asked of
/// it, without going through `DefaultHomeBriefProvider`/a real
/// `WeatherService` at all — this file is about the view model's call
/// ordering, not the provider's weather plumbing.
///
/// `@unchecked Sendable` with `nonisolated(unsafe)` state rather than an
/// actor: `weatherAuthorization()` is a synchronous, non-async protocol
/// requirement (so it can be read from `HomeViewModel.onAppear()` without
/// a suspension point, matching `DefaultHomeBriefProvider`'s own
/// implementation), and an actor cannot satisfy a synchronous requirement
/// while also mutating actor-isolated state from it. Every test in this
/// file runs sequentially on `@MainActor`, so the lack of actor isolation
/// costs nothing in practice — the same tradeoff already made by
/// `AstraAPIClientIdempotencyTests`'s `nonisolated(unsafe)` statics.
private final class RecordingWeatherProvider: HomeBriefProviding, @unchecked Sendable {
    nonisolated(unsafe) private var authorization: WeatherLocationAuthorization
    private let permissionGrantResult: Bool
    private let briefData: HomeBriefData
    nonisolated(unsafe) private(set) var loadCallCount = 0
    nonisolated(unsafe) private(set) var requestPermissionCallCount = 0

    init(authorization: WeatherLocationAuthorization, permissionGrantResult: Bool, briefData: HomeBriefData) {
        self.authorization = authorization
        self.permissionGrantResult = permissionGrantResult
        self.briefData = briefData
    }

    func loadTodayBrief(regenerate: Bool) async throws -> HomeBriefData {
        loadCallCount += 1
        return briefData
    }

    func markPrimaryOutfitWorn(_ data: HomeBriefData) async throws {}

    func weatherAuthorization() -> WeatherLocationAuthorization { authorization }

    func requestWeatherPermission() async -> Bool {
        requestPermissionCallCount += 1
        authorization = permissionGrantResult ? .authorized : .denied
        return permissionGrantResult
    }
}
