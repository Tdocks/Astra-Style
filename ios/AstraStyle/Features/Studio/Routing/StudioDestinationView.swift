//
//  StudioDestinationView.swift
//  AstraStyle
//
//  Pushed Studio routes. Generate stays a modal from the tab root.
//

import SwiftUI

struct StudioDestinationView: View {
    let route: StudioRoute
    let container: AppContainer

    var body: some View {
        switch route {
        case .generation(let generationID):
            StudioGenerationDetailView(
                viewModel: StudioGenerationDetailViewModel(
                    generationID: generationID,
                    studioRepository: container.studioRepository,
                    imageURLResolver: container.closetImageURLResolver,
                    exporter: container.studioEstimateExporter
                )
            )
        case .compare(let generationIDs):
            StudioComparisonView(viewModel: StudioComparisonViewModel(
                generationIDs: generationIDs,
                repository: container.studioRepository,
                resolver: container.closetImageURLResolver
            ))
        case .lookbook:
            StudioLookbooksView(viewModel: StudioLookbooksViewModel(repository: container.studioRepository))
        case .savedLooks(let lookbookID, let name):
            StudioSavedLooksView(viewModel: StudioSavedLooksViewModel(
                lookbookID: lookbookID, repository: container.studioRepository, resolver: container.closetImageURLResolver
            ), name: name)
        case .referenceCapture:
            FeaturePlaceholderView(
                title: String(localized: "Style Studio"),
                message: String(localized: "Open See a look on you to choose a reference photo."),
                systemImage: "camera.viewfinder"
            )
        }
    }
}
