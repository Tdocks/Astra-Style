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
    private let shoppingRepository: ShoppingRepository
    @State private var isPastingLink = false

    public init(viewModel: HomeViewModel, shoppingRepository: ShoppingRepository) {
        _viewModel = State(wrappedValue: viewModel)
        self.shoppingRepository = shoppingRepository
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
        // Same signal Closet already watches: a sheet does not tear down
        // this view, so `.task` never re-fires after Scan One. Without
        // this, Home keeps the pre-scan empty count until pull-to-refresh.
        .onChange(of: router.presentedModal?.id) { previous, current in
            guard current == nil, previous != nil else { return }
            Task { await viewModel.reloadAfterExternalChange() }
        }
        .alert(
            Text(actionFailureTitle),
            isPresented: actionErrorPresented,
            presenting: viewModel.actionError
        ) { _ in
            Button(dismissTitle) { viewModel.clearActionError() }
        } message: { error in
            Text(error.message)
        }
        .sheet(isPresented: $isPastingLink) {
            ProductLinkPasteSheet(shoppingRepository: shoppingRepository) { candidateID in
                router.push(HomeRoute.productDecision(candidateID: candidateID))
            }
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

    /// The same quiet day line the loaded screen opens with, then the reason
    /// there is no look.
    ///
    /// This used to open with `DailyBriefHeaderView` — "Good morning,
    /// Marcus" over a weather strip — while the loaded path had already
    /// stopped greeting him. Two screens one tap apart addressing him
    /// differently is the sort of seam that makes an app feel assembled
    /// rather than designed, and the greeting was the half that had already
    /// been argued down: he knows his name.
    private func emptyStateContent(_ data: HomeBriefData) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            dayLine
                .padding(.horizontal, AstraSpacing.pagePadding)

            weatherAffordance(for: data)

            HomeEmptyStateView(reason: data.emptyReason ?? .noOutfitYet) {
                if case .inTheWash = data.emptyReason {
                    router.select(.closet)
                } else {
                    // Dogfood loop is Scan One (ADR 0015). Batch remains on
                    // Closet's scan menu; sending a missing-role CTA into it
                    // put a Partial surface on the only door Home has.
                    router.startScan()
                }
            }

            pasteLinkButton
                .padding(.horizontal, AstraSpacing.pagePadding)
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

            actions
                .padding(.horizontal, AstraSpacing.pagePadding)
        }
    }

    /// The date, and nothing else. Shared by the loaded screen and the empty
    /// one so both open the same way — the empty screen has no outfit to
    /// name and no forecast worth putting above "there is nothing to dress
    /// you in yet", but it is still today.
    private var dayLine: some View {
        Text(AstraDateFormatting.longWeekdayAndDate(Date.now))
            .astraText(.caption)
            .foregroundStyle(AstraColor.textMuted)
            .textCase(.uppercase)
    }

    /// One quiet line: the day, and the weather if we have it.
    ///
    /// Replaces `DailyBriefHeaderView`, which greeted the man by name every
    /// morning. He knows his name. What he does not know is whether it will
    /// rain on the way to the car.
    private func todayLine(_ data: HomeBriefData) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            dayLine

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

    private var actions: some View {
        VStack(spacing: AstraSpacing.sm) {
            AstraButton(
                title: wearThisTitle,
                isLoading: viewModel.isMarkingWorn
            ) {
                markWorn()
            }
            .disabled(viewModel.hasMarkedWorn)
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

            pasteLinkButton

            todayShareLink

            if case .loaded(let data) = viewModel.state, data.primaryOutfit != nil {
                Button {
                    router.presentModal(.studioGeneration(outfitID: data.primaryOutfit?.id))
                } label: {
                    Text(String(localized: "See this on you", comment: "Home door into Studio for today's look"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.astraSecondary)
                .accessibilityIdentifier("home.seeOnYou")
            }

            makePublicOffer
        }
    }

    /// System share of today's look name + why. Not a feed.
    @ViewBuilder
    private var todayShareLink: some View {
        if case .loaded(let data) = viewModel.state, let outfit = data.primaryOutfit {
            let why = data.brief.kyraMessage ?? outfit.description
            ShareLink(item: HomeShareCopy.shareText(name: outfit.name, why: why)) {
                Label(
                    String(localized: "Share this look", comment: "Home share of today's look"),
                    systemImage: "square.and.arrow.up"
                )
                .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("home.shareLook")
        }
    }

    /// Opt-in after Wear This. Never auto-publishes the closet.
    @ViewBuilder
    private var makePublicOffer: some View {
        if viewModel.canOfferPublicLook {
            Button {
                Task { await viewModel.makeWornLookPublic() }
            } label: {
                Text(String(localized: "Show this look to other men", comment: "Home post-wear public opt-in"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("home.makeLookPublic")
        }
    }

    /// He brought the URL. This is not a shop suggestion.
    private var pasteLinkButton: some View {
        Button {
            isPastingLink = true
        } label: {
            Text(String(localized: "Paste a link", comment: "Home paste-a-link don't-buy door"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.astraSecondary)
        .accessibilityIdentifier("home.pasteLink")
    }

    /// Haptics live here, not in the view model — same rule as
    /// `OutfitDetailView.markWorn()` so a unit test never reaches for the
    /// Taptic Engine, and success fires on the write, not the tap.
    private func markWorn() {
        Task {
            await viewModel.markPrimaryOutfitWorn()
            if viewModel.actionError == nil, viewModel.hasMarkedWorn {
                AstraHaptics.success()
            }
        }
    }

    private var wearThisTitle: String {
        viewModel.hasMarkedWorn
            ? String(localized: "Worn today", comment: "Home Wear This after a successful write")
            : String(localized: "Wear This", comment: "Home primary action")
    }

    private var actionFailureTitle: String {
        String(localized: "Couldn't record that", comment: "Home Wear This failure alert title")
    }

    private var dismissTitle: String {
        String(localized: "OK", comment: "Dismisses the Home Wear This failure alert")
    }

    private var actionErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.actionError != nil },
            set: { isPresented in
                if !isPresented { viewModel.clearActionError() }
            }
        )
    }

}

// MARK: - Previews

#Preview("Loaded") {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(provider: PreviewHomeBriefProvider()),
            shoppingRepository: MockShoppingRepository()
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(provider: PreviewHomeBriefProvider(mode: .empty)),
            shoppingRepository: MockShoppingRepository()
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

#Preview("Error") {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(provider: PreviewHomeBriefProvider(mode: .error)),
            shoppingRepository: MockShoppingRepository()
        )
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
            )
        case .error:
            throw AstraError.network("Check your connection and try again.")
        }
    }

    func markPrimaryOutfitWorn(_ data: HomeBriefData) async throws {}

    func weatherAuthorization() -> WeatherLocationAuthorization { .authorized }
    func requestWeatherPermission() async -> Bool { true }
}
