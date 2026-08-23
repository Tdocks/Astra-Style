//
//  DiscoverDestinationView.swift
//  AstraStyle
//
//  Lookbook detail reuses outfit detail — these are his outfits, not
//  editorial SKUs. Style guides and brand spotlights stay placeholders.
//

import SwiftUI

struct DiscoverDestinationView: View {
    let route: DiscoverRoute
    let container: AppContainer

    var body: some View {
        switch route {
        case .lookbook(let id):
            OutfitDetailView(
                viewModel: OutfitDetailViewModel(
                    outfitID: id,
                    outfitRepository: container.outfitRepository,
                    closetRepository: container.closetRepository,
                    closetImageURLResolver: container.closetImageURLResolver,
                    profileRepository: container.profileRepository,
                    analyticsClient: container.analyticsClient
                )
            )
        case .productDecision(let candidateID):
            ProductDecisionView(
                viewModel: ProductDecisionViewModel(
                    candidateID: candidateID,
                    shoppingRepository: container.shoppingRepository
                )
            )
        case .styleGuide, .brandSpotlight, .fitGuide:
            FeaturePlaceholderView(
                title: String(localized: "Not a lookbook", comment: "Discover editorial placeholder title"),
                message: String(
                    localized: "Guides and brand pages are not this cut. Discover is the looks you already own.",
                    comment: "Discover editorial placeholder"
                ),
                systemImage: "book"
            )
        }
    }
}
