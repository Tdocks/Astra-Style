//
//  HomeView.swift
//  AstraStyle
//
//  Kyra's Daily Brief (spec §6.11) — the reference implementation other
//  feature modules are patterned after. No network calls happen in this
//  file; everything routes through `HomeViewModel`. Every state spec §21
//  requires is represented: loading (skeleton), loaded, empty, offline
//  (as a banner layered over loaded/empty), and recoverable error (with
//  retry).
//

import SwiftUI

public struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @Environment(AppRouter.self) private var router

    public init(viewModel: HomeViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                if viewModel.isOffline, viewModel.state.showsOfflineBannerWhenStale {
                    HomeOfflineBanner()
                        .padding(.horizontal, AstraSpacing.pagePadding)
                }

                content
            }
            .padding(.vertical, AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.refresh()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.onAppear()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            HomeLoadingSkeletonView()

        case .failed(let error):
            HomeErrorStateView(error: error) {
                Task { await viewModel.refresh() }
            }

        case .empty(let data):
            emptyStateContent(data)

        case .loaded(let data):
            loadedContent(data)
        }
    }

    private func emptyStateContent(_ data: HomeBriefData) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            DailyBriefHeaderView(
                greetingName: data.greetingName,
                weather: data.weather,
                schedule: data.schedule,
                units: .imperial,
                onTapKyra: { router.startAskKyra() }
            )
            .padding(.horizontal, AstraSpacing.pagePadding)

            weatherAffordance(for: data)

            HomeEmptyStateView(reason: data.emptyReason ?? .noOutfitYet) {
                // A closet short of a whole role is a job for the batch
                // path: he is about to photograph several trousers, not one.
                if case .missingRoles = data.emptyReason {
                    router.startScan(mode: .batchCloset)
                } else {
                    router.startScan()
                }
            }
        }
    }

    private func loadedContent(_ data: HomeBriefData) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            DailyBriefHeaderView(
                greetingName: data.greetingName,
                weather: data.weather,
                schedule: data.schedule,
                units: .imperial,
                onTapKyra: { router.startAskKyra() }
            )
            .padding(.horizontal, AstraSpacing.pagePadding)

            weatherAffordance(for: data)

            if let outfit = data.primaryOutfit {
                HeroOutfitCardView(
                    outfit: outfit,
                    weather: data.weather,
                    units: .imperial,
                    isMarkingWorn: viewModel.isMarkingWorn,
                    onWearThis: { Task { await viewModel.markPrimaryOutfitWorn() } },
                    onAlternatives: { router.push(HomeRoute.alternativeLooks(briefID: data.brief.id)) },
                    onEdit: { router.presentModal(.outfitBuilder(.builder(startingOutfitID: outfit.id))) },
                    onVisualize: { router.presentModal(.studioGeneration(outfitID: outfit.id)) }
                )
                .padding(.horizontal, AstraSpacing.pagePadding)
            }

            modules(data)
        }
    }

    /// Spec §7's in-context weather permission ask, and its honest fallback
    /// (P4-HOME-05). Shown only while `data.weather` has nothing to say —
    /// once real weather is on the header there is nothing left to ask
    /// for or explain, and while `.authorized` but still nil (a transient
    /// WeatherKit failure) this deliberately renders nothing further: the
    /// header's own absence of a temperature already told the honest
    /// story, and repeating it here would be noise, not information.
    @ViewBuilder
    private func weatherAffordance(for data: HomeBriefData) -> some View {
        if data.weather == nil {
            Group {
                switch viewModel.weatherAuthorization {
                case .notDetermined:
                    WeatherOptInCardView(isRequesting: viewModel.isRequestingWeatherPermission) {
                        Task { await viewModel.enableWeather() }
                    }
                case .denied:
                    WeatherDeniedNoticeView()
                case .authorized:
                    EmptyView()
                }
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
        }
    }

    /// Everything below the hero card: the optional Home modules, in the order
    /// spec §5 lists them. Separate from `loadedContent` so the screen's spine
    /// (greeting, then hero outfit, then modules) stays readable at a glance
    /// and each module's presence condition is not buried in a long body.
    @ViewBuilder
    private func modules(_ data: HomeBriefData) -> some View {
        if !data.alternativeOutfits.isEmpty {
            AlternativeLooksCarouselView(outfits: data.alternativeOutfits) { outfit in
                router.push(HomeRoute.outfitDetail(outfitID: outfit.id))
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
        }

        if let wardrobeScore = data.wardrobeScore {
            WardrobeScoreModuleView(score: wardrobeScore)
                .padding(.horizontal, AstraSpacing.pagePadding)
        }

        if let kyraMessage = data.brief.kyraMessage {
            KyraInsightModuleView(message: kyraMessage)
                .padding(.horizontal, AstraSpacing.pagePadding)
        }

        if let opportunity = data.purchaseOpportunity {
            PurchaseOpportunityModuleView(opportunity: opportunity) {
                router.push(HomeRoute.productDecision(candidateID: opportunity.productCandidate.id))
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
        }

        if !data.upcomingOccasions.isEmpty {
            UpcomingOccasionsModuleView(occasions: data.upcomingOccasions) { occasion in
                router.push(HomeRoute.occasionDetail(occasionID: occasion.id))
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
        }

        if data.laundryAlertItemCount > 0 {
            LaundryAlertModuleView(itemCount: data.laundryAlertItemCount) {
                router.select(.closet)
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
        }
    }
}

// MARK: - Previews

#Preview("Loaded") {
    NavigationStack {
        HomeView(viewModel: HomeViewModel(provider: PreviewHomeBriefProvider()))
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    NavigationStack {
        HomeView(viewModel: HomeViewModel(provider: PreviewHomeBriefProvider(mode: .empty)))
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

#Preview("Error") {
    NavigationStack {
        HomeView(viewModel: HomeViewModel(provider: PreviewHomeBriefProvider(mode: .error)))
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

/// A synchronous-feeling preview provider — avoids composing four mock
/// repositories just to drive `#Preview`. Production code and real
/// previews both go through `DefaultHomeBriefProvider` +
/// `Core/Mocks/Mock*Repository`; this one exists purely to make the three
/// state previews above trivial to read.
private struct PreviewHomeBriefProvider: HomeBriefProviding {
    enum Mode { case loaded, empty, error }
    var mode: Mode = .loaded

    func loadTodayBrief(regenerate: Bool) async throws -> HomeBriefData {
        switch mode {
        case .loaded:
            return HomeBriefData(
                greetingName: SampleData.profile.greetingName,
                weather: SampleData.weatherSnapshot,
                schedule: SampleData.scheduleSnapshot,
                brief: SampleData.dailyBrief(),
                primaryOutfit: SampleData.heroOutfit,
                primaryOutfitItems: SampleData.heroOutfitItems(),
                alternativeOutfits: SampleData.alternativeOutfits,
                wardrobeScore: SampleData.wardrobeScore,
                laundryAlertItemCount: 2,
                upcomingOccasions: MockCalendarService().events,
                purchaseOpportunity: nil
            )
        case .empty:
            var brief = SampleData.dailyBrief()
            brief.primaryOutfitID = nil
            return HomeBriefData(
                greetingName: SampleData.profile.greetingName,
                weather: nil,
                schedule: nil,
                brief: brief,
                primaryOutfit: nil,
                primaryOutfitItems: [],
                alternativeOutfits: [],
                wardrobeScore: nil,
                laundryAlertItemCount: 0,
                upcomingOccasions: [],
                purchaseOpportunity: nil
            )
        case .error:
            throw AstraError.network("Check your connection and try again.")
        }
    }

    func markPrimaryOutfitWorn(_ data: HomeBriefData) async throws {}

    func weatherAuthorization() -> WeatherLocationAuthorization { .authorized }
    func requestWeatherPermission() async -> Bool { true }
}
