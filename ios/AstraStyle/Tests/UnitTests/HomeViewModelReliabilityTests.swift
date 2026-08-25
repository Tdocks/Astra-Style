//
//  HomeViewModelReliabilityTests.swift
//  AstraStyleTests
//
//  Phase 1 dogfood: Home has to survive Scan One and Wear This without
//  going mute. Closet already reloads when the scanner sheet closes;
//  Home used to keep the pre-scan empty state, and Wear This used to
//  swallow both success and failure.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("HomeViewModel dogfood reliability")
@MainActor
struct HomeViewModelReliabilityTests {

    @Test("A second onAppear does not reload — but a closed scanner does")
    func scannerDismissReloadsEvenWhenOnAppearWouldNoOp() async {
        let provider = RecordingHomeProvider(data: emptyBrief(have: 0))
        let viewModel = HomeViewModel(
            provider: provider,
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false)
        )

        await viewModel.onAppear()
        #expect(provider.loadCallCount == 1)
        await viewModel.onAppear()
        #expect(provider.loadCallCount == 1)

        provider.data = emptyBrief(have: 1)
        await viewModel.reloadAfterExternalChange()

        #expect(provider.loadCallCount == 2)
        guard case .empty(let data) = viewModel.state else {
            Issue.record("expected .empty after the scan, got \(viewModel.state)")
            return
        }
        #expect(data.closetItemCount == 1)
    }

    @Test("Reloading an empty Home asks the server to regenerate, so a missing role just scanned can produce a look")
    func emptyReloadRegenerates() async {
        let provider = RecordingHomeProvider(data: emptyBrief(have: 4))
        let viewModel = HomeViewModel(
            provider: provider,
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false)
        )
        await viewModel.onAppear()
        #expect(provider.lastRegenerate == false)

        let dressed = loadedBrief()
        provider.data = dressed
        await viewModel.reloadAfterExternalChange()

        #expect(provider.lastRegenerate == true)
        guard case .loaded(let data) = viewModel.state else {
            Issue.record("expected .loaded once the closet could dress him, got \(viewModel.state)")
            return
        }
        #expect(data.primaryOutfit?.id == dressed.primaryOutfit?.id)
    }

    @Test("Reloading a dressed Home keeps today's look — a new scan does not churn the brief")
    func loadedReloadDoesNotRegenerate() async {
        let provider = RecordingHomeProvider(data: loadedBrief())
        let viewModel = HomeViewModel(
            provider: provider,
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false)
        )
        await viewModel.onAppear()
        await viewModel.reloadAfterExternalChange()

        #expect(provider.loadCallCount == 2)
        #expect(provider.lastRegenerate == false)
        guard case .loaded = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
    }

    @Test("Pull-to-refresh does not blank Home back to the skeleton")
    func refreshKeepsContentOnScreen() async {
        let provider = RecordingHomeProvider(data: loadedBrief())
        let viewModel = HomeViewModel(
            provider: provider,
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false)
        )
        await viewModel.onAppear()
        await viewModel.refresh()

        #expect(provider.loadCallCount == 2)
        guard case .loaded = viewModel.state else {
            Issue.record("refresh must not leave Home on .loading, got \(viewModel.state)")
            return
        }
    }

    @Test("Wear This records the wear once, then refuses a second tap")
    func wearThisSucceedsOnce() async {
        let provider = RecordingHomeProvider(data: loadedBrief())
        let viewModel = HomeViewModel(
            provider: provider,
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false)
        )
        await viewModel.onAppear()

        await viewModel.markPrimaryOutfitWorn()
        await viewModel.markPrimaryOutfitWorn()

        #expect(provider.markCallCount == 1)
        #expect(viewModel.hasMarkedWorn)
        #expect(viewModel.canOfferPublicLook)
        #expect(viewModel.actionError == nil)
        guard case .loaded = viewModel.state else {
            Issue.record("Wear This must not replace the look, got \(viewModel.state)")
            return
        }
    }

    @Test("A failed Wear This surfaces actionError and leaves Today's Outfit on screen")
    func wearThisFailureDoesNotReplaceTheLook() async {
        let provider = RecordingHomeProvider(
            data: loadedBrief(),
            markError: AstraError.network("Check your connection and try again.")
        )
        let viewModel = HomeViewModel(
            provider: provider,
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false)
        )
        await viewModel.onAppear()
        await viewModel.markPrimaryOutfitWorn()

        #expect(viewModel.actionError?.category == .network)
        #expect(!viewModel.hasMarkedWorn)
        guard case .loaded = viewModel.state else {
            Issue.record("expected .loaded after a failed Wear This, got \(viewModel.state)")
            return
        }
    }

    @Test("A transport 429 on Wear This stays an error and never becomes monetization")
    func wearThisRateLimitNeverPresentsPaywall() async {
        let provider = RecordingHomeProvider(
            data: loadedBrief(),
            markError: AstraError.rateLimited("Upgrade to keep logging looks.")
        )
        let viewModel = HomeViewModel(
            provider: provider,
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false)
        )
        await viewModel.onAppear()
        await viewModel.markPrimaryOutfitWorn()

        #expect(viewModel.pendingPaywall == nil)
        #expect(viewModel.actionError?.category == .rateLimited)
        #expect(!viewModel.hasMarkedWorn)
        guard case .loaded = viewModel.state else {
            Issue.record("expected .loaded after a Wear This rate limit, got \(viewModel.state)")
            return
        }
    }

    @Test("Wear This is inert on the empty state — there is no outfit to wear")
    func wearThisIsInertWhenEmpty() async {
        let provider = RecordingHomeProvider(data: emptyBrief(have: 0))
        let viewModel = HomeViewModel(
            provider: provider,
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false)
        )
        await viewModel.onAppear()
        await viewModel.markPrimaryOutfitWorn()

        #expect(provider.markCallCount == 0)
        #expect(!viewModel.hasMarkedWorn)
    }
}

