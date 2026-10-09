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

    /// Called with the garment a completed scan created, before the modal
    /// dismisses.
    ///
    /// For the scanner's own entry points this is nil: the Closet reloads
    /// from the repository and does not need telling. Onboarding's
    /// first-items step does — it shows the list IT is building, not the
    /// closet, so a garment added through here would otherwise be saved and
    /// invisible on the screen that asked for it.
    var onItemSaved: ((ClosetItem) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var path: [ScannerRoute] = []
    @State private var captureViewModel: ScannerCaptureViewModel?
    @State private var reviewViewModel: ScannerReviewViewModel?
    @State private var batchViewModel: ScannerBatchViewModel?
    @State private var batchReviewProgressAlert = false
    /// Drafts from a batch that have NOT been reviewed yet. The one on
    /// screen is popped off when it is pushed, so this plus the review
    /// screen's own draft is the whole set of uploaded-but-unsaved objects.
    @State private var batchQueue: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            rootContent
                .navigationDestination(for: ScannerRoute.self) { destination in
                    destinationContent(destination)
                }
                .toolbar {
                    if path.isEmpty, route == .singleItem {
                        ToolbarItem(placement: .primaryAction) {
                            Menu("Capture mode") {
                                Button("Receipt or label") { path.append(.receiptLabel) }
                                    .accessibilityIdentifier("scanner.mode.receipt")
                                Button("Mirror photo") { path.append(.outfitMirror) }
                                Button("Batch closet photos") { path.append(.batchCloset) }
                            }
                            .accessibilityIdentifier("scanner.mode.menu")
                        }
                    }

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
        .alert(
            String(localized: "Couldn't save review progress", comment: "Batch review journal failure title"),
            isPresented: $batchReviewProgressAlert
        ) {
            Button(String(localized: "OK", comment: "Dismiss review progress alert"), role: .cancel) {}
        } message: {
            Text(String(
                localized: "Your place in this batch could not be saved. Try again before continuing.",
                comment: "Batch review journal failure message"
            ))
        }
        // Covers the swipe-dismiss, which reaches neither Close button.
        .onDisappear {
            // A batch journal is deliberately retained across an unplanned
            // disappearance so the app can restore review after relaunch.
            if batchViewModel?.hasPendingBatch != true {
                discardUnsavedUpload()
                discardQueuedBatch()
            }
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

    private var mirrorRoot: some View {
        MirrorCaptureView(viewModel: MirrorCaptureViewModel(
            repository: container.profileRepository,
            currentUserID: { await container.sessionStore.currentUserID() }
        ), onDone: { closeScanner() })
    }

    private var receiptRoot: some View {
        ReceiptCaptureView(onDone: { closeScanner() }, onItemSaved: onItemSaved, viewModel: ReceiptCaptureViewModel(
            recognizer: LiveVisionLabelTextRecognizer(),
            repository: container.closetRepository,
            currentUserID: { await container.sessionStore.currentUserID() }
        ))
    }

    @ViewBuilder
    private var rootContent: some View {
        switch route {
        case .singleItem:
            captureRoot
        case .batchCloset:
            batchRoot
        case .receiptLabel:
            receiptRoot
        case .outfitMirror:
            mirrorRoot
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
        case .receiptLabel:
            receiptRoot
        case .batchCloset:
            batchRoot
        case .outfitMirror:
            mirrorRoot
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
    private var batchRoot: some View {
        if let batchViewModel {
            ScannerBatchCaptureView(
                viewModel: batchViewModel,
                onReady: { draftIDs in
                    guard let first = draftIDs.first else { return }
                    batchQueue = Array(draftIDs.dropFirst())
                    path.append(.review(capturedImageID: first))
                }
            )
        } else {
            ProgressView()
                .tint(AstraColor.accentChampagne)
                .task {
                    if batchViewModel == nil {
                        batchViewModel = ScannerBatchViewModel(
                            dependencies: .init(
                                draftStore: container.captureDraftStore,
                                closetRepository: container.closetRepository,
                                currentOwnerID: { await container.sessionStore.currentUserID() },
                                pendingStore: FileScannerBatchPendingStore.live
                            )
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
                        Task {
                            await finishReview(
                                draftID: draftID,
                                savedItem: reviewViewModel.savedItem
                            )
                        }
                    },
                    onRetake: {
                        Task {
                            await skipReviewDraft(draftID, viewModel: reviewViewModel)
                        }
                    }
                )
            } else {
                ProgressView()
                    .tint(AstraColor.accentChampagne)
            }
        }
        .onChange(of: reviewViewModel?.phase) { _, newPhase in
            guard newPhase == .saved else { return }
            Task {
                guard let batchViewModel,
                      !(await batchViewModel.markDraftConsumed(draftID, saved: true)) else { return }
                batchReviewProgressAlert = true
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
                        scannerSaveJournal: container.scannerSaveJournal,
                        networkMonitor: container.networkMonitor,
                        analyticsClient: container.analyticsClient,
                        currentUserID: { await container.sessionStore.currentUserID() }
                    )
                )
            }
        }
    }

}

private extension ScannerDestinationView {
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
    func discardUnsavedUpload() {
        guard let viewModel = reviewViewModel else { return }
        Task { await viewModel.discardUnsavedUpload() }
    }

    func closeScanner() {
        if let batchViewModel, batchViewModel.hasPendingBatch {
            Task { await batchViewModel.discardPendingBatch() }
        } else {
            discardUnsavedUpload()
            discardQueuedBatch()
        }
        container.captureDraftStore.removeAll()
        dismiss()
    }

    /// A batch uploads every image before the user reviews any of them, so
    /// abandoning after garment three strands seventeen objects in
    /// `user-content` that nothing will ever reference. `discardUnsavedUpload`
    /// only knows about the one on screen.
    ///
    /// The paths are read out before the `Task` starts, because the draft
    /// store is cleared by the caller on the very next line — reading them
    /// inside would find an empty store.
    func discardQueuedBatch() {
        let paths = batchQueue.compactMap { container.captureDraftStore.draft(id: $0)?.storagePath }
        batchQueue = []
        guard !paths.isEmpty else { return }
        let repository = container.closetRepository
        Task {
            for path in paths {
                try? await repository.deleteCapturedImage(atPath: path)
            }
        }
    }

    /// Moves to the next garment in a batch, or finishes.
    ///
    /// Returns false when there is nothing left, so the caller can do
    /// whatever it does at the end of a single-item scan instead. Clearing
    /// `reviewViewModel` is what makes the pushed destination rebuild — the
    /// review screen keys its `.task` on `draftID`, and the path length is
    /// unchanged, so without this the same view model would be reused for a
    /// different garment.
    func advanceBatch() -> Bool {
        guard !batchQueue.isEmpty, !path.isEmpty else { return false }
        let next = batchQueue.removeFirst()
        reviewViewModel = nil
        // Replace rather than append: appending would leave a twenty-deep
        // stack of finished garments behind the one on screen, each of
        // whose drafts has already been removed from the store.
        path.removeLast()
        path.append(.review(capturedImageID: next))
        return true
    }

    @MainActor
    func finishReview(draftID: UUID, savedItem: ClosetItem?) async {
        if savedItem != nil {
            if let batchViewModel,
               !(await batchViewModel.markDraftConsumed(draftID, saved: true)) {
                batchReviewProgressAlert = true
                return
            }
            batchReviewProgressAlert = false
            if let savedItem { onItemSaved?(savedItem) }
        }
        container.captureDraftStore.remove(id: draftID)
        if advanceBatch() { return }
        container.captureDraftStore.removeAll()
        dismiss()
    }

    @MainActor
    func skipReviewDraft(_ draftID: UUID, viewModel: ScannerReviewViewModel) async {
        if batchViewModel?.hasPendingBatch == true {
            guard let batchViewModel,
                  await batchViewModel.markDraftConsumed(draftID, saved: false) else {
                batchReviewProgressAlert = true
                return
            }
        } else {
            await viewModel.discardUnsavedUpload()
        }
        await container.pendingScanQueue.remove(id: draftID)
        container.captureDraftStore.remove(id: draftID)
        reviewViewModel = nil
        if advanceBatch() { return }
        if path.isEmpty {
            dismiss()
        } else {
            path.removeLast()
            await captureViewModel?.retake()
        }
    }
}
