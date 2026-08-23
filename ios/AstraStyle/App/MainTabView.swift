//
//  MainTabView.swift
//  AstraStyle
//
//  The five-tab shell (spec §4): Home, Closet, Studio, Discover, Profile.
//  Dogfood chrome is Home, Closet, Discover, Profile. Studio stays off
//  the bar; Visualize / See this on you is the generate door (Wave E).
//  Each tab owns an independent `NavigationStack` bound to its own path in
//  `AppRouter`, so tab state survives switching tabs. SF Symbols per tab are
//  defined on `AppTab` in AppRouter.swift; gold indicates the active tab per
//  spec §3 "Iconography", handled by DesignSystem's tab bar styling.
//

import SwiftUI

struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            ForEach(AppTab.chromeTabs) { tab in
                tabRoot(for: tab)
                    .tabItem {
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(systemName: tab.symbolName)
                        }
                    }
                    .accessibilityLabel(Text(tab.accessibilityLabel))
                    .tag(tab)
            }
        }
        .tint(AstraColor.accentChampagne)
        .sheet(item: $router.presentedModal) { modal in
            modalContent(for: modal)
        }
    }

    /// Every tab root carries the floating Ask Kyra orb — spec §4 lists
    /// "Ask Kyra" as a GLOBAL action, and an entry point that exists on
    /// some tabs is a navigation model the user has to memorize. It is
    /// overlaid here, on the tab's content INSIDE the tab bar's safe area,
    /// rather than on the `TabView` itself: the TabView's own frame
    /// includes the tab bar, so an overlay there needs a guessed bottom
    /// padding to clear it, and the guess breaks the day the bar's height
    /// changes. Inside the content, the safe area does the arithmetic.
    @ViewBuilder
    private func tabRoot(for tab: AppTab) -> some View {
        Group {
            switch tab {
            case .home: homeTab
            case .closet: closetTab
            case .studio: studioTab
            case .discover: discoverTab
            case .profile: profileTab
            }
        }
        .overlay(alignment: .bottomTrailing) {
            KyraAskButton {
                router.startAskKyra()
            }
            .padding(.trailing, AstraSpacing.pagePadding)
            .padding(.bottom, AstraSpacing.md)
        }
    }

    /// The Home tab's root, in its own `NavigationStack` bound to
    /// `AppRouter.homePath` so the tab keeps its stack across tab switches.
    @ViewBuilder
    private var homeTab: some View {
        // `@Bindable` must be re-established in each of these: the one in `body`
        // is a local binding and does not carry into other members, so `$router`
        // would otherwise be out of scope. @Observable types need this to
        // project bindings at all.
        @Bindable var router = router
        NavigationStack(path: $router.homePath) {
            HomeView(
                viewModel: HomeViewModel(
                    provider: DefaultHomeBriefProvider(
                        outfitRepository: container.outfitRepository,
                        profileRepository: container.profileRepository,
                        closetRepository: container.closetRepository,
                        weatherService: container.weatherService,
                        imageURLResolver: container.closetImageURLResolver
                    ),
                    analyticsClient: container.analyticsClient,
                    outfitRepository: container.outfitRepository
                ),
                shoppingRepository: container.shoppingRepository
            )
            .navigationDestination(for: HomeRoute.self) { route in
                HomeDestinationView(route: route, container: container)
            }
        }
    }

    /// The Closet tab's root, in its own `NavigationStack` bound to
    /// `AppRouter.closetPath` so the tab keeps its stack across tab switches.
    @ViewBuilder
    private var closetTab: some View {
        // `@Bindable` must be re-established in each of these: the one in `body`
        // is a local binding and does not carry into other members, so `$router`
        // would otherwise be out of scope. @Observable types need this to
        // project bindings at all.
        @Bindable var router = router
        NavigationStack(path: $router.closetPath) {
            ClosetView(
                viewModel: ClosetViewModel(
                    closetRepository: container.closetRepository,
                    imageURLResolver: container.closetImageURLResolver,
                    // Without this, `makeAddItemViewModel` builds a form that
                    // fails every submit as `.auth` — the sheet stays up and
                    // P3-TEST-02's post-save "Tops" tap hits the form's
                    // category chip instead of the closet tile.
                    currentUserID: { await container.sessionStore.currentUserID() },
                    analyticsClient: container.analyticsClient
                ),
                looksViewModel: ClosetLooksViewModel(
                    outfitRepository: container.outfitRepository,
                    closetRepository: container.closetRepository,
                    profileRepository: container.profileRepository,
                    imageURLResolver: container.closetImageURLResolver
                )
            )
            .navigationDestination(for: ClosetRoute.self) { route in
                ClosetDestinationView(route: route, container: container)
            }
        }
    }

    /// The Style Studio tab's root, in its own `NavigationStack` bound to
    /// `AppRouter.studioPath` so the tab keeps its stack across tab switches.
    @ViewBuilder
    private var studioTab: some View {
        // `@Bindable` must be re-established in each of these: the one in `body`
        // is a local binding and does not carry into other members, so `$router`
        // would otherwise be out of scope. @Observable types need this to
        // project bindings at all.
        @Bindable var router = router
        NavigationStack(path: $router.studioPath) {
            FeaturePlaceholderView(
                title: String(localized: "Style Studio"),
                message: String(localized: "See a look on yourself before you wear it — or before you buy it."),
                systemImage: "camera.viewfinder"
            )
            .navigationDestination(for: StudioRoute.self) { _ in
                FeaturePlaceholderView(
                    title: String(localized: "Style Studio"),
                    message: String(localized: "This screen arrives with Style Studio itself."),
                    systemImage: "camera.viewfinder"
                )
            }
        }
    }

    /// The Discover tab's root, in its own `NavigationStack` bound to
    /// `AppRouter.discoverPath` so the tab keeps its stack across tab switches.
    @ViewBuilder
    private var discoverTab: some View {
        // `@Bindable` must be re-established in each of these: the one in `body`
        // is a local binding and does not carry into other members, so `$router`
        // would otherwise be out of scope. @Observable types need this to
        // project bindings at all.
        @Bindable var router = router
        NavigationStack(path: $router.discoverPath) {
            DiscoverView(
                viewModel: DiscoverViewModel(
                    outfitRepository: container.outfitRepository,
                    shoppingRepository: container.shoppingRepository
                )
            )
            .navigationDestination(for: DiscoverRoute.self) { route in
                DiscoverDestinationView(route: route, container: container)
            }
        }
    }

    /// The Profile tab's root, in its own `NavigationStack` bound to
    /// `AppRouter.profilePath` so the tab keeps its stack across tab switches.
    @ViewBuilder
    private var profileTab: some View {
        // `@Bindable` must be re-established in each of these: the one in `body`
        // is a local binding and does not carry into other members, so `$router`
        // would otherwise be out of scope. @Observable types need this to
        // project bindings at all.
        @Bindable var router = router
        NavigationStack(path: $router.profilePath) {
            // Real now, where it used to be a placeholder over a placeholder.
            // The tab is deliberately thin — P7-HOME-05 owns the full profile
            // and stats screen — but the two things behind it are the App
            // Store's own gate (Guideline 5.1.1(v)), so they ship first and
            // the rest of the tab grows around them.
            ProfileView()
                .navigationDestination(for: ProfileRoute.self) { route in
                    ProfileDestinationView(route: route, container: container)
                }
        }
    }

    @ViewBuilder
    private func modalContent(for modal: AppModalRoute) -> some View {
        switch modal {
        case .scanner(let mode):
            ScannerDestinationView(route: mode, container: container)
        case .paywall(let context):
            PaywallView(
                viewModel: PaywallViewModel(
                    context: context,
                    purchasing: LiveStoreKitPurchasing(),
                    subscriptionRepository: container.subscriptionRepository
                )
            )
        case .outfitBuilder(let route):
            OutfitBuilderDestinationView(route: route, container: container)
        case .studioGeneration(let outfitID):
            StudioGenerationView(
                viewModel: StudioGenerationViewModel(
                    outfitID: outfitID,
                    studioRepository: container.studioRepository,
                    profileRepository: container.profileRepository,
                    imageURLResolver: container.closetImageURLResolver
                )
            )
        case .askKyra(let route):
            KyraDestinationView(route: route, container: container)
        case .addOccasion:
            AddOccasionView(
                viewModel: AddOccasionViewModel(
                    outfitRepository: container.outfitRepository,
                    currentUserID: { await container.sessionStore.currentUserID() }
                )
            )
        case .packingTrip:
            PackingTripView(
                viewModel: PackingTripViewModel(outfitRepository: container.outfitRepository)
            )
        }
    }
}

/// Shared, honest "not yet built" screen used by every feature tab until
/// its module lands. Deliberately not a dead end: it states what will be
/// here and why, and remains fully accessible.
///
/// **The "Not built yet" line is part of the type, not of each caller's
/// string.** Every one of these screens previously opened with a sentence
/// of product copy — "See a look on yourself before you wear it" — and
/// nothing else. Read on a device rather than in a diff, that is
/// indistinguishable from a feature that is present and broken: the tester
/// taps the tab, sees a confident claim, and waits for something to load.
/// Putting the disclosure in the shared view means no future placeholder
/// can be added without it, which is the only version of this that stays
/// true.
struct FeaturePlaceholderView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ZStack {
            AstraColor.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: AstraSpacing.md) {
                Image(systemName: systemImage)
                    .astraIcon(.display)
                    .foregroundStyle(AstraColor.textMuted)
                    .accessibilityHidden(true)
                Text(title)
                    .astraText(.title2)
                    .foregroundStyle(AstraColor.textPrimary)
                Text("Not built yet")
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                Text(message)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AstraSpacing.pagePadding)
            }
            .accessibilityElement(children: .combine)
        }
        .navigationTitle(title)
    }
}
