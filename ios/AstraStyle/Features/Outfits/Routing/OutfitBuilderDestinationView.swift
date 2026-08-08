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
//  TWO OF THREE CASES ARE HONEST PLACEHOLDERS. `.visualize` (Style
//  Studio's "see it on yourself", P4-STUDIO/P5) and `.shopMissingItems`
//  (Shopping's product search for a gap in the outfit, P6-SHOP) both
//  belong to modules this ticket does not build. Nothing inside this
//  flow pushes either case today — there is no "visualize" or "shop the
//  rest" button on `OutfitBuilderView` — so neither is reachable by a
//  control that looks like it would work; they exist on the enum for the
//  tickets that will make them real.
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
                    startingOutfitID: startingOutfitID
                )
            )

        case .visualize:
            FeaturePlaceholderView(
                title: String(localized: "Visualize"),
                message: String(localized: "See this look on yourself before you wear it — this screen arrives with Style Studio."),
                systemImage: "person.crop.rectangle"
            )

        case .shopMissingItems:
            FeaturePlaceholderView(
                title: String(localized: "Shop the Rest"),
                message: String(localized: "Kyra will find pieces to fill what this outfit is missing — this screen arrives with Shopping."),
                systemImage: "bag"
            )
        }
    }
}
