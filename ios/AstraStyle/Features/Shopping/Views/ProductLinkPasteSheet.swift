//
//  ProductLinkPasteSheet.swift
//  AstraStyle
//
//  Home's paste-a-link door. Same URL shape check as Kyra's attachment
//  sheet; extract runs here, evaluate runs on the decision page.
//

import SwiftUI

struct ProductLinkPasteSheet: View {
    @State private var viewModel: ProductLinkPasteViewModel
    var onExtracted: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var linkText = ""

    init(shoppingRepository: ShoppingRepository, onExtracted: @escaping (UUID) -> Void) {
        _viewModel = State(wrappedValue: ProductLinkPasteViewModel(shoppingRepository: shoppingRepository))
        self.onExtracted = onExtracted
    }

    private var parsedURL: URL? { ProductLinkURL.parse(linkText) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                Text(String(
                    localized: "Paste a product page. You'll get skip, wait, or buy — and how many outfits it would actually add.",
                    comment: "Home product link sheet explainer"
                ))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)

                TextField(String(localized: "https://…", comment: "Product link placeholder"), text: $linkText)
                    .astraText(.body)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(AstraSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: AstraSpacing.buttonRadius, style: .continuous)
                            .fill(AstraColor.backgroundSecondary)
                    )
                    .accessibilityIdentifier("home.productLink.field")

                if let error = viewModel.submitError {
                    Text(error.message)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                }

                AstraButton(
                    title: String(localized: "Weigh it", comment: "Runs extract then opens the decision page"),
                    isLoading: viewModel.isSubmitting
                ) {
                    Task {
                        guard let id = await viewModel.extract(from: linkText) else { return }
                        onExtracted(id)
                        dismiss()
                    }
                }
                .disabled(parsedURL == nil || viewModel.isSubmitting)
                .accessibilityIdentifier("home.productLink.submit")

                Spacer()
            }
            .padding(AstraSpacing.pagePadding)
            .background(AstraColor.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(String(localized: "Paste a link", comment: "Home product link sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { KyraPickerCloseButton() }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
        .presentationDetents([.medium])
        .onChange(of: viewModel.pendingPaywall) { _, context in
            if let context {
                router.presentModal(.paywall(context: context))
                viewModel.clearPendingPaywall()
            }
        }
    }
}
