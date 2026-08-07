//
//  HomeViewModel.swift
//  AstraStyle
//
//  Drives `HomeView` (spec §6.11 Kyra's Daily Brief). `@Observable` and
//  `@MainActor` per spec §8's state-management rules; owns exactly one
//  dependency — `HomeBriefProviding` — and performs zero networking
//  itself, matching spec §8's "Never place network calls directly in
//  views" extended to the view-model boundary as well.
//
//  This is the reference implementation the rest of the feature modules
//  (P3-CLOSET, P4-OUTFIT, P5-KYRA, ...) are expected to pattern their own
//  view models after: an explicit `ViewState` enum covering loading /
//  loaded / empty / error, a separate `isOffline` flag (offline is
//  orthogonal to the four content states — you can be offline *and*
//  showing cached content), and no view-layer type ever touching a
//  repository directly.
//

import Foundation
import Observation

@MainActor
@Observable
public final class HomeViewModel {
    public enum ViewState: Equatable {
        case loading
        case loaded(HomeBriefData)
        /// Signed in, reachable, but the brief has no primary outfit
        /// because the closet doesn't have enough items yet
        /// (spec §6.11 "Empty state"). Still carries `HomeBriefData` so the
        /// header can greet the user by name rather than the view reaching
        /// for placeholder/sample data to fill the gap.
        case empty(HomeBriefData)
        case failed(AstraError)

        public static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading):
                true
            case (.loaded(let left), .loaded(let right)), (.empty(let left), .empty(let right)):
                left.brief.id == right.brief.id
            case (.failed(let left), .failed(let right)):
                left == right
            default:
                false
            }
        }

        /// The offline banner only makes sense over content that's
        /// actually rendering (loaded or the closet-empty state) — not
        /// over the loading skeleton or an error screen, which already
        /// communicate their own status.
        var showsOfflineBannerWhenStale: Bool {
            switch self {
            case .loaded, .empty: true
            case .loading, .failed: false
            }
        }
    }

    public private(set) var state: ViewState = .loading

    /// Independent of `state` — the Daily Brief header still needs to
    /// render a "you're offline, showing your last brief" banner even
    /// while `state == .loaded` from cache (spec §7 "Cached closet and
    /// outfits remain viewable").
    public private(set) var isOffline = false

    public private(set) var isMarkingWorn = false
    public private(set) var isRegenerating = false

    /// Drives `WeatherOptInCardView`/the denied-state notice (P4-HOME-05).
    /// Starts `.notDetermined` — the same value a brand-new install's
    /// `CLLocationManager` reports — so a view rendered before `onAppear()`
    /// runs (a `#Preview`, a test asserting on the freshly-constructed view
    /// model) shows nothing rather than a false "denied" state.
    public private(set) var weatherAuthorization: WeatherLocationAuthorization = .notDetermined
    public private(set) var isRequestingWeatherPermission = false

    private let provider: HomeBriefProviding
    private let analyticsClient: AnalyticsClient
    private let networkMonitor: NetworkReachabilityMonitoring

    public init(
        provider: HomeBriefProviding,
        analyticsClient: AnalyticsClient = NoOpAnalyticsClient(),
        networkMonitor: NetworkReachabilityMonitoring = SystemNetworkReachabilityMonitor()
    ) {
        self.provider = provider
        self.analyticsClient = analyticsClient
        self.networkMonitor = networkMonitor
    }

    public func onAppear() async {
        isOffline = await networkMonitor.isOffline()
        // Read-only — never prompts. First use of Home is when spec §7's
        // location permission becomes reachable at all, but the ask itself
        // waits for `enableWeather()`, which only `WeatherOptInCardView`'s
        // button calls.
        weatherAuthorization = provider.weatherAuthorization()
        guard case .loading = state else { return }
        await load(regenerate: false)
    }

    /// Spec §7's "Location: when enabling weather", requested in context on
    /// first use of Home and nowhere during onboarding — the requirement
    /// `P2-ONBOARD-06` dropped and this ticket now owns (see
    /// `docs/02-task-breakdown.md`'s `P4-HOME-05` entry).
    ///
    /// The one caller of `HomeBriefProviding.requestWeatherPermission()`
    /// reachable from a live screen, and it is only ever invoked from
    /// `WeatherOptInCardView`'s button — which has already put the
    /// explanation on screen. That ordering is the whole point: nothing
    /// else in this view model calls it, so the system prompt cannot
    /// appear before a man has read why.
    public func enableWeather() async {
        guard weatherAuthorization == .notDetermined, !isRequestingWeatherPermission else { return }
        isRequestingWeatherPermission = true
        defer { isRequestingWeatherPermission = false }
        let granted = await provider.requestWeatherPermission()
        weatherAuthorization = granted ? .authorized : .denied
        guard granted else { return }
        // Reload rather than patch `state` in place: the brief the user is
        // looking at was generated/read before weather existed, and a
        // fresh `loadTodayBrief()` is what actually attaches it (see
        // `DefaultHomeBriefProvider`'s cached-vs-generate weather overlay).
        await load(regenerate: false)
    }

    public func refresh() async {
        await load(regenerate: false)
    }

    public func regenerate() async {
        guard !isRegenerating else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        await load(regenerate: true)
    }

    public func markPrimaryOutfitWorn() async {
        guard case .loaded(let data) = state, let outfitID = data.primaryOutfit?.id, !isMarkingWorn else { return }
        isMarkingWorn = true
        defer { isMarkingWorn = false }
        do {
            try await provider.markPrimaryOutfitWorn(data)
            analyticsClient.log(.outfitMarkedWorn(outfitID: outfitID))
        } catch {
            // Marking worn failing doesn't invalidate the whole brief —
            // surface it as a transient condition rather than replacing
            // the loaded content with an error screen.
            isOffline = await networkMonitor.isOffline()
        }
    }

    private func load(regenerate: Bool) async {
        isOffline = await networkMonitor.isOffline()
        if !regenerate {
            state = .loading
        }
        do {
            let data = try await provider.loadTodayBrief(regenerate: regenerate)
            state = data.needsMoreClosetItems ? .empty(data) : .loaded(data)
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }
}

// `NetworkReachabilityMonitoring` / `SystemNetworkReachabilityMonitor` now
// live in Core/Utilities/NetworkReachabilityMonitoring.swift — promoted
// out of this file once `Features/Slice` became a second consumer, per
// the promotion note that used to be here.
