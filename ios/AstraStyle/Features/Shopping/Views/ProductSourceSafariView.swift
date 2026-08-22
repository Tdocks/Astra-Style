//
//  ProductSourceSafariView.swift
//  AstraStyle
//
//  Reopens the URL he pasted after a buy/consider verdict. Not a catalog
//  and not an in-app checkout — Safari so the page is clearly the retailer's.
//

import SafariServices
import SwiftUI

struct ProductSourceSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
