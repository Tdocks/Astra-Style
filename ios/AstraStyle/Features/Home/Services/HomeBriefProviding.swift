//
//  HomeBriefProviding.swift
//  AstraStyle
//
//  The single protocol `HomeViewModel` depends on. `DefaultHomeBriefProvider`
//  composes the Domain repository protocols (spec §8) into the one shape
//  Home actually needs — this is the only place in the app that combines
//  `OutfitRepository`, `ProfileRepository`, `ClosetRepository`, and
//  `WeatherService` for a single screen, keeping that fan-out out of the
//  view model per spec §21's "no network calls in views" mandate extended
//  to view models: a view model should orchestrate state, not repository
//  wiring.
//
//  Because it's generic over the four protocols it composes,
//  `DefaultHomeBriefProvider` works identically whether it's handed
//  `Live*` or `Mock*` conformances — no separate mock implementation of
//  this type is needed (spec §31's "mocks sit behind the same protocols"
//  principle applies one level up here).
//

import Foundation

public protocol HomeBriefProviding: Sendable {
    /// Loads (or, if `regenerate` is `true`, force-regenerates) today's
    /// brief and hydrates every module Home needs to render.
    func loadTodayBrief(regenerate: Bool) async throws -> HomeBriefData

    func markPrimaryOutfitWorn(_ data: HomeBriefData) async throws
}

public final class DefaultHomeBriefProvider: HomeBriefProviding {
    private let outfitRepository: OutfitRepository
    private let profileRepository: ProfileRepository
    private let closetRepository: ClosetRepository
    private let weatherService: WeatherService
    private let calendarService: CalendarService

    public init(
        outfitRepository: OutfitRepository,
        profileRepository: ProfileRepository,
        closetRepository: ClosetRepository,
        weatherService: WeatherService,
        calendarService: CalendarService
    ) {
        self.outfitRepository = outfitRepository
        self.profileRepository = profileRepository
        self.closetRepository = closetRepository
        self.weatherService = weatherService
        self.calendarService = calendarService
    }

    public func loadTodayBrief(regenerate: Bool) async throws -> HomeBriefData {
        let profile = try await profileRepository.fetchCurrentProfile()

        let brief: DailyBrief
        if !regenerate, let cached = try await outfitRepository.fetchDailyBrief(for: .now) {
            brief = cached
        } else {
            brief = try await outfitRepository.generateDailyBrief(for: .now)
        }

        // Each of these degrades independently to an empty/nil result on
        // failure via `try?` inside the wrapper — a hiccup fetching, say,
        // upcoming occasions should never block the primary outfit from
        // rendering. Run them concurrently since none depend on another.
        async let primaryOutfitTask = fetchPrimaryOutfit(id: brief.primaryOutfitID)
        async let primaryOutfitItemsTask = fetchPrimaryOutfitItems(id: brief.primaryOutfitID)
        async let alternativeOutfitsTask = fetchAlternativeOutfits(ids: brief.alternativeOutfitIDs)
        async let wardrobeScoreTask = fetchWardrobeScoreSafely()
        async let occasionsTask = calendarService.fetchUpcomingEvents(
            in: DateInterval(start: .now, duration: 60 * 60 * 18),
            userID: profile.id
        )
        async let laundryCountTask = fetchLaundryCount()

        let primaryOutfit = await primaryOutfitTask
        let primaryOutfitItems = await primaryOutfitItemsTask
        let alternativeOutfits = await alternativeOutfitsTask
        let wardrobeScore = await wardrobeScoreTask
        let occasions = await occasionsTask
        let laundryCount = await laundryCountTask

        return HomeBriefData(
            greetingName: profile.greetingName,
            weather: brief.weatherSnapshot,
            schedule: brief.scheduleSnapshot,
            brief: brief,
            primaryOutfit: primaryOutfit,
            primaryOutfitItems: primaryOutfitItems,
            alternativeOutfits: alternativeOutfits,
            wardrobeScore: wardrobeScore,
            laundryAlertItemCount: laundryCount,
            upcomingOccasions: occasions,
            purchaseOpportunity: nil
        )
    }

    public func markPrimaryOutfitWorn(_ data: HomeBriefData) async throws {
        guard let outfitID = data.primaryOutfit?.id else {
            throw AstraError.validation("There's no outfit to mark worn yet.")
        }
        try await outfitRepository.recordWear(outfitID: outfitID, wornAt: .now, occasion: nil, rating: nil, feedback: nil)
    }

    // MARK: - Concurrent-fetch helpers
    //
    // Each wrapper swallows its own failure (`try?`) so one degraded
    // module never fails the whole Daily Brief load — see spec §21's
    // per-feature error/empty-state requirement, applied at the
    // module level within a single screen.

    private func fetchPrimaryOutfit(id: UUID?) async -> Outfit? {
        guard let id else { return nil }
        return try? await outfitRepository.fetchOutfit(id: id)
    }

    private func fetchPrimaryOutfitItems(id: UUID?) async -> [OutfitItem] {
        guard let id else { return [] }
        return (try? await outfitRepository.fetchOutfitItems(outfitID: id)) ?? []
    }

    private func fetchAlternativeOutfits(ids: [UUID]) async -> [Outfit] {
        (try? await outfitRepository.fetchOutfits(ids: ids)) ?? []
    }

    private func fetchWardrobeScoreSafely() async -> WardrobeScore? {
        try? await closetRepository.fetchWardrobeScore()
    }

    private func fetchLaundryCount() async -> Int {
        ((try? await closetRepository.fetchItems()) ?? []).filter { $0.laundryState == .laundry }.count
    }
}
