//
//  UnreadableClosetTests.swift
//  AstraStyleTests
//
//  One failure, pinned from both ends: a closet the app could not read must
//  never be reported as a closet with nothing in it.
//
//  The provider reads the closet with `try?` — correctly, since an
//  unreachable closet must not block the whole brief — and the result used
//  to be flattened to `[:]`. `closetItemCount` then read 0, `emptyReason`
//  said `.tooFewItems(have: 0)`, and a man with forty garments was told to
//  scan his first item, with no retry anywhere on the screen. Every
//  ingredient of that was individually reasonable.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("An unreadable closet is not an empty one")
@MainActor
struct UnreadableClosetTests {

    @Test("Nil role counts mean unknown, and unknown has no empty-state reason")
    func unknownClosetHasNoReason() {
        let data = briefData(closetRoleCounts: nil)

        #expect(data.closetIsUnreadable)
        // NOT `.tooFewItems(have: 0)`. There is no honest answer to "why is
        // there no outfit" when we do not know what he owns.
        #expect(data.emptyReason == nil)
        #expect(!data.needsMoreClosetItems)
    }

    @Test("A genuinely small closet still gets its reason")
    func knownSmallClosetKeepsItsReason() {
        let data = briefData(closetRoleCounts: [.top: 2])

        #expect(!data.closetIsUnreadable)
        #expect(data.emptyReason == .tooFewItems(have: 2, need: HomeBriefData.minimumItemsForOutfits))
    }

    @Test("An empty closet the app COULD read is still empty, not unreadable")
    func emptyButReadableIsNotUnreadable() {
        // The distinction only pays for itself if the readable-and-empty
        // case survives it. `[:]` is a real answer: we asked, and he owns
        // nothing yet.
        let data = briefData(closetRoleCounts: [:])

        #expect(!data.closetIsUnreadable)
        #expect(data.emptyReason == .tooFewItems(have: 0, need: HomeBriefData.minimumItemsForOutfits))
    }

    @Test("Home shows a retry, not an invitation, when the closet could not be read")
    func homeSurfacesTheFailureWithSomethingToTap() async {
        let model = HomeViewModel(provider: StubBriefProvider(data: briefData(closetRoleCounts: nil)))
        await model.onAppear()

        guard case .failed(let error) = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        // Retryable specifically: `HomeErrorStateView` only draws its retry
        // button for errors that can succeed on a second attempt, and this
        // one can — that is the entire difference from the empty state it
        // replaced.
        #expect(error.isRetryable)
    }

    @Test("An unreadable closet under a cached outfit still shows the outfit")
    func aCachedOutfitSurvivesAnUnreadableCloset() async {
        // The brief came from cache and names a real outfit. Failing the
        // whole screen because the closet fetch dropped would take away a
        // dressed answer the app is holding.
        var data = briefData(closetRoleCounts: nil)
        data.primaryOutfit = Outfit(id: UUID(), userID: UUID(), name: "Thursday")
        let model = HomeViewModel(provider: StubBriefProvider(data: data))

        await model.onAppear()

        guard case .loaded = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
    }
}

// MARK: - Helpers

private func briefData(closetRoleCounts: [ClothingCategory: Int]?) -> HomeBriefData {
    HomeBriefData(
        greetingName: "Marcus",
        weather: nil,
        schedule: nil,
        brief: DailyBrief(id: UUID(), userID: UUID(), briefDate: .now),
        primaryOutfit: nil,
        primaryOutfitItems: [],
        closetRoleCounts: closetRoleCounts
    )
}

private final class StubBriefProvider: HomeBriefProviding, @unchecked Sendable {
    private let data: HomeBriefData

    init(data: HomeBriefData) {
        self.data = data
    }

    func loadTodayBrief(regenerate: Bool) async throws -> HomeBriefData { data }
    func markPrimaryOutfitWorn(_ data: HomeBriefData) async throws {}
    func weatherAuthorization() -> WeatherLocationAuthorization { .denied }
    func requestWeatherPermission() async -> Bool { false }
}
