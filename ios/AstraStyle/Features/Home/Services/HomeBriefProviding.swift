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

    /// Resolves the *current* session's guest status at call time (a guest
    /// session can end mid-lifetime via migration, so this cannot be
    /// captured once at construction) — injected rather than read from a
    /// global so this type stays testable, matching the pattern
    /// `GuestAwareClosetRepository` already uses for the same question.
    /// Typically `{ await sessionStore.currentIsGuest() }` (see
    /// `Core/Auth/SessionStore.swift`, backed by `AuthSession.isGuest`).
    private let isGuest: @Sendable () async -> Bool

    public init(
        outfitRepository: OutfitRepository,
        profileRepository: ProfileRepository,
        closetRepository: ClosetRepository,
        weatherService: WeatherService,
        calendarService: CalendarService,
        isGuest: @escaping @Sendable () async -> Bool
    ) {
        self.outfitRepository = outfitRepository
        self.profileRepository = profileRepository
        self.closetRepository = closetRepository
        self.weatherService = weatherService
        self.calendarService = calendarService
        self.isGuest = isGuest
    }

    public func loadTodayBrief(regenerate: Bool) async throws -> HomeBriefData {
        // Guests have no server-side profile row at all (ADR 0011: "no
        // server-side identity at all" until migration), so
        // `profileRepository.fetchCurrentProfile()` below would be a real
        // Supabase call for a session that must never touch Supabase — and
        // it would fail besides. Route guests to a brief built entirely
        // from local state instead, matching the pattern already
        // established in `AstraStyleApp.resolveLaunchRoute()`.
        if await isGuest() {
            return await loadGuestBrief()
        }

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

    // MARK: - Guest brief (ADR 0011; never touches Supabase)

    /// Builds the guest Home brief from local state only — no
    /// `profileRepository` or `outfitRepository` call, both of which are
    /// Supabase-backed and neither of which has a guest-local counterpart
    /// (there is no server-generated Daily Brief without an Edge Function
    /// round trip). `closetRepository` is safe to use as-is: it's always
    /// `GuestAwareClosetRepository` (see `AppContainer`), which already
    /// routes a guest session's calls to on-device storage.
    ///
    /// A guest's brief therefore always has no primary outfit — outfit
    /// generation is a server capability guests don't have — which drives
    /// `HomeBriefData.needsMoreClosetItems`, so `HomeViewModel` renders the
    /// real "Let's build your first look" empty state (spec §6.11) instead
    /// of an error. The one thing that *is* real here is the local closet:
    /// `fetchLaundryCount()` below reads it through the same guest-aware
    /// repository, not a hardcoded zero.
    private func loadGuestBrief() async -> HomeBriefData {
        async let wardrobeScoreTask = fetchWardrobeScoreSafely()
        async let laundryCountTask = fetchLaundryCount()

        let wardrobeScore = await wardrobeScoreTask
        let laundryCount = await laundryCountTask

        let brief = DailyBrief(id: UUID(), userID: UUID(), briefDate: .now)

        return HomeBriefData(
            greetingName: String(localized: "there", comment: "Home header greeting for a guest session, which has no display name to greet by"),
            weather: nil,
            schedule: nil,
            brief: brief,
            primaryOutfit: nil,
            primaryOutfitItems: [],
            alternativeOutfits: [],
            wardrobeScore: wardrobeScore,
            laundryAlertItemCount: laundryCount,
            upcomingOccasions: [],
            purchaseOpportunity: nil
        )
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
