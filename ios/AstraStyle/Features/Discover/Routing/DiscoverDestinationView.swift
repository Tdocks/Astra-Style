//
//  DiscoverDestinationView.swift
//  AstraStyle
//
//  Lookbooks reuse outfit detail. Editorial guides are local config content;
//  no brand spotlights are published without an authorized catalog source.
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
        case .publicLook(let id):
            PublicLookDetailView(
                viewModel: PublicLookDetailViewModel(
                    outfitID: id,
                    outfitRepository: container.outfitRepository,
                    imageURLResolver: container.closetImageURLResolver
                )
            )
        case .productDecision(let candidateID):
            ProductDecisionView(
                viewModel: ProductDecisionViewModel(
                    candidateID: candidateID,
                    shoppingRepository: container.shoppingRepository
                )
            )
        case .styleGuide(let slug), .fitGuide(let slug):
            guideDetail(slug: slug)
        case .brandSpotlight(let brand):
            guideDetail(slug: brand)
        }
    }

    @ViewBuilder
    private func guideDetail(slug: String) -> some View {
        DiscoverGuideDetailView(
            viewModel: DiscoverGuideDetailViewModel(
                slug: slug,
                repository: BundleDiscoverEditorialRepository()
            )
        )
    }
}
