//
//  OutfitBuilderDestinationView.swift
//  AstraStyle
//
//  Resolves `OutfitBuilderRoute` (App/AppRouter.swift) to the screen it
//  stands for. This is the modal's own composition root — it owns the
//  `NavigationStack` for the outfit builder flow, mirroring
//  `ScannerDestinationView`'s shape for the same reason: `AppModalRoute
//  .outfitBuilder` is presented as a single sheet with no `AppRouter`
//  path behind it, so whatever is pushed inside that flow needs a stack
//  of its own rather than borrowing one of the five tab paths.
//
//  `.visualize` remains a placeholder owned by Style Studio. The shopping
//  destination is shared with the Shop tab and uses the same owner-scoped
//  saved-outfit read model.
//

import SwiftUI

struct OutfitBuilderDestinationView: View {
    let route: OutfitBuilderRoute
    let container: AppContainer

    @State private var path: [OutfitBuilderRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            destination(for: route)
                .navigationDestination(for: OutfitBuilderRoute.self) { nested in
                    destination(for: nested)
                }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
    }

    @ViewBuilder
    private func destination(for route: OutfitBuilderRoute) -> some View {
        switch route {
        case .builder(let startingOutfitID):
            OutfitBuilderView(
                viewModel: OutfitBuilderViewModel(
                    outfitRepository: container.outfitRepository,
                    closetRepository: container.closetRepository,
                    analyticsClient: container.analyticsClient,
                    startingOutfitID: startingOutfitID,
                    generationContextProvider: CurrentOutfitContextProvider(
                        profileRepository: container.profileRepository,
                        weatherService: container.weatherService,
                        calendarService: container.calendarService
                    )
                )
            )

        case .visualize:
            FeaturePlaceholderView(
                title: String(localized: "Visualize"),
                message: String(localized: "See this look on yourself before you wear it — this screen arrives with Style Studio."),
                systemImage: "person.crop.rectangle"
            )

        case .shopMissingItems(let outfitID):
            ShopTheLookView(
                viewModel: ShopTheLookViewModel(
                    outfitID: outfitID,
                    outfitRepository: container.outfitRepository,
                    closetRepository: container.closetRepository,
                    profileRepository: container.profileRepository,
                    shoppingRepository: container.shoppingRepository,
                    imageURLResolver: container.closetImageURLResolver,
                    currentOwnerID: { await container.sessionStore.currentUserID() }
                )
            )
        }
    }
}
