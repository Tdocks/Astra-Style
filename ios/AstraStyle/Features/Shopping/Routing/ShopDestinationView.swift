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
        case .productDecision(let candidateID):
            ProductDecisionView(
                viewModel: ProductDecisionViewModel(
                    candidateID: candidateID,
                    shoppingRepository: container.shoppingRepository
                )
            )
        }
    }
}
