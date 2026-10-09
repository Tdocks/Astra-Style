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
            let cachePurger = container.profileRepository as? any ProfileCachePurging
            let kyraCachePurger = container.kyraRepository as? any KyraHistoryCachePurging
            let shoppingCachePurger = container.shoppingRepository as? any ShoppingEvaluationCachePurging
            let closetCachePurger = container.closetRepository as? any ClosetItemCachePurging
            AccountDeletionView(
                viewModel: AccountDeletionViewModel(
                    authRepository: container.authRepository,
                    currentUserID: { await container.sessionStore.currentUserID() },
                    purgeLocalProfileCache: { ownerID in
                        try await FileScannerBatchPendingStore.live.remove(ownerID: ownerID)
                        try await cachePurger?.purgeLocalProfileCache(ownerID: ownerID)
                        try await kyraCachePurger?.purgeCachedKyraHistory(ownerID: ownerID)
                        try await shoppingCachePurger?.purgeCachedShoppingEvaluations(ownerID: ownerID)
                        try await closetCachePurger?.purgeCachedClosetItems(ownerID: ownerID)
                    }
                )
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

        case .tasteRefinement:
            StyleQuizRefinementView(
                viewModel: StyleQuizRefinementViewModel(
                    profileRepository: container.profileRepository,
                    currentOwnerID: { await container.sessionStore.currentUserID() }
                )
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
