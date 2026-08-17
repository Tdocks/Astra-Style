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
//  `.memories` and `.productCard` remain honest placeholders: the memory
//  inspector is P5-KYRA-17 and the product decision page is P6-SHOP, and
//  neither is served by a confident screen with nothing behind it.
//

import SwiftUI

struct KyraDestinationView: View {
    let route: KyraRoute
    let container: AppContainer

    var body: some View {
        switch route {
        case .thread(let threadID):
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
                        analyticsClient: container.analyticsClient
                    )
                )
            }
        case .memories:
            FeaturePlaceholderView(
                title: String(localized: "Style Memories"),
                message: String(localized: "Everything Kyra remembers about your taste, yours to review and delete."),
                systemImage: "bookmark"
            )
        case .productCard:
            FeaturePlaceholderView(
                title: String(localized: "Product Decision"),
                message: String(localized: "Whether this is worth buying, and what it would actually add."),
                systemImage: "cart"
            )
        }
    }
}
