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
import StoreKit

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
            WardrobeScoreDetailView(
                viewModel: WardrobeScoreViewModel(closetRepository: container.closetRepository)
            )

        case .preferences:
            PreferencesEditorView(
                viewModel: PreferencesEditorViewModel(
                    profileRepository: container.profileRepository
                )
            )

        case .notificationSettings:
            NotificationSettingsView(service: container.reminderService)

        case .subscriptionManagement:
            SubscriptionManagementView(
                viewModel: SubscriptionManagementViewModel(
                    purchasing: LiveStoreKitPurchasing(appAccountTokenProvider: {
                        await container.sessionStore.currentUserID()
                    }),
                    subscriptionRepository: container.subscriptionRepository
                )
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
            StyleJourneyView(
                viewModel: ProfileDashboardViewModel(
                    closetRepository: container.closetRepository,
                    outfitRepository: container.outfitRepository
                )
            )
        }
    }
}
