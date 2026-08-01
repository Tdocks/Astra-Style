//
//  ScannerDestinationView.swift
//  AstraStyle
//
//  Resolves `ScannerRoute` (App/AppRouter.swift) for the modal scanner
//  flow (spec §4). Composition root for scanner screens — view models are
//  built here from `AppContainer`, never inside a leaf view.
//
//  Single-item capture pushes review onto an internal NavigationPath so
//  Retake can pop without dismissing the modal.
//

import SwiftUI

struct ScannerDestinationView: View {
    let route: ScannerRoute
    let container: AppContainer

    @Environment(\.dismiss) private var dismiss
    @State private var path: [ScannerRoute] = []
    @State private var captureViewModel: ScannerCaptureViewModel?
    @State private var reviewViewModel: ScannerReviewViewModel?

    var body: some View {
        NavigationStack(path: $path) {
            rootContent
                .navigationDestination(for: ScannerRoute.self) { destination in
                    destinationContent(destination)
                }
                .toolbar {
                    if showsChromeClose {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Close", comment: "Dismiss scanner modal")) {
                                container.captureDraftStore.removeAll()
                                dismiss()
                            }
                            .foregroundStyle(AstraColor.textSecondary)
                        }
                    }
                }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
        .onDisappear {
            container.captureDraftStore.removeAll()
        }
    }

    private var showsChromeClose: Bool {
        switch route {
        case .singleItem:
            // Capture root owns its Close toolbar; pushed review adds its own.
            false
        case .batchCloset, .receiptLabel, .outfitMirror, .review:
            true
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        switch route {
        case .singleItem:
            captureRoot
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
        case .review(let id):
            reviewScreen(draftID: id)
        }
    }

    @ViewBuilder
    private func destinationContent(_ destination: ScannerRoute) -> some View {
        switch destination {
        case .review(let id):
            reviewScreen(draftID: id)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Close", comment: "Dismiss scanner from review")) {
                            container.captureDraftStore.removeAll()
                            dismiss()
                        }
                        .foregroundStyle(AstraColor.textSecondary)
                    }
                }
        default:
            FeaturePlaceholderView(
                title: String(localized: "Scan", comment: "Generic scanner placeholder"),
                message: String(localized: "That capture mode is not built yet.", comment: "Generic scanner gap"),
                systemImage: "viewfinder"
            )
        }
    }

    @ViewBuilder
    private var captureRoot: some View {
        if let captureViewModel {
            ScannerCaptureView(
                viewModel: captureViewModel,
                captureSession: container.captureSession,
                onContinue: { prepared in
                    let draft = CaptureDraft(prepared: prepared)
                    container.captureDraftStore.put(draft)
                    path.append(.review(capturedImageID: draft.id))
                }
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
    }

    @ViewBuilder
    private func reviewScreen(draftID: UUID) -> some View {
        Group {
            if let reviewViewModel {
                ScannerReviewView(
                    viewModel: reviewViewModel,
                    onFinished: {
                        container.captureDraftStore.removeAll()
                        dismiss()
                    },
                    onRetake: {
                        container.captureDraftStore.remove(id: draftID)
                        self.reviewViewModel = nil
                        if path.isEmpty {
                            dismiss()
                        } else {
                            path.removeLast()
                            Task { await captureViewModel?.retake() }
                        }
                    }
                )
            } else {
                ProgressView()
                    .tint(AstraColor.accentChampagne)
            }
        }
        .task(id: draftID) {
            if reviewViewModel?.draftID != draftID {
                reviewViewModel = ScannerReviewViewModel(
                    draftID: draftID,
                    dependencies: .init(
                        draftStore: container.captureDraftStore,
                        closetRepository: container.closetRepository,
                        imageURLResolver: container.closetImageURLResolver,
                        analyticsClient: container.analyticsClient,
                        currentUserID: { await container.sessionStore.currentUserID() }
                    )
                )
            }
        }
    }
}
