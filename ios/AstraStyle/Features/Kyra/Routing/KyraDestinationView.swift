//
//  KyraDestinationView.swift
//  AstraStyle
//
//  Resolves `KyraRoute` (App/AppRouter.swift) to a screen, same division
//  of labor as `ClosetDestinationView`: the route enum stays at the App
//  layer, which view a case maps to is this module's concern. This is the
//  composition root for the Ask Kyra modal, so the view model is built
//  here where the full dependency graph is known.
//
//  `.memories` uses the shared privacy screen. `.productCard` remains an
//  honest placeholder until its route carries the product decision model.
//

import SwiftUI

struct KyraDestinationView: View {
    let route: KyraRoute
    let container: AppContainer

    var body: some View {
        switch route {
        case .thread(let threadID, let initialPrompt, let outfitID, let autoSend):
            NavigationStack {
                KyraConversationView(
                    viewModel: KyraConversationViewModel(
                        threadID: threadID,
                        kyraRepository: container.kyraRepository,
                        outfitRepository: container.outfitRepository,
                        closetRepository: container.closetRepository,
                        shoppingRepository: container.shoppingRepository,
                        imageURLResolver: container.closetImageURLResolver,
                        networkMonitor: container.networkMonitor,
                        analyticsClient: container.analyticsClient,
                        initialPrompt: initialPrompt,
                        contextualOutfitID: outfitID,
                        autoSendInitialPrompt: autoSend
                    )
                )
            }
        case .memories:
            NavigationStack {
                StyleMemoriesView(
                    viewModel: StyleMemoriesViewModel(
                        kyraRepository: container.kyraRepository
                    )
                )
            }
        case .productCard:
            FeaturePlaceholderView(
                title: String(localized: "Product Decision"),
                message: String(localized: "Whether this is worth buying, and what it would actually add."),
                systemImage: "cart"
            )
        }
    }
}
