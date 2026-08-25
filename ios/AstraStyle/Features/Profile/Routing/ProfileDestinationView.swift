//
//  ProfileDestinationView.swift
//  AstraStyle
//
//  Resolves `ProfileRoute` (App/AppRouter.swift) to the screen it stands
//  for, mirroring `Features/Closet/Routing/ClosetDestinationView.swift`.
//  THIS IS THE COMPOSITION ROOT FOR PUSHED PROFILE SCREENS — see that
//  file's header for why view models are built here rather than inside
//  `MainTabView` or inside the pushed view itself.
//
//  Two of `ProfileRoute`'s eight cases are real: `.privacyAndData` and
//  `.accountDeletion`, this pass's own two tickets (P7-PRIVACY-02/03).
//  The remaining six — `.styleDNA`, `.wardrobeScoreDetail`,
//  `.preferences`, `.subscriptionManagement`, `.styleMemories`,
//  `.styleJourney` — belong to other tickets not yet built
//  (`P7-HOME-05`, `P2-ONBOARD`'s editing flow, `P7-SUB`, `P5-KYRA-17`)
//  and get the same honest `FeaturePlaceholderView` treatment
//  `MainTabView` already uses for every other unbuilt tab/route, rather
//  than silently doing nothing or being left to fail an exhaustiveness
//  check the moment a route is added.
//

import SwiftUI

struct ProfileDestinationView: View {
    let route: ProfileRoute
    let container: AppContainer

    var body: some View {
        switch route {
        case .privacyAndData:
            PrivacyAndDataView()

        case .accountDeletion:
            AccountDeletionView(
                viewModel: AccountDeletionViewModel(authRepository: container.authRepository)
            )

        case .styleDNA:
            FeaturePlaceholderView(
                title: String(localized: "Style DNA"),
                message: String(localized: "Your palette, silhouette, and the reasoning behind them."),
                systemImage: "swatchpalette"
            )

        case .appearance:
            AppearanceEditorView(
                viewModel: AppearanceEditorViewModel(
                    profileRepository: container.profileRepository
                )
            )

        case .wardrobeScoreDetail:
            FeaturePlaceholderView(
                title: String(localized: "Wardrobe Score"),
                message: String(localized: "How versatile, current, and well-loved your closet is."),
                systemImage: "chart.bar.fill"
            )

        case .preferences:
            FeaturePlaceholderView(
                title: String(localized: "Preferences"),
                message: String(localized: "Edit the answers behind your Style DNA."),
                systemImage: "slider.horizontal.3"
            )

        case .subscriptionManagement:
            FeaturePlaceholderView(
                title: String(localized: "Subscription"),
                message: String(localized: "Manage your Astra Style plan."),
                systemImage: "creditcard"
            )

        case .styleMemories:
            FeaturePlaceholderView(
                title: String(localized: "Style Memories"),
                message: String(localized: "What Kyra remembers about your style, and a way to clear it."),
                systemImage: "brain"
            )

        case .styleJourney:
            FeaturePlaceholderView(
                title: String(localized: "Style Journey"),
                message: String(localized: "New items, spend, wears, and what to focus on next."),
                systemImage: "chart.line.uptrend.xyaxis"
            )
        }
    }
}
