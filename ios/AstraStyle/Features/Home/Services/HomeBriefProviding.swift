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
    /// Next seven local days. Empty on failure so today still renders.
    func loadWeekStrip() async -> [WeekDaySlot]
}

public extension HomeBriefProviding {
    func loadWeekStrip() async -> [WeekDaySlot] { [] }
}

public final class DefaultHomeBriefProvider: HomeBriefProviding {
    private let outfitRepository: OutfitRepository
    private let profileRepository: ProfileRepository
    private let closetRepository: ClosetRepository
    private let weatherService: WeatherService
    /// Added so Home can draw the garments rather than a placeholder. Signing
    /// is batched — one request for the whole look, not one per garment —
    /// which is the reason `ClosetImageURLResolving` has a plural method at
    /// all; see its own header.
    private let imageURLResolver: ClosetImageURLResolving

    public init(
        outfitRepository: OutfitRepository,
        profileRepository: ProfileRepository,
        closetRepository: ClosetRepository,
        weatherService: WeatherService,
        imageURLResolver: ClosetImageURLResolving
    ) {
        self.outfitRepository = outfitRepository
        self.profileRepository = profileRepository
        self.closetRepository = closetRepository
        self.weatherService = weatherService
        self.imageURLResolver = imageURLResolver
    }

    /// Today's brief, read from cache when one exists and generated when it
    /// does not, with the device's own weather reading laid over the top.
    ///
    /// Split out of `loadTodayBrief` because that function had grown past what
    /// one screenful can hold; the two halves are independent — this one is
    /// about where the brief comes from, the caller is about what Home needs
    /// alongside it.
    private func todaysBrief(regenerate: Bool, weather weatherSnapshot: WeatherSnapshot?) async throws -> DailyBrief {
        let serverBrief: DailyBrief
        if !regenerate, let cached = try await outfitRepository.fetchDailyBrief(for: .now) {
            serverBrief = cached
        } else {
            // `regenerate` is threaded through rather than always false:
            // the endpoint is idempotent per `brief_date`, so §6.11's
            // regenerate control would otherwise return the outfits the
            // user just asked to replace.
            serverBrief = try await outfitRepository.generateDailyBrief(
                for: .now,
                regenerate: regenerate,
                weather: weatherSnapshot
            )
        }

        // THE CLIENT'S OWN READING WINS, ON BOTH PATHS.
        //
        // The cached path needs it for an obvious reason: a brief written this
        // morning can predate the moment the user tapped "Enable Weather", and
        // the header should say what Kyra can see NOW.
        //
        // The generate path needs it for a less obvious one, and it was a real
        // bug — this overlay used to apply only to the cached branch. On the
        // generate branch the snapshot goes UP to the server, is persisted, and
        // comes back down on the returned row; so the header was reading a
        // value it already held in a local variable, via a network round trip,
        // and showed nothing at all whenever the server did not echo it back.
        // Depending on a round trip to return something you are holding is
        // fragile in the exact case where it matters — a slow or partial write
        // and the header silently goes blank on a device that knows the
        // weather perfectly well.
        //
        // Overlaying is NOT a write. Attaching a forecast to the persisted row
        // on every Home read would cost a request per screen load for
        // something nobody asked for; the row catches up the next time
        // generation actually runs.
        return weatherSnapshot.map { snapshot in
            var patched = serverBrief
            patched.weatherSnapshot = snapshot
            return patched
        } ?? serverBrief
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
            return loadSparseClosetBrief(profile: profile, closetItems: closetItems)
        }

        // Read before either branch below: both the cached-read path and the
        // generate path want it, and reading it once keeps a slow/failing
        // WeatherKit lookup from being attempted twice for one screen load.
        // Never prompts — see `currentWeatherSnapshotIfAuthorized()`.
        let weatherSnapshot = await currentWeatherSnapshotIfAuthorized()

        let brief = try await todaysBrief(regenerate: regenerate, weather: weatherSnapshot)

        // Both degrade to nil/empty via `try?` inside the wrapper: a hiccup
        // fetching the outfit's items should not cost the user the outfit's
        // name and the reason for it. Concurrent because neither depends on
        // the other.
        //
        // THIS FAN-OUT USED TO BE FIVE CALLS WIDE. The other three —
        // alternative outfits, the wardrobe score, and the calendar's
        // upcoming occasions — were fetched on every Home load and rendered
        // by nothing after the screen became one look: two network round
        // trips and a calendar read per morning, feeding fields no view
        // read. (`fetchWardrobeScore()` throws `.unimplemented`
        // unconditionally, so that one had never returned a value in
        // production at all.) They come back when something draws them.
        async let primaryOutfitTask = fetchPrimaryOutfit(id: brief.primaryOutfitID)
        async let primaryOutfitItemsTask = fetchPrimaryOutfitItems(id: brief.primaryOutfitID)

