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

import SwiftUI

struct ProfileDestinationView: View {
    let route: ProfileRoute
    let container: AppContainer

    var body: some View {
        switch route {
        case .privacyAndData:
            PrivacyAndDataView(
                exportViewModel: PersonalDataExportViewModel(
                    profileRepository: container.profileRepository
                )
            )

        case .accountDeletion:
            AccountDeletionView(
                viewModel: AccountDeletionViewModel(authRepository: container.authRepository)
            )

        case .styleDNA:
            StyleDNAView(
                viewModel: StyleDNAViewModel(profileRepository: container.profileRepository)
            )

        case .appearance:
            AppearanceEditorView(
                viewModel: AppearanceEditorViewModel(
                    profileRepository: container.profileRepository
                )
            )

        case .savedItems:
            SavedItemsView(
                viewModel: SavedItemsViewModel(
                    shoppingRepository: container.shoppingRepository
                )
            )

        case .productDecision(let candidateID):
            ProductDecisionView(
                viewModel: ProductDecisionViewModel(
                    candidateID: candidateID,
                    shoppingRepository: container.shoppingRepository
                )
            )

        case .wardrobeScoreDetail:
            FeaturePlaceholderView(
                title: String(localized: "Wardrobe Score"),
                message: String(localized: "How versatile, current, and well-loved your closet is."),
                systemImage: "chart.bar.fill"
            )

        case .preferences:
            PreferencesEditorView(
                viewModel: PreferencesEditorViewModel(
                    profileRepository: container.profileRepository
                )
            )

        case .subscriptionManagement:
            FeaturePlaceholderView(
                title: String(localized: "Subscription"),
                message: String(localized: "Manage your Astra Style plan."),
                systemImage: "creditcard"
            )

        case .styleMemories:
            StyleMemoriesView(
                viewModel: StyleMemoriesViewModel(
                    kyraRepository: container.kyraRepository
                )
            )

        case .referencePhotos:
            ReferencePhotosView(
                viewModel: ReferencePhotosViewModel(
                    profileRepository: container.profileRepository,
                    studioRepository: container.studioRepository,
                    imageURLResolver: container.closetImageURLResolver
                )
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
