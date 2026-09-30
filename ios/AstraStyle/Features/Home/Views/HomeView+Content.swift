//
//  HomeView+Content.swift
//  AstraStyle
//

import SwiftUI

extension HomeView {
    @ViewBuilder
    var content: some View {
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
    func emptyStateContent(_ data: HomeBriefData) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            dayLine
                .padding(.horizontal, AstraSpacing.pagePadding)

            WearStreakBanner(viewModel: WearStreakViewModel(streakRepository: container.streakRepository))
                .padding(.horizontal, AstraSpacing.pagePadding)

            weatherAffordance(for: data)
            calendarAffordance
            DailyReminderOptInCard(service: container.reminderService)
                .padding(.horizontal, AstraSpacing.pagePadding)

            HomeEmptyStateView(
                reason: data.emptyReason ?? .noOutfitYet,
                wardrobeGraph: data.wardrobeGraph,
                presentRoles: data.presentRoles
            ) {
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
    func weatherAffordance(for data: HomeBriefData) -> some View {
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

    @ViewBuilder
    var calendarAffordance: some View {
        switch viewModel.calendarAuthorization {
        case .notDetermined:
            CalendarOptInCardView(isRequesting: viewModel.isRequestingCalendarPermission) {
                Task { await viewModel.enableCalendar() }
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
        case .denied:
            CalendarDeniedNoticeView()
                .padding(.horizontal, AstraSpacing.pagePadding)
        case .authorized:
            EmptyView()
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
    func loadedContent(_ data: HomeBriefData) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            todayLine(data)
                .padding(.horizontal, AstraSpacing.pagePadding)

            WearStreakBanner(viewModel: WearStreakViewModel(streakRepository: container.streakRepository))
                .padding(.horizontal, AstraSpacing.pagePadding)

            weatherAffordance(for: data)
            calendarAffordance
            DailyReminderOptInCard(service: container.reminderService)
                .padding(.horizontal, AstraSpacing.pagePadding)

            TodaysLookView(garments: data.lookGarments) { garment in
                router.select(.closet)
                router.push(ClosetRoute.itemDetail(itemID: garment.item.id))
            }
            .padding(.horizontal, AstraSpacing.pagePadding)

            reason(data)
                .padding(.horizontal, AstraSpacing.pagePadding)

            actions(for: data)
                .padding(.horizontal, AstraSpacing.pagePadding)
                .onAppear { syncWearFeedback(for: data) }
                .onChange(of: data.primaryOutfit?.id) { _, _ in syncWearFeedback(for: data) }

            askKyraTodayButton
                .padding(.horizontal, AstraSpacing.pagePadding)

            if !viewModel.weekSlots.isEmpty {
                HomeWeekStripView(
                    slots: viewModel.weekSlots,
                    onSelect: { slot in
                        guard let id = slot.outfit?.id else { return }
                        guard !Calendar.current.isDateInToday(slot.date) else { return }
                        router.push(HomeRoute.outfitDetail(outfitID: id))
                    },
                    onAddOccasion: { router.presentModal(.addOccasion) },
                    onPackTrip: { router.presentModal(.packingTrip) }
                )
                .padding(.horizontal, AstraSpacing.pagePadding)
            }

            monthlyReviewCard
        }
    }

    private var askKyraTodayButton: some View {
        Button {
            router.startAskKyra(initialPrompt: "What should I wear today?", autoSend: true)
        } label: {
            Label("Ask Kyra what to wear today", systemImage: "bubble.left")
                .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
        }
        .buttonStyle(.astraSecondary)
        .accessibilityIdentifier("home.askKyra.today")
    }

    private var monthlyReviewCard: some View {
        Button {
            router.push(.monthlyReview(month: .now))
        } label: {
            AstraCard {
                HStack(spacing: AstraSpacing.md) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .astraIcon(.emphasis)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                    VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                        Text("Your month in style")
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.textPrimary)
                        Text("See what you wore, added, and want to improve.")
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: AstraSpacing.xs)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AstraColor.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AstraSpacing.pagePadding)
        .accessibilityIdentifier("home.monthlyReview")
    }

    /// The date, and nothing else. Shared by the loaded screen and the empty
    /// one so both open the same way — the empty screen has no outfit to
    /// name and no forecast worth putting above "there is nothing to dress
    /// you in yet", but it is still today.
    var dayLine: some View {
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
    func todayLine(_ data: HomeBriefData) -> some View {
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
            if let scheduleHeadline = data.schedule?.headline {
                Text(scheduleHeadline)
                    .astraText(.caption)
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
    func reason(_ data: HomeBriefData) -> some View {
        if let message = data.brief.kyraMessage ?? data.primaryOutfit?.description, !message.isEmpty {
            Text(message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("home.reason")
        }
    }
}
