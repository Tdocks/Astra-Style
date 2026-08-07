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

    /// Current weather-location authorization, read without prompting
    /// (P4-HOME-05). `HomeViewModel` uses this to decide whether to show
    /// the "enable weather" explanation — only when nobody has decided yet
    /// — versus the honest denied state, versus nothing at all once
    /// weather is already flowing through `loadTodayBrief`.
    func weatherAuthorization() -> WeatherLocationAuthorization

    /// Spec §7's in-context permission ask ("Location: when enabling
    /// weather"). The one path from a live Home screen to
    /// `WeatherService.requestLocationPermissionIfNeeded()` — see
    /// `HomeViewModel.enableWeather()`, its only caller, which only calls
    /// this after `WeatherOptInCardView` has already explained why.
    /// Returns whether permission is now granted.
    func requestWeatherPermission() async -> Bool
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

        // §6.11's empty state is a fact about the closet, not a failure of
        // the brief generator — a man who finished onboarding sixty seconds
        // ago has nothing to be dressed in, and asking the server to build
        // him an outfit anyway can only fail. Ask the closet first.
        //
        // The count is read here rather than inferred from a nil
        // `primaryOutfitID` on the way back because that inference requires
        // the round trip to have succeeded. Before this check existed the
        // empty state was reachable only by a guest session: every real user
        // went to `generateDailyBrief`, whose Edge Function is not built
        // (P4-HOME-02), and got an error screen where §6.11 specifies an
        // invitation. `try?` rather than `try` on purpose — if the closet
        // itself is unreachable we genuinely do not know the count, and
        // falling through to the old path surfaces that honestly instead
        // of telling a man with forty garments that he owns nothing.
        let closetItems = try? await closetRepository.fetchItems()
        if let closetItems, closetItems.count < HomeBriefData.minimumItemsForOutfits {
            return await loadSparseClosetBrief(profile: profile, closetItems: closetItems)
        }

        // Read before either branch below: both the cached-read path and the
        // generate path want it, and reading it once keeps a slow/failing
        // WeatherKit lookup from being attempted twice for one screen load.
        // Never prompts — see `currentWeatherSnapshotIfAuthorized()`.
        let weatherSnapshot = await currentWeatherSnapshotIfAuthorized()

        let brief: DailyBrief
        if !regenerate, let cached = try await outfitRepository.fetchDailyBrief(for: .now) {
            // A cached brief can predate today's weather permission grant —
            // e.g. the very first Home load of the day happened before the
            // user tapped "Enable Weather". Overlay the fresh client reading
            // onto the value handed to `HomeBriefData` so the header is
            // honest about what Kyra can see right now, WITHOUT writing back
            // to the server: this is a read, and turning it into a network
            // write purely to attach a forecast would cost a request on
            // every single Home load for no reason the user asked for. The
            // persisted row catches up the next time generation actually
            // runs (a new day, or an explicit regenerate).
            brief = weatherSnapshot.map { snapshot in
                var patched = cached
                patched.weatherSnapshot = snapshot
                return patched
            } ?? cached
        } else {
            // `regenerate` is threaded through rather than always false:
            // the endpoint is idempotent per `brief_date`, so §6.11's
            // regenerate control would otherwise return the outfits the
            // user just asked to replace.
            brief = try await outfitRepository.generateDailyBrief(for: .now, regenerate: regenerate, weather: weatherSnapshot)
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

    public func weatherAuthorization() -> WeatherLocationAuthorization {
        weatherService.currentAuthorization()
    }

    public func requestWeatherPermission() async -> Bool {
        await weatherService.requestLocationPermissionIfNeeded()
    }

    // MARK: - Sparse-closet brief (spec §6.11 empty state)

    /// A real profile, a real closet, and deliberately no outfit —
    /// because there aren't enough garments to build one from.
    ///
    /// `primaryOutfit` is nil, which is what drives
    /// `HomeBriefData.needsMoreClosetItems` and therefore
    /// `HomeViewModel.ViewState.empty`. The header still greets him by
    /// name and the laundry count is still real: `.empty` carries its
    /// payload precisely so an empty screen is not a blank one.
    ///
    /// Weather and schedule are nil rather than fetched. Both arrive on
    /// the `DailyBrief` the server generates, and there is no honest way
    /// to put a forecast on a screen whose whole message is "there is
    /// nothing to dress you in yet" — a weather strip above that copy
    /// implies an outfit recommendation the app has not made.
    private func loadSparseClosetBrief(profile: Profile, closetItems: [ClosetItem]) async -> HomeBriefData {
        async let wardrobeScoreTask = fetchWardrobeScoreSafely()
        async let occasionsTask = calendarService.fetchUpcomingEvents(
            in: DateInterval(start: .now, duration: 60 * 60 * 18),
            userID: profile.id
        )

        let wardrobeScore = await wardrobeScoreTask
        let occasions = await occasionsTask

        return HomeBriefData(
            greetingName: profile.greetingName,
            weather: nil,
            schedule: nil,
            brief: DailyBrief(id: UUID(), userID: profile.id, briefDate: .now),
            primaryOutfit: nil,
            primaryOutfitItems: [],
            alternativeOutfits: [],
            wardrobeScore: wardrobeScore,
            laundryAlertItemCount: closetItems.filter { $0.laundryState == .laundry }.count,
            upcomingOccasions: occasions,
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

    /// The client's own weather reading, or `nil` — never a guess and
    /// never a prompt.
    ///
    /// Only ever fetches when `currentAuthorization()` already reports
    /// `.authorized`. A `.notDetermined` result here does NOT fall through
    /// to `requestLocationPermissionIfNeeded()`: that would put the system
    /// permission dialog on screen the instant Home loads, with none of
    /// `WeatherOptInCardView`'s explanation in front of it — exactly what
    /// spec §7's "in context" requirement and this ticket's "never during
    /// onboarding" note both rule out. Asking is `HomeViewModel
    /// .enableWeather()`'s job, reachable only from that explicit button.
    /// A `.denied` result also returns nil rather than calling
    /// `currentSnapshot()` — it would only throw, and the caller already
    /// knows the answer from `currentAuthorization()`.
    private func currentWeatherSnapshotIfAuthorized() async -> WeatherSnapshot? {
        guard weatherService.currentAuthorization() == .authorized else { return nil }
        return try? await weatherService.currentSnapshot()
    }
}
