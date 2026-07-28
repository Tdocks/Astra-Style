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
//  Every destination here is a placeholder pending its owning feature's
//  tickets (P4-OUTFIT for outfit/alternatives, P5-KYRA for the thread
//  view, P6-SHOP for the product decision page) — Home only originates
//  the navigation, it doesn't own the destination screens.
//

import SwiftUI

struct HomeDestinationView: View {
    let route: HomeRoute

    var body: some View {
        switch route {
        case .outfitDetail:
            FeaturePlaceholderView(
                title: String(localized: "Outfit Detail"),
                message: String(localized: "Full outfit detail lands here under the P4-OUTFIT tickets."),
                systemImage: "tshirt"
            )
        case .alternativeLooks:
            FeaturePlaceholderView(
                title: String(localized: "Alternative Looks"),
                message: String(localized: "The full alternatives list lands here under the P4-OUTFIT tickets."),
                systemImage: "square.stack"
            )
        case .kyraThread:
            FeaturePlaceholderView(
                title: String(localized: "Ask Kyra"),
                message: String(localized: "Kyra's conversation UI lands here under the P5-KYRA tickets."),
                systemImage: "sparkles"
            )
        case .occasionDetail:
            FeaturePlaceholderView(
                title: String(localized: "Occasion"),
                message: String(localized: "Occasion detail lands here under the P4-OUTFIT tickets."),
                systemImage: "calendar"
            )
        case .monthlyReview:
            FeaturePlaceholderView(
                title: String(localized: "Monthly Review"),
                message: String(localized: "Kyra's monthly review lands here under the P7-SUB tickets."),
                systemImage: "chart.line.uptrend.xyaxis"
            )
        case .productDecision:
            FeaturePlaceholderView(
                title: String(localized: "Product Decision"),
                message: String(localized: "The Buy / Consider / Wait / Skip verdict page lands here under the P6-SHOP tickets."),
                systemImage: "cart"
            )
        }
    }
}
