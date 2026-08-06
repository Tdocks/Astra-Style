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
                                closeScanner()
                            }
                            .foregroundStyle(AstraColor.textSecondary)
                        }
                    }
                }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
        // Covers the swipe-dismiss, which reaches neither Close button.
        .onDisappear {
            discardUnsavedUpload()
            container.captureDraftStore.removeAll()
        }
    }

    /// Every exit that is not a save runs through here.
    ///
    /// The capture is already in `user-content` by the time the review
    /// screen renders — `uploadCapturedImage` runs before the user has
    /// decided anything — so leaving without saving strands the object with
    /// nothing referencing it. Dropping the local draft, which is all this
    /// used to do, removes the only thing that knew the path.
    ///
    /// The `Task` captures the view model strongly on purpose: it has to
    /// outlive the dismissal that fires immediately after, or the cleanup
    /// is cancelled by the very action that made it necessary. The view
    /// model's own guard makes the call a no-op after a successful save.
    private func discardUnsavedUpload() {
        guard let viewModel = reviewViewModel else { return }
        Task { await viewModel.discardUnsavedUpload() }
    }

    private func closeScanner() {
        discardUnsavedUpload()
        container.captureDraftStore.removeAll()
        dismiss()
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
                            closeScanner()
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
                onContinue: { ready in
                    let draft = CaptureDraft(
                        prepared: ready.prepared,
                        deviceHints: ready.deviceHints
                    )
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
                            captureSession: container.captureSession,
                            regionDetector: LiveVisionGarmentRegionDetector(),
                            textRecognizer: LiveVisionLabelTextRecognizer()
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
                        // Retake is the abandonment the user is most likely
                        // to repeat — three attempts at one garment leave
                        // three orphans without this.
                        discardUnsavedUpload()
                        Task { await container.pendingScanQueue.remove(id: draftID) }
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
                        pendingScanQueue: container.pendingScanQueue,
                        networkMonitor: container.networkMonitor,
                        analyticsClient: container.analyticsClient,
                        currentUserID: { await container.sessionStore.currentUserID() }
                    )
                )
            }
        }
    }
}
