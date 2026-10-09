//
//  ShopDestinationView.swift
//  AstraStyle
//
//  Shop tab stack. Product decisions reuse the paste-evaluate page.
//

import SwiftUI

struct ShopDestinationView: View {
    let route: ShopRoute
    let container: AppContainer

    var body: some View {
        switch route {
        case .shopTheLook(let outfitID):
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
        case .productDecision(let candidateID):
            ProductDecisionView(
                viewModel: ProductDecisionViewModel(
                    candidateID: candidateID,
                    shoppingRepository: container.shoppingRepository
                )
            )
        case .historicalDecision(let candidateID):
            ProductDecisionView(
                viewModel: ProductDecisionViewModel(
                    candidateID: candidateID,
                    shoppingRepository: container.shoppingRepository,
                    startsInHistoricalMode: true
                )
            )
        }
    }
}
