//
//  ClosetDestinationView.swift
//  AstraStyle
//
//  Resolves `ClosetRoute` (App/AppRouter.swift) to the screen it stands
//  for, mirroring `Features/Home/Routing/HomeDestinationView.swift`.
//  `ClosetRoute` stays defined at the App layer — `AppRouter` owns every
//  tab's path type so tab state can be restored and inspected in one
//  place — but which view each case maps to is this module's business.
//
//  THIS IS THE COMPOSITION ROOT FOR PUSHED CLOSET SCREENS.
//  View models are not built inside views; they are built where the graph
//  is known. For the tab's ROOT that is `MainTabView`. For everything
//  pushed onto the tab's stack it is here, which is why this type takes
//  `AppContainer` rather than a bag of already-built view models: a
//  `navigationDestination` closure is handed a route value and nothing
//  else, so the alternative would be `MainTabView` pre-building a view
//  model per route case for screens the user may never open.
//
//  Every destination below is real or honestly labelled. Three cases point
//  at screens owned by other tickets and say so in the product's voice
//  rather than naming a ticket: nothing in this module links to any of the
//  three, so none of them is reachable by tapping something that looked
//  like it would work.
//

import SwiftUI

struct ClosetDestinationView: View {
    let route: ClosetRoute
    let container: AppContainer

    var body: some View {
        switch route {
        case .category(let category):
            ClosetCategoryView(
                category: category,
                viewModel: ClosetViewModel(
                    closetRepository: container.closetRepository,
                    imageURLResolver: container.closetImageURLResolver
                )
            )

        case .itemDetail(let itemID):
            ClosetItemDetailView(
                viewModel: ClosetItemDetailViewModel(
                    itemID: itemID,
                    closetRepository: container.closetRepository,
                    imageURLResolver: container.closetImageURLResolver
                )
            )

        case .editItem:
            // `ClosetItemFormViewModel.editing(item:closetRepository:)`
            // takes a loaded `ClosetItem`, and this route carries only an
            // id — so satisfying it means fetching first, which a view may
            // not do. The item-detail screen already holds the loaded item
            // and is where Edit is reached from, so the form belongs to
            // that screen's own presentation rather than to a route that
            // would have to re-fetch what the caller already had. Nothing
            // pushes this case today; it is answered honestly instead of
            // being wired to a screen that would show the wrong thing.
            FeaturePlaceholderView(
                title: String(localized: "Edit Piece"),
                message: String(localized: "Open a piece from your closet to change its details."),
                systemImage: "square.and.pencil"
            )

        case .scanner:
            // Capture is a modal flow (spec §4), presented through
            // `AppRouter.startScan()` — the scan button in the closet
            // header does exactly that. This pushed case exists on the
            // enum but is not how the scanner is entered.
            FeaturePlaceholderView(
                title: String(localized: "Scan an Item"),
                message: String(localized: "Point your camera at a garment and Kyra will catalog it for you."),
                systemImage: "viewfinder"
            )

        case .colorSpectrum:
            FeaturePlaceholderView(
                title: String(localized: "Colour Spectrum"),
                message: String(localized: "Your whole wardrobe arranged by colour, so you can see what you actually reach for."),
                systemImage: "circle.hexagongrid"
            )

        case .filters:
            FeaturePlaceholderView(
                title: String(localized: "Filters"),
                message: String(localized: "Narrow your closet by category, colour, season, brand, condition, fit, availability, and how often you wear it."),
                systemImage: "line.3.horizontal.decrease"
            )
        }
    }
}
