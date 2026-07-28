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
                    message: String(localized: "Your wardrobe grid, filters, and item detail land here under the P3-CLOSET tickets."),
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
                    message: String(localized: "Visual try-on and outfit visualization land here under the P6-STUDIO tickets."),
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
                    message: String(localized: "Kyra-curated lookbooks and style education land here under the P6-SHOP tickets."),
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
                FeaturePlaceholderView(
                    title: String(localized: "Profile"),
                    message: String(localized: "Style DNA, Wardrobe Score, and account controls land here under the P7-SUB tickets."),
                    systemImage: "person.crop.circle"
                )
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
                message: String(localized: "Camera capture and analysis review land here under the P3-SCAN tickets."),
                systemImage: "viewfinder"
            )
        case .paywall:
            FeaturePlaceholderView(
                title: String(localized: "Astra Style Premium"),
                message: String(localized: "The paywall lands here under the P7-SUB tickets."),
                systemImage: "sparkles"
            )
        case .outfitBuilder:
            FeaturePlaceholderView(
                title: String(localized: "Outfit Builder"),
                message: String(localized: "The flat-lay outfit canvas lands here under the P4-OUTFIT tickets."),
                systemImage: "tshirt"
            )
        case .studioGeneration:
            FeaturePlaceholderView(
                title: String(localized: "Style Studio"),
                message: String(localized: "Visualization generation lands here under the P6-STUDIO tickets."),
                systemImage: "wand.and.stars"
            )
        case .askKyra:
            FeaturePlaceholderView(
                title: String(localized: "Ask Kyra"),
                message: String(localized: "Kyra's conversation UI lands here under the P5-KYRA tickets."),
                systemImage: "sparkles"
            )
        case .addOccasion:
            FeaturePlaceholderView(
                title: String(localized: "Add an Occasion"),
                message: String(localized: "Manual occasion entry lands here under the P4-OUTFIT tickets."),
                systemImage: "calendar.badge.plus"
            )
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
