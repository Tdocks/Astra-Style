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
        // `@Bindable` must be re-established here: the one in `body` is a local
        // binding and does not carry into other methods, so `$router` was out
        // of scope. @Observable types need this to project bindings at all.
        @Bindable var router = router

        switch tab {
        case .home:
            NavigationStack(path: $router.homePath) {
                HomeView(
                    viewModel: HomeViewModel(
                        provider: DefaultHomeBriefProvider(
                            outfitRepository: container.outfitRepository,
                            profileRepository: container.profileRepository,
                            closetRepository: container.closetRepository,
                            weatherService: container.weatherService,
                            calendarService: container.calendarService
                        ),
                        analyticsClient: container.analyticsClient
                    )
                )
                .navigationDestination(for: HomeRoute.self) { route in
                    HomeDestinationView(route: route)
                }
            }

        case .closet:
            NavigationStack(path: $router.closetPath) {
                FeaturePlaceholderView(
                    title: String(localized: "Closet"),
                    message: String(localized: "Everything you own, in one place. Scan your first few pieces and Kyra can start building real outfits."),
                    systemImage: "square.grid.2x2"
                )
                .navigationDestination(for: ClosetRoute.self) { _ in
                    FeaturePlaceholderView(
                        title: String(localized: "Closet"),
                        message: String(localized: "Detail screen placeholder — see Features/Closet/README.md."),
                        systemImage: "square.grid.2x2"
                    )
                }
            }

        case .studio:
            NavigationStack(path: $router.studioPath) {
                FeaturePlaceholderView(
                    title: String(localized: "Style Studio"),
                    message: String(localized: "See a look on yourself before you wear it — or before you buy it."),
                    systemImage: "camera.viewfinder"
                )
                .navigationDestination(for: StudioRoute.self) { _ in
                    FeaturePlaceholderView(
                        title: String(localized: "Style Studio"),
                        message: String(localized: "Detail screen placeholder — see Features/Studio/README.md."),
                        systemImage: "camera.viewfinder"
                    )
                }
            }

        case .discover:
            NavigationStack(path: $router.discoverPath) {
                FeaturePlaceholderView(
                    title: String(localized: "Discover"),
                    message: String(localized: "Lookbooks, fit guides, and the reasoning behind them."),
                    systemImage: "safari"
                )
                .navigationDestination(for: DiscoverRoute.self) { _ in
                    FeaturePlaceholderView(
                        title: String(localized: "Discover"),
                        message: String(localized: "Detail screen placeholder — see Features/Discover/README.md."),
                        systemImage: "safari"
                    )
                }
            }

        case .profile:
            NavigationStack(path: $router.profilePath) {
                Group {
                    // A guest has no real Profile content to browse yet
                    // (Style DNA, wardrobe progress — Phase 2+), but does
                    // need a real, reachable "create an account" surface
                    // (spec §6.2; ADR 0011) — shown here instead of the
                    // generic placeholder below.
                    if container.sessionStore.isGuest {
                        GuestProfileView()
                    } else {
                        FeaturePlaceholderView(
                            title: String(localized: "Profile"),
                            message: String(localized: "Your Style DNA, how your wardrobe is progressing, and full control over your data."),
                            systemImage: "person.crop.circle"
                        )
                    }
                }
                .navigationDestination(for: ProfileRoute.self) { _ in
                    FeaturePlaceholderView(
                        title: String(localized: "Profile"),
                        message: String(localized: "Detail screen placeholder — see Features/Profile/README.md."),
                        systemImage: "person.crop.circle"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func modalContent(for modal: AppModalRoute) -> some View {
        switch modal {
        case .scanner:
            FeaturePlaceholderView(
                title: String(localized: "Scan an Item"),
                message: String(localized: "Point your camera at a garment and Kyra will catalog it for you."),
                systemImage: "viewfinder"
            )
        case .paywall:
            FeaturePlaceholderView(
                title: String(localized: "Astra Style Premium"),
                message: String(localized: "An unlimited closet, the full Daily Brief, and a verdict before you buy."),
                systemImage: "checkmark.seal"
            )
        case .outfitBuilder:
            FeaturePlaceholderView(
                title: String(localized: "Outfit Builder"),
                message: String(localized: "Build a look piece by piece, with Kyra checking your work as you go."),
                systemImage: "tshirt"
            )
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
        case .createAccount(let reason):
            CreateAccountSheet(reason: reason)
        }
    }
}

/// Shared, honest "not yet built" screen used by every feature tab until
/// its module lands. Deliberately not a dead end: it states what will be
/// here and why, and remains fully accessible.
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
                    .foregroundStyle(AstraColor.accentChampagne)
                    .accessibilityHidden(true)
                Text(title)
                    .astraText(.title2)
                    .foregroundStyle(AstraColor.textPrimary)
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
