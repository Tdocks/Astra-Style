//
//  ScannerDestinationView.swift
//  AstraStyle
//
//  Resolves `ScannerRoute` (App/AppRouter.swift) for the modal scanner
//  flow (spec §4). Composition root for scanner screens — view models are
//  built here from `AppContainer`, never inside a leaf view.
//
//  This PR ships single-item capture (+ Photos import). Batch, receipt,
//  mirror, and review are answered honestly rather than with dead chrome
//  that pretends they work (spec §22).
//

import SwiftUI

struct ScannerDestinationView: View {
    let route: ScannerRoute
    let container: AppContainer

    @Environment(\.dismiss) private var dismiss
    @State private var captureViewModel: ScannerCaptureViewModel?

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    // Single-item capture owns its own Close control. Other
                    // modes are honest placeholders and still need a way out
                    // (spec §22 — no dead ends).
                    if routeNeedsChromeClose {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Close", comment: "Dismiss scanner modal")) {
                                dismiss()
                            }
                            .foregroundStyle(AstraColor.textSecondary)
                        }
                    }
                }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
    }

    private var routeNeedsChromeClose: Bool {
        switch route {
        case .singleItem: false
        case .batchCloset, .receiptLabel, .outfitMirror, .review: true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .singleItem:
            if let captureViewModel {
                ScannerCaptureView(
                    viewModel: captureViewModel,
                    captureSession: container.captureSession
                )
            } else {
                ProgressView()
                    .tint(AstraColor.accentChampagne)
                    .task {
                        if captureViewModel == nil {
                            captureViewModel = ScannerCaptureViewModel(
                                captureSession: container.captureSession
                            )
                        }
                    }
            }

        case .batchCloset:
            FeaturePlaceholderView(
                title: String(localized: "Batch Closet Scan", comment: "Scanner batch mode title"),
                message: String(localized: "Scan several pieces in one sitting. That capture mode is not built yet — use single-item scan for now.",
                                comment: "Honest gap: batch capture mode"),
                systemImage: "square.stack.3d.up"
            )

        case .receiptLabel:
            FeaturePlaceholderView(
                title: String(localized: "Scan a Label", comment: "Scanner receipt/label mode title"),
                message: String(localized: "Point at a care label or receipt to pull brand and size. That mode is not built yet.",
                                comment: "Honest gap: receipt/label mode"),
                systemImage: "doc.text.viewfinder"
            )

        case .outfitMirror:
            FeaturePlaceholderView(
                title: String(localized: "Mirror Photo", comment: "Scanner outfit mirror mode title"),
                message: String(localized: "Capture a full look in the mirror. That mode is not built yet.",
                                comment: "Honest gap: outfit mirror mode"),
                systemImage: "person.crop.rectangle"
            )

        case .review:
            FeaturePlaceholderView(
                title: String(localized: "Review Scan", comment: "Scanner review title"),
                message: String(localized: "Check what Kyra read from the photo and correct anything before it lands in your closet. That screen is not built yet.",
                                comment: "Honest gap: review screen"),
                systemImage: "checklist"
            )
        }
    }
}