        let primaryOutfit = await primaryOutfitTask
        let primaryOutfitItems = await primaryOutfitItemsTask

        return HomeBriefData(
            greetingName: profile.greetingName,
            weather: brief.weatherSnapshot,
            schedule: brief.scheduleSnapshot,
            brief: brief,
            primaryOutfit: primaryOutfit,
            primaryOutfitItems: primaryOutfitItems,
            // `closetItems` nil means the fetch failed, and that is passed
            // through as nil rather than flattened to an empty closet — see
            // `HomeBriefData.closetRoleCounts`.
            closetRoleCounts: closetItems.map(Self.roleCounts(of:)),
            wearableRoleCounts: closetItems.map { Self.roleCounts(of: $0.filter(\.isWearableToday)) },
            // After the fan-out, not inside it: this needs the items the
            // fan-out is fetching, and running it concurrently would fetch
            // them twice.
            lookGarments: await LookHydrator(
                closetRepository: closetRepository,
                imageURLResolver: imageURLResolver
            ).hydrate(items: primaryOutfitItems, closet: closetItems ?? [])
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

    /// Carried into `HomeBriefData` so the empty state can name what is
    /// missing rather than guess at it.
    ///
    /// An empty dictionary when the closet read itself failed, which
    /// `emptyReason` reads as "too few items" — the honest reading when the
    /// count is genuinely unknown, and the same choice the `try?` on that
    /// read already makes deliberately.
    private static func roleCounts(of items: [ClosetItem]) -> [ClothingCategory: Int] {
        Dictionary(grouping: items, by: \.category).mapValues(\.count)
    }

    // MARK: - Sparse-closet brief (spec §6.11 empty state)

    /// A real profile, a real closet, and deliberately no outfit —
    /// because there aren't enough garments to build one from.
    ///
    /// `primaryOutfit` is nil, which is what drives
    /// `HomeBriefData.needsMoreClosetItems` and therefore
    /// `HomeViewModel.ViewState.empty`. The header still greets him by
    /// name: `.empty` carries its payload precisely so an empty screen is
    /// not a blank one.
    ///
    /// Weather and schedule are nil rather than fetched. Both arrive on
    /// the `DailyBrief` the server generates, and there is no honest way
    /// to put a forecast on a screen whose whole message is "there is
    /// nothing to dress you in yet" — a weather strip above that copy
    /// implies an outfit recommendation the app has not made.
    private func loadSparseClosetBrief(profile: Profile, closetItems: [ClosetItem]) -> HomeBriefData {
        HomeBriefData(
            greetingName: profile.greetingName,
            weather: nil,
            schedule: nil,
            brief: DailyBrief(id: UUID(), userID: profile.id, briefDate: .now),
            primaryOutfit: nil,
            primaryOutfitItems: [],
            closetRoleCounts: Self.roleCounts(of: closetItems),
            wearableRoleCounts: Self.roleCounts(of: closetItems.filter(\.isWearableToday))
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

extension DefaultHomeBriefProvider {
    public func loadWeekStrip() async -> [WeekDaySlot] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 6, to: start) else { return [] }
        var briefs = (try? await outfitRepository.fetchDailyBriefs(from: start, to: end)) ?? []
        let days = (0...6).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let have = Set(briefs.map { DateFormatter.astraDay.string(from: $0.briefDate) })
        let missing = days.contains { !have.contains(DateFormatter.astraDay.string(from: $0)) }
        if missing {
            _ = try? await outfitRepository.generatePackingPlan(
                PackingRequest(
                    destination: "",
                    startDate: start,
                    endDate: end,
                    luggageConstraint: .noConstraint,
                    hasLaundryAccess: true
                )
            )
            briefs = (try? await outfitRepository.fetchDailyBriefs(from: start, to: end)) ?? []
        }
        let outfitIDs = Array(Set(briefs.compactMap(\.primaryOutfitID)))
        let outfits = (try? await outfitRepository.fetchOutfits(ids: outfitIDs)) ?? []
        let outfitByID = Dictionary(uniqueKeysWithValues: outfits.map { ($0.id, $0) })
        let briefByDay = Dictionary(
            uniqueKeysWithValues: briefs.map { (DateFormatter.astraDay.string(from: $0.briefDate), $0) }
        )
        return days.map { date in
            let brief = briefByDay[DateFormatter.astraDay.string(from: date)]
            return WeekDaySlot(
                date: date,
                outfit: brief?.primaryOutfitID.flatMap { outfitByID[$0] },
                occasionHeadline: brief?.scheduleSnapshot?.headline
            )
        }
    }
}
