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

    /// Home is one decision, not a dashboard.
    ///
    /// This screen used to stack NINE modules: greeting header, weather
    /// affordance, hero card, alternatives carousel, wardrobe score, Kyra
    /// insight, purchase opportunity, upcoming occasions, laundry alert. Every
    /// one of them was individually defensible and the sum was an admin
    /// console — nothing on it answered "what do I wear", and the one thing
    /// that could, the garments themselves, was fetched on every load and
    /// discarded unshown.
    ///
    /// What is left is the look, the reason, and two choices. The modules were
    /// triaged rather than deleted: wardrobe score and the laundry alert are
    /// facts about the WARDROBE and now live in the Closet, where a man is
    /// already thinking about his clothes rather than about his morning.
    /// Alternatives became the "Something Else" button. The purchase
    /// opportunity was `nil` on every code path in the app and is honestly
    /// absent until it is not.
    private func loadedContent(_ data: HomeBriefData) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            todayLine(data)
                .padding(.horizontal, AstraSpacing.pagePadding)

            weatherAffordance(for: data)

            TodaysLookView(garments: data.lookGarments) { garment in
                router.select(.closet)
                router.push(ClosetRoute.itemDetail(itemID: garment.item.id))
            }
            .padding(.horizontal, AstraSpacing.pagePadding)

            reason(data)
                .padding(.horizontal, AstraSpacing.pagePadding)

            actions(data)
                .padding(.horizontal, AstraSpacing.pagePadding)
        }
    }

    /// One quiet line: the day, and the weather if we have it.
    ///
    /// Replaces `DailyBriefHeaderView`, which greeted the man by name every
    /// morning. He knows his name. What he does not know is whether it will
    /// rain on the way to the car.
    private func todayLine(_ data: HomeBriefData) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(AstraDateFormatting.longWeekdayAndDate(Date.now))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .textCase(.uppercase)

            Text(data.primaryOutfit?.name ?? String(
                localized: "Today's look",
                comment: "Home title when the outfit has no name"
            ))
                .astraText(.displayL)
                .foregroundStyle(AstraColor.textPrimary)

            if let weather = data.weather {
                Text(AstraWeatherFormatting.temperatureRange(
                    low: weather.temperatureLow,
                    high: weather.temperatureHigh,
                    units: .imperial
                ))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.todayLine")
    }

    /// Why this, in Kyra's words.
    ///
    /// `kyra_message` is written by the server from the deterministic scorer,
    /// not by Luna — P5-KYRA-02 is unbuilt. It is therefore honest but flat,
    /// and it is shown as prose without a "Kyra says" frame, because framing a
    /// scorer's sentence as a stylist speaking is the confounded reading this
    /// repo keeps refusing. When the real voice lands, only the string
    /// changes.
    @ViewBuilder
    private func reason(_ data: HomeBriefData) -> some View {
        if let message = data.brief.kyraMessage ?? data.primaryOutfit?.description, !message.isEmpty {
            Text(message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("home.reason")
        }
    }

    private func actions(_ data: HomeBriefData) -> some View {
        VStack(spacing: AstraSpacing.sm) {
            AstraButton(
                title: String(localized: "Wear This", comment: "Home primary action"),
                isLoading: viewModel.isMarkingWorn
            ) {
                Task { await viewModel.markPrimaryOutfitWorn() }
            }
            .accessibilityIdentifier("home.wearThis")

            Button {
                // The carousel lives in the Closet, where browsing belongs.
                // Home's job is to have decided; this is the door out of that
                // decision, not a second one on the same screen.
                router.select(.closet)
            } label: {
                Text(String(localized: "Something Else", comment: "Home secondary action"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.astraSecondary)
            .accessibilityHint(Text(String(
                localized: "Browse other outfits in your closet",
                comment: "VoiceOver hint for the Home alternatives action"
            )))
            .accessibilityIdentifier("home.somethingElse")
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
