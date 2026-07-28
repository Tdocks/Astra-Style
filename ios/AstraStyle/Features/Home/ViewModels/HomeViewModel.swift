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
            case (.loaded(let a), .loaded(let b)), (.empty(let a), .empty(let b)):
                a.brief.id == b.brief.id
            case (.failed(let a), .failed(let b)):
                a == b
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
        guard case .loading = state else { return }
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

/// A minimal reachability seam so `HomeViewModel` never imports `Network`
/// directly — kept in Home rather than Core/Utilities since, at time of
/// writing, Home is the only screen that needs to distinguish "loaded from
/// cache while offline" from "loaded fresh". If a second feature needs
/// this, promote it to Core/Utilities.
public protocol NetworkReachabilityMonitoring: Sendable {
    func isOffline() async -> Bool
}

public struct SystemNetworkReachabilityMonitor: NetworkReachabilityMonitoring {
    public init() {}

    public func isOffline() async -> Bool {
        await AstraReachability.shared.isOffline
    }
}