// MARK: - Fixtures

private func emptyBrief(have: Int) -> HomeBriefData {
    HomeBriefData(
        greetingName: "Marcus",
        weather: nil,
        schedule: nil,
        brief: DailyBrief(id: UUID(), userID: UUID(), briefDate: .now),
        primaryOutfit: nil,
        primaryOutfitItems: [],
        closetRoleCounts: have == 0 ? [:] : [.top: have]
    )
}

private func loadedBrief(outfitID: UUID = UUID()) -> HomeBriefData {
    HomeBriefData(
        greetingName: "Marcus",
        weather: nil,
        schedule: nil,
        brief: DailyBrief(id: UUID(), userID: UUID(), briefDate: .now, primaryOutfitID: outfitID),
        primaryOutfit: Outfit(id: outfitID, userID: UUID(), name: "Thursday"),
        primaryOutfitItems: [],
        closetRoleCounts: [.top: 2, .bottom: 2, .shoes: 1]
    )
}

private final class RecordingHomeProvider: HomeBriefProviding, @unchecked Sendable {
    nonisolated(unsafe) var data: HomeBriefData
    private let markError: Error?
    nonisolated(unsafe) private(set) var loadCallCount = 0
    nonisolated(unsafe) private(set) var markCallCount = 0
    nonisolated(unsafe) private(set) var lastRegenerate: Bool?

    init(data: HomeBriefData, markError: Error? = nil) {
        self.data = data
        self.markError = markError
    }

    func loadTodayBrief(regenerate: Bool) async throws -> HomeBriefData {
        loadCallCount += 1
        lastRegenerate = regenerate
        return data
    }

    func markPrimaryOutfitWorn(_ data: HomeBriefData) async throws {
        markCallCount += 1
        if let markError { throw markError }
    }

    func weatherAuthorization() -> WeatherLocationAuthorization { .denied }
    func requestWeatherPermission() async -> Bool { false }
}
