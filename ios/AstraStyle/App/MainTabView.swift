//
//  MainTabView.swift
//  AstraStyle
//
//  The five-tab shell (spec §4): Home, Closet, Studio, Discover, Profile.
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
            ForEach(AppTab.allCases) { tab in
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

    @ViewBuilder
    private func tabRoot(for tab: AppTab) -> some View {
        switch tab {
        case .home: homeTab
        case .closet: closetTab
        case .studio: studioTab
        case .discover: discoverTab
        case .profile: profileTab
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
                        calendarService: container.calendarService,
                        imageURLResolver: container.closetImageURLResolver
                    ),
                    analyticsClient: container.analyticsClient
                )
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
            FeaturePlaceholderView(
                title: String(localized: "Discover"),
                message: String(localized: "Lookbooks, fit guides, and the reasoning behind them."),
                systemImage: "safari"
            )
            .navigationDestination(for: DiscoverRoute.self) { _ in
                FeaturePlaceholderView(
                    title: String(localized: "Discover"),
                    message: String(localized: "This screen arrives with Discover itself."),
                    systemImage: "safari"
                )
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
            FeaturePlaceholderView(
                title: String(localized: "Profile"),
                message: String(localized: "Your Style DNA, how your wardrobe is progressing, and full control over your data."),
                systemImage: "person.crop.circle"
            )
            .navigationDestination(for: ProfileRoute.self) { _ in
                FeaturePlaceholderView(
                    title: String(localized: "Profile"),
                    message: String(localized: "This screen arrives with Profile itself."),
                    systemImage: "person.crop.circle"
                )
            }
        }
    }

    @ViewBuilder
    private func modalContent(for modal: AppModalRoute) -> some View {
        switch modal {
        case .scanner(let mode):
            ScannerDestinationView(route: mode, container: container)
        case .paywall:
            FeaturePlaceholderView(
                title: String(localized: "Astra Style Premium"),
                message: String(localized: "An unlimited closet, the full Daily Brief, and a verdict before you buy."),
                systemImage: "checkmark.seal"
            )
        case .outfitBuilder(let route):
            OutfitBuilderDestinationView(route: route, container: container)
        case .studioGeneration:
            FeaturePlaceholderView(
                title: String(localized: "Style Studio"),
                message: String(localized: "Kyra is putting this look together on you."),
                systemImage: "person.crop.rectangle"
            )
        case .askKyra:
            FeaturePlaceholderView(
                title: String(localized: "Ask Kyra"),
                message: String(localized: "Ask about an outfit, a purchase, or what to pack."),
                systemImage: "bubble.left.and.text.bubble.right"
            )
        case .addOccasion:
            FeaturePlaceholderView(
                title: String(localized: "Add an Occasion"),
                message: String(localized: "Tell Kyra what's coming up and she'll dress you for it."),
                systemImage: "calendar.badge.plus"
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
