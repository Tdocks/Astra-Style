//
//  HomeDestinationView.swift
//  AstraStyle
//
//  Resolves `HomeRoute` (App/AppRouter.swift) to the screen it represents.
//  `HomeRoute` itself stays defined at the App layer (spec §8 "typed route
//  enums per tab" — `AppRouter` owns every tab's path type so tab state
//  can be restored/inspected in one place), but which *view* each case
//  maps to is this module's concern, not the App layer's.
//
//  Every destination here not yet listed under "What is built" is a
//  placeholder pending its owning feature's tickets (P5-KYRA for the
//  thread view, P6-SHOP for the product decision page) — Home only
//  originates the navigation, it doesn't own the destination screens.
//
//  What is built: `.outfitDetail` — `Features/Outfits/Views
//  /OutfitDetailView.swift` (spec §6.12, P4-OUTFIT-11). Takes `container`
//  for the same reason `ClosetDestinationView` does: this is the
//  composition root for screens PUSHED onto the Home tab's stack, so the
//  view model is built here, where the full dependency graph is known,
//  rather than inside the view itself.
//

import SwiftUI

struct HomeDestinationView: View {
    let route: HomeRoute
    let container: AppContainer

    var body: some View {
        switch route {
        case .outfitDetail(let outfitID):
            OutfitDetailView(
                viewModel: OutfitDetailViewModel(
                    outfitID: outfitID,
                    outfitRepository: container.outfitRepository,
                    closetRepository: container.closetRepository,
                    closetImageURLResolver: container.closetImageURLResolver,
                    profileRepository: container.profileRepository,
                    analyticsClient: container.analyticsClient
                )
            )
        case .alternativeLooks:
            FeaturePlaceholderView(
                title: String(localized: "Alternative Looks"),
                message: String(localized: "Other ways Kyra would put today together."),
                systemImage: "square.stack"
            )
        case .kyraThread:
            FeaturePlaceholderView(
                title: String(localized: "Ask Kyra"),
                message: String(localized: "Ask about an outfit, a purchase, or what to pack."),
                systemImage: "bubble.left.and.text.bubble.right"
            )
        case .occasionDetail:
            FeaturePlaceholderView(
                title: String(localized: "Occasion"),
                message: String(localized: "What's coming up, and what Kyra suggests wearing to it."),
                systemImage: "calendar"
            )
        case .monthlyReview:
            FeaturePlaceholderView(
                title: String(localized: "Monthly Review"),
                message: String(localized: "What you wore, what you bought, and what's worth changing."),
                systemImage: "chart.line.uptrend.xyaxis"
            )
        case .productDecision:
            FeaturePlaceholderView(
                title: String(localized: "Product Decision"),
                message: String(localized: "Whether this is worth buying, and what it would actually add."),
                systemImage: "cart"
            )
        }
    }
}
