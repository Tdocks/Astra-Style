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
                    imageURLResolver: container.closetImageURLResolver
                )
            )
        case .referenceCapture, .compare, .lookbook:
            FeaturePlaceholderView(
                title: String(localized: "Style Studio"),
                message: String(localized: "Compare and lookbook arrive with the rest of Style Studio."),
                systemImage: "camera.viewfinder"
            )
        }
    }
}
